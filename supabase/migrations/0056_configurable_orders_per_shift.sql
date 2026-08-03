-- ============================================================
-- Tasu · 0056_configurable_orders_per_shift.sql
-- ============================================================
-- Бір ауысымға берілетін ЗАКАЗ САНЫН модератор өзі баптай алатын етеміз.
--
-- Бұрын: әр ауысымда қатаң 10 заказ (`buy_tariff()` ішінде хардкод).
-- Енді `app_settings.tariffs.orders_per_shift` (әдепкі 10) —
-- Модератор → Баптаулар → «Тариф бағасы» бөлімінен SQL-сыз өзгертіледі.
-- ============================================================

-- 1) Бар тарифке әдепкі мәнді ҚОСАМЫЗ (баға мен ұзақтықты сақтап, тек
--    жетпейтін кілтті толтырамыз — merge, overwrite емес).
update public.app_settings
set value = value || '{"orders_per_shift": 10}'::jsonb
where key = 'tariffs'
  and not (value ? 'orders_per_shift');

-- 2) buy_tariff() — енді app_settings.tariffs-тен оқиды.
create or replace function public.buy_tariff(p_kind text default 'simple')
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  ep record;
  v_price bigint;
  v_session uuid;
  v_orders int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into ep from public.executor_profiles where user_id = v_uid for update;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  -- Белсенді тариф (не триал) тұрса — қайта сатып алуға болмайды
  if public.exec_has_capacity(v_uid) then
    raise exception 'ALREADY_ACTIVE';
  end if;

  v_price := public.tariff_price_now('simple');
  if ep.balance < v_price then raise exception 'INSUFFICIENT_BALANCE'; end if;

  select (value->>'orders_per_shift')::int into v_orders
    from public.app_settings where key = 'tariffs';
  if v_orders is null or v_orders < 1 then v_orders := 10; end if;

  update public.executor_profiles set balance = balance - v_price where user_id = v_uid;

  insert into public.balance_txns (executor_id, amount, type, note)
  values (v_uid, -v_price, 'tariff_fee', 'Тариф (1 ауысым)');

  insert into public.tariff_sessions
    (executor_id, kind, fee, is_night, is_trial, orders_left, started_at, expires_at)
  values
    (v_uid, 'simple', v_price, public.is_night_now(), false, v_orders, now(),
     public.current_window_end())
  returning id into v_session;

  return jsonb_build_object('session_id', v_session, 'fee', v_price,
                            'orders_left', v_orders, 'expires_at', public.current_window_end());
end;
$$;
