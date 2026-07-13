-- Tasu · 0036_remove_vip_dispatch.sql
-- VIP/instant заказ тарату механизмі (0001-де құрылған) толық алып
-- тасталады: 0029_vehicle_types_single_tariff.sql-ден бастап create_order
-- ЕШҚАШАН type='instant' жасамайды (әрдайым 'bidding') — сол себепті
-- vip_dispatches кестесі мен оған қатысты RPC-тер, cron job әлдеқашан
-- өлі код. Клиент (Dart) жағы да толық тазаланды.
--
-- РЕТ МАҢЫЗДЫ (тәуелділіктер бойынша):
--   1) `gazelgo-vip-advance` cron job — әр 10 секунд сайын әлі жұмыс
--      істеп тұр, оны бірінші тоқтатпасақ, келесі қадамдарда функцияны
--      өшіргеннен кейін әр 10 секунд сайын қате лог жаза береді.
--   2) `orders_dispatched` RLS policy `has_my_dispatch()`-ке тәуелді —
--      policy-ні функциядан БҰРЫН өшіру керек (әйтпесе DROP FUNCTION
--      "cannot drop function ... because other objects depend on it"
--      қатесімен сәтсіз аяқталады).
--   3) `cancel_order`/`mod_cancel_order`/`expire_stale_orders` —
--      vip_dispatches/assign_next_vip-ге тиетін бөлікті алып тастап,
--      ҚАЛҒАН (bidding) логикасын толық сақтап қайта анықтаймыз.
--   4) Ең соңында кестені/enum-ды өшіреміз.
--
-- `order_type` enum-дағы 'instant' МӘНІ ӘДЕЙІ ҚАЛДЫРЫЛАДЫ: Postgres-те
-- enum мәнін өшіру күрделі әрі тарихи заказ жолдарында (ескі
-- type='instant') әлі де қолданылады — тек жаңа заказ енді солай
-- жасалмайды. Сол сияқты `orders.system_price` бағаны да қалады (ескі
-- instant заказдардың бағасын көрсету үшін, Order.displayPrice fallback).

-- ---------- 1) vip-advance cron job тоқтату ----------
do $$ begin
  perform cron.unschedule('gazelgo-vip-advance');
exception when others then null; end $$;

-- ---------- 2) vip_dispatches-ке тәуелді RLS policy/функция ----------
drop policy if exists orders_dispatched on public.orders;
drop function if exists public.has_my_dispatch(uuid);

-- ---------- 3) VIP-тек RPC-тер ----------
drop function if exists public.accept_vip(uuid);
drop function if exists public.decline_vip(uuid);
drop function if exists public.advance_vip(uuid);
drop function if exists public.advance_all_vip();
drop function if exists public.assign_next_vip(uuid);
drop function if exists public.set_auto_accept_vip(boolean);

-- ---------- 4) cancel_order: vip_dispatches/assign_next_vip тармақтары
--    алынып тасталды, қалғаны (bidding) өзгеріссіз ----------
create or replace function public.cancel_order(p_order uuid, p_reason text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_is_client boolean;
  v_is_executor boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  v_is_client := (o.client_id = v_uid);
  v_is_executor := (o.executor_id is not null and o.executor_id = v_uid);
  if not v_is_client and not v_is_executor then raise exception 'FORBIDDEN'; end if;
  if o.status in ('completed','cancelled','expired') then raise exception 'NOT_AVAILABLE'; end if;

  -- процесс кезеңі — бас тартуға болмайды
  if o.status in ('loading','in_transit') then raise exception 'CANNOT_CANCEL_IN_PROGRESS'; end if;

  -- searching: тек клиент
  if o.status = 'searching' and not v_is_client then raise exception 'FORBIDDEN'; end if;

  -- arrived: орындаушы бас тарта алмайды
  if o.status = 'arrived' and v_is_executor then raise exception 'CANNOT_CANCEL_IN_PROGRESS'; end if;

  -- қабылданғаннан кейін себеп міндетті
  if o.status <> 'searching' and coalesce(trim(p_reason),'') = '' then
    raise exception 'REASON_REQUIRED';
  end if;

  -- орындаушы қабылдағаннан кейін бас тартса: заказ жойылмайды, клиентке
  -- қайта заказ беруге тура келмеу үшін «іздеуде» күйіне қайта ашылады.
  -- Бұл — орындаушының ӨЗ шешімі, сондықтан шегерілген тариф лимиті
  -- ҚАЙТАРЫЛМАЙДЫ (charged_session_id заказда сол күйінде қалады —
  -- заказды келесі орындаушы қайта қабылдағанда consume_order оны
  -- өзінің сессиясымен қайта жазып басады).
  if v_is_executor and o.status = 'accepted' then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;

    update public.orders
       set status = 'searching', executor_id = null, accepted_at = null,
           final_price = null
     where id = p_order;

    update public.offers set status = 'rejected'
     where order_id = p_order and status in ('pending','accepted');

    return;
  end if;

  -- Осы жерге жеткен барлық жағдай — клиенттің бас тартуы (орындаушының
  -- барлық сценарийі жоғарыда FORBIDDEN/CANNOT_CANCEL/requeue-мен
  -- өңделіп қойды). Заказ 'searching' емес күйде болса (яғни орындаушыға
  -- тариф лимиті ЕСЕПТЕН ШЫҒАРЫЛҒАН болса) — орындаушының кінәсі жоқ
  -- болғандықтан лимит қайтарылады.
  update public.orders
     set status = 'cancelled', cancelled_by = v_uid, cancelled_at = now(),
         cancel_reason = coalesce(trim(p_reason),'')
   where id = p_order;

  if o.status <> 'searching' then
    perform public.refund_order_quota(p_order);
  end if;

  update public.offers set status = 'rejected'
   where order_id = p_order and status = 'pending';

  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;
end;
$$;

grant execute on function public.cancel_order(uuid,text) to authenticated;

-- ---------- 5) mod_cancel_order: vip_dispatches тармағы алынды ----------
create or replace function public.mod_cancel_order(p_order uuid, p_reason text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status in ('completed','cancelled','expired') then raise exception 'NOT_AVAILABLE'; end if;

  update public.orders
     set status = 'cancelled', cancelled_by = v_uid, cancelled_at = now(),
         cancel_reason = 'Модератор: ' || coalesce(trim(p_reason),'')
   where id = p_order;
  update public.offers set status = 'rejected'
   where order_id = p_order and status = 'pending';
  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;
end;
$$;

grant execute on function public.mod_cancel_order(uuid,text) to authenticated;

-- ---------- 6) expire_stale_orders: instant/vip_dispatches блогы алынды,
--    bidding-мерзімі өткен заказ логикасы (cron: gazelgo-expire-orders,
--    әр 5 минут сайын) өзгеріссіз қалады ----------
create or replace function public.expire_stale_orders()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.orders
     set status = 'expired'
   where type = 'bidding' and status = 'searching'
     and created_at < now() - interval '24 hours';
end;
$$;

-- ---------- 7) auto_accept_vip бағаны (executor_profiles) ----------
alter table public.executor_profiles drop column if exists auto_accept_vip;

-- ---------- 8) кесте мен enum ----------
drop table if exists public.vip_dispatches cascade;
drop type if exists public.dispatch_status;

-- ---------- 9) instant-баға есептеу (тек ескі create_order нұсқаларында
--    қолданылған, ағымдағы 0029 нұсқасы шақырмайды) ----------
drop function if exists public.instant_quote(text, numeric);
delete from public.app_settings where key = 'instant_pricing';
