-- GazelGo · 0028_order_push_notify.sql
-- Жаңа заказ push-хабарландыруы: бұрын executor_shell.dart тек қосымша
-- ашық/фонда тұрғанда poll арқылы хабарлайтын (Notify.show, foreground-only).
-- Пайдаланушы сұрады: тумблер (order notify) ҚОСУЛЫ тұрса, қосымша толық
-- ЖАБЫҚ болса да хабарлама келуі керек. Ол үшін орындаушының қалауы
-- СЕРВЕРДЕ сақталуы керек (жергілікті SharedPreferences жеткіліксіз —
-- триггер оны көрмейді).
--
-- Жаңа заказ келгенде — public.exec_can_take(...)-пен ДӘЛ СОЛ ереже бойынша
-- (тариф түрі, қала, белсенді заказы жоқтығы) сай келетін, order_push_enabled
-- қосулы орындаушыларға public.send_push (0025) арқылы broadcast жасалады.

alter table public.executor_profiles
  add column if not exists order_push_enabled boolean not null default true;

-- ---------- орындаушы өз қалауын серверге сақтайды ----------
create or replace function public.set_order_push_enabled(p_enabled boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.executor_profiles
     set order_push_enabled = p_enabled
   where user_id = auth.uid();
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;
revoke all on function public.set_order_push_enabled(boolean) from public, anon;
grant execute on function public.set_order_push_enabled(boolean) to authenticated;

-- ---------- жаңа заказ келгенде сай орындаушыларға push ----------
create or replace function public.notify_executors_new_order()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
begin
  if new.status <> 'searching' then return new; end if;

  select array_agg(ep.user_id) into v_ids
  from public.executor_profiles ep
  where ep.status = 'approved'
    and ep.order_push_enabled = true
    and public.exec_can_take(ep.user_id, new.id);

  if v_ids is null or array_length(v_ids, 1) = 0 then return new; end if;

  perform public.send_push(
    'Жаңа заказ',
    'Сізге сай жаңа заказ шықты — тезірек қараңыз.',
    jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
    v_ids
  );
  return new;
exception when others then
  -- push шақыруы сәтсіз болса да, заказ құру үзілмеуі керек
  return new;
end;
$$;

drop trigger if exists trg_notify_executors_new_order on public.orders;
create trigger trg_notify_executors_new_order
  after insert on public.orders
  for each row execute function public.notify_executors_new_order();
