-- ============================================================
-- Тариф лимитін ("orders_left") дұрыс есептеу: қазірге дейін
-- consume_order() тек accept_offer() кезінде шақырылады да, кейін
-- ЕШҚАШАН қайтарылмайды — заказды кім тоқтатса да (клиент не
-- орындаушы) орындаушының лимиті шегерулі күйінде қалады.
--
-- Дұрыс логика:
--   - Орындаушы ӨЗІ қабылданған заказдан бас тартса (cancel_order-дың
--     "requeue" тармағы) — лимит ҚАЙТАРЫЛМАЙДЫ (өз кінәсі, -1 болып
--     қалады). Бұл тармақ өзгермейді.
--   - Клиент қабылданған/жеткен заказдан бас тартса — орындаушының
--     кінәсі жоқ, сондықтан шегерілген лимит ОРЫНДАУШЫҒА ҚАЙТАРЫЛУЫ
--     керек.
--
-- Іске асыру: әр заказда қай tariff_sessions жазбасынан шегерілгені
-- charged_session_id-де сақталады (триал болса — null, өйткені
-- триалда ештеңе шегерілмейді). Клиент бас тартқанда сол сессияға
-- +1 қайтарылады.
--
-- Сонымен қатар 0018_abuse_limits.sql-дегі «спам-заказ» қорғанысындағы
-- қате түзетіледі: check_client_order_abuse() соңғы 60 минутта ӨЗІ
-- тоқтатқан заказдарды created_at (заказ АШЫЛҒАН уақыт) бойынша санап
-- жүрген — дұрысы cancelled_at (заказ ТОҚТАТЫЛҒАН уақыт) болу керек,
-- өйткені created_at ескі заказ болса, оны тоқтатқан сәтте терезеден
-- шығып кетуі мүмкін (клиент 2+ сағат бұрын ашқан 3 заказды қатарынан
-- тоқтатса — қазіргі кодпен ешқашан бұғатталмайды). Бұл үшін orders-ке
-- cancelled_at бағаны қосылады.
-- ============================================================

alter table public.orders
  add column if not exists charged_session_id uuid references public.tariff_sessions(id);

alter table public.orders
  add column if not exists cancelled_at timestamptz;

-- ---------- consume_order: енді қай сессиядан шегергенін заказға жазады ----------
drop function if exists public.consume_order(uuid);

create function public.consume_order(p_exec uuid, p_order uuid default null)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if public.exec_trial_active(p_exec) then
    return;  -- тегін кезең — шегерілмейді, қайтаратын да ештеңе жоқ
  end if;
  select id into v_id from public.tariff_sessions
   where executor_id = p_exec and not is_trial
     and coalesce(orders_left,0) > 0 and expires_at > now()
   order by orders_left asc, started_at asc
   limit 1;
  if v_id is not null then
    update public.tariff_sessions set orders_left = orders_left - 1 where id = v_id;
    if p_order is not null then
      update public.orders set charged_session_id = v_id where id = p_order;
    end if;
  end if;
end;
$$;

revoke execute on function public.consume_order(uuid, uuid) from public, anon, authenticated;

-- ---------- жаңа: заказ бойынша шегерілген лимитті қайтару ----------
create or replace function public.refund_order_quota(p_order uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_session uuid;
begin
  select charged_session_id into v_session from public.orders where id = p_order;
  if v_session is null then return; end if;

  update public.tariff_sessions set orders_left = orders_left + 1 where id = v_session;
  update public.orders set charged_session_id = null where id = p_order;
end;
$$;

revoke execute on function public.refund_order_quota(uuid) from public, anon, authenticated;

-- ---------- accept_offer: consume_order-ге заказ id-ін қоса береді ----------
create or replace function public.accept_offer(p_offer uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order_id uuid;
  o record;
  ofr record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select order_id into v_order_id from public.offers where id = p_offer;
  if v_order_id is null then raise exception 'NOT_FOUND'; end if;

  select * into o from public.orders where id = v_order_id for update;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  select * into ofr from public.offers where id = p_offer for update;
  if ofr.status <> 'pending' then raise exception 'OFFER_GONE'; end if;

  if not public.exec_has_capacity(ofr.executor_id) then raise exception 'EXEC_NO_ORDERS'; end if;
  if not public.exec_can_take(ofr.executor_id, v_order_id) then raise exception 'EXEC_BUSY'; end if;

  update public.offers set status = 'accepted' where id = p_offer;
  update public.offers set status = 'rejected'
   where order_id = v_order_id and id <> p_offer and status = 'pending';
  update public.orders
     set executor_id = ofr.executor_id, final_price = ofr.price,
         status = 'accepted', accepted_at = now()
   where id = v_order_id;
  update public.executor_profiles set busy_order_id = v_order_id
   where user_id = ofr.executor_id;

  perform public.consume_order(ofr.executor_id, v_order_id);

  return jsonb_build_object('order_id', v_order_id, 'executor_id', ofr.executor_id);
end;
$$;

grant execute on function public.accept_offer(uuid) to authenticated;

-- ---------- cancel_order: клиент бас тартқанда лимит қайтарылады ----------
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
    update public.vip_dispatches set status = 'expired'
     where order_id = p_order and status = 'pending';

    if o.type = 'instant' then
      perform public.assign_next_vip(p_order);
    end if;
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

  update public.vip_dispatches set status = 'expired'
   where order_id = p_order and status = 'pending';
  update public.offers set status = 'rejected'
   where order_id = p_order and status = 'pending';

  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;
end;
$$;

grant execute on function public.cancel_order(uuid,text) to authenticated;

-- ---------- mod_cancel_order: cancelled_at қосылды (үйлесімділік үшін) ----------
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
  update public.vip_dispatches set status = 'expired'
   where order_id = p_order and status = 'pending';
  update public.offers set status = 'rejected'
   where order_id = p_order and status = 'pending';
  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;
end;
$$;

grant execute on function public.mod_cancel_order(uuid,text) to authenticated;

-- ---------- check_client_order_abuse: created_at емес, cancelled_at бойынша ----------
create or replace function public.check_client_order_abuse()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_cancels int;
begin
  select count(*) into v_cancels
    from public.orders o
   where o.client_id = new.client_id
     and o.status = 'cancelled'
     and o.cancelled_by = new.client_id
     and coalesce(o.cancelled_at, o.created_at) > now() - interval '60 minutes';
  if v_cancels >= 3 then
    raise exception 'TOO_MANY_CANCELS';
  end if;
  return new;
end;
$$;
