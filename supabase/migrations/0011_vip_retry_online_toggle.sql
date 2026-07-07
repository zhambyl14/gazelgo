-- GazelGo · 0011_vip_retry_online_toggle.sql
-- 1) Орындаушы тариф сатып алса да, өзі "линияда/демалыста" ауыса алады
--    (VIP тағайындау мен жаңа заказ хабарламалары тек линиядағыларға барады).
-- 2) VIP таратуды шексіз циклге айналдыру: бәріне 1 рет ұсынылып біткен соң
--    ешкім қабылдамаса — ең ұзақ күткеннен бастап қайтадан ұсына береді.
-- 3) VIP диалогта бағаны жасыру (қабылдағанша көрінбейді) — бас тартулар азаяды.
-- 4) Жауап беру терезесі 20с → 25с (ашылу/render кідірісіне қосымша уақыт).
-- 5) "Автоматты қабылдау": қосулы болса, VIP заказ терезесіз бірден тағайындалады
--    (ешкім жіберіп алмайды), тек хабарлама келеді.

alter table public.executor_profiles
  add column if not exists on_line boolean not null default true;
alter table public.executor_profiles
  add column if not exists auto_accept_vip boolean not null default false;

-- ============ орындаушы: линия ауыстыру ============
create or replace function public.set_on_line(p_value boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  update public.executor_profiles set on_line = p_value where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

grant execute on function public.set_on_line(boolean) to authenticated;

-- ============ орындаушы: VIP автоматты қабылдау ауыстыру ============
create or replace function public.set_auto_accept_vip(p_value boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  update public.executor_profiles set auto_accept_vip = p_value where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

grant execute on function public.set_auto_accept_vip(boolean) to authenticated;

-- ============ executor_stats: on_line + auto_accept_vip қосу ============
create or replace function public.executor_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  ep record;
  v_day_start timestamptz;
  v_month_start timestamptz;
  v_today bigint;
  v_month bigint;
  v_simple timestamptz;
  v_vip timestamptz;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into ep from public.executor_profiles where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;

  v_day_start := date_trunc('day', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';

  select coalesce(sum(amount),0) into v_today from public.earnings
   where executor_id = v_uid and created_at >= v_day_start;
  select coalesce(sum(amount),0) into v_month from public.earnings
   where executor_id = v_uid and created_at >= v_month_start;

  select max(expires_at) into v_simple from public.tariff_sessions
   where executor_id = v_uid and kind = 'simple' and expires_at > now();
  select max(expires_at) into v_vip from public.tariff_sessions
   where executor_id = v_uid and kind = 'vip' and expires_at > now();

  return jsonb_build_object(
    'balance', ep.balance,
    'total_earned', ep.total_earned,
    'today', v_today,
    'month', v_month,
    'busy_order_id', ep.busy_order_id,
    'simple_until', v_simple,
    'vip_until', v_vip,
    'is_night', public.is_night_now(),
    'price_simple', public.tariff_price_now('simple'),
    'price_vip', public.tariff_price_now('vip'),
    'on_line', ep.on_line,
    'auto_accept_vip', ep.auto_accept_vip
  );
end;
$$;

-- ============ VIP таратуды циклдік ету + линия/автоқабылдау ============
create or replace function public.assign_next_vip(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
  v_exec uuid;
  v_auto boolean;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.type <> 'instant' or o.status <> 'searching' then return; end if;

  update public.vip_dispatches
     set status = 'expired'
   where order_id = p_order and status = 'pending' and expires_at <= now();

  if exists (select 1 from public.vip_dispatches
             where order_id = p_order and status = 'pending' and expires_at > now()) then
    return;
  end if;

  -- алдымен ешқашан ұсынылмағандар (жаңалар), содан соң ең ұзақ күткендер —
  -- осылай бәріне 1 рет ұсынылып біткен соң циклдей бастайды.
  select ep.user_id, ep.auto_accept_vip into v_exec, v_auto
  from public.executor_profiles ep
  join public.profiles p on p.id = ep.user_id
  where ep.status = 'approved'
    and ep.vehicle_size = o.size
    and ep.busy_order_id is null
    and ep.on_line = true
    and exists (select 1 from public.tariff_sessions ts
                where ts.executor_id = ep.user_id
                  and ts.kind = 'vip' and ts.expires_at > now())
  order by
    (select max(d.created_at) from public.vip_dispatches d
      where d.order_id = p_order and d.executor_id = ep.user_id) nulls first,
    p.rating desc,
    random()
  limit 1;

  if v_exec is null then return; end if;

  if v_auto then
    -- автоматты қабылдау: терезесіз бірден тағайындау (жіберіп алу мүмкін емес)
    insert into public.vip_dispatches (order_id, executor_id, status, expires_at)
    values (p_order, v_exec, 'accepted', now());
    update public.orders
       set executor_id = v_exec, final_price = o.system_price,
           status = 'accepted', accepted_at = now()
     where id = p_order;
    update public.executor_profiles set busy_order_id = p_order where user_id = v_exec;
  else
    insert into public.vip_dispatches (order_id, executor_id, expires_at)
    values (p_order, v_exec, now() + interval '25 seconds');
  end if;
end;
$$;

-- ============ Линия панелі: on_line өрісін қосу ============
create or replace function public.mod_line_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_searching_bidding int;
  v_searching_instant int;
  v_active_orders int;
  v_online jsonb;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  select count(*) into v_searching_bidding from public.orders
   where status = 'searching' and type = 'bidding';
  select count(*) into v_searching_instant from public.orders
   where status = 'searching' and type = 'instant';
  select count(*) into v_active_orders from public.orders
   where status in ('accepted','arrived','loading','in_transit');

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_online
  from (
    select ep.user_id,
           p.full_name,
           p.avatar_url,
           ep.vehicle_size,
           ep.busy_order_id,
           ep.on_line,
           exists (select 1 from public.tariff_sessions ts
                   where ts.executor_id = ep.user_id
                     and ts.kind = 'simple' and ts.expires_at > now()) as simple_on,
           exists (select 1 from public.tariff_sessions ts
                   where ts.executor_id = ep.user_id
                     and ts.kind = 'vip' and ts.expires_at > now()) as vip_on
    from public.executor_profiles ep
    join public.profiles p on p.id = ep.user_id
    where ep.status = 'approved'
      and exists (select 1 from public.tariff_sessions ts
                  where ts.executor_id = ep.user_id and ts.expires_at > now())
    order by p.full_name
  ) t;

  return jsonb_build_object(
    'searching_bidding', v_searching_bidding,
    'searching_instant', v_searching_instant,
    'active_orders', v_active_orders,
    'online', v_online
  );
end;
$$;

grant execute on function public.executor_stats() to authenticated;
grant execute on function public.mod_line_stats() to authenticated;
