-- GazelGo · 0029_vehicle_types_single_tariff.sql
-- Пайдаланушы сұраған өзгерістер:
--   • КӨЛІК ТҮРІ (vehicle_type): Газель, Фургон, КамАЗ, Кран, Манипулятор,
--     Ассенизатор, Экскаватор, Погрузчик, Мини вэн, Трактор 3в1.
--     Орындаушы тіркелгенде түрін таңдайды; клиент заказ бергенде түрін
--     таңдайды; заказ ТЕК сол түрдегі орындаушыларға көрінеді.
--   • ТАРИФ БІРЫҢҒАЙ: Простой/VIP жоқ, бір ғана тариф. Бағасы 300 ₸
--     (күндіз де, түнде де). Ауысым/10 заказ механикасы өзгеріссіз.
--   • Клиент заказ санатын (тарифін) ТАҢДАМАЙДЫ — бәрі бірыңғай.
--   • Жаңа расталған орындаушыларға 1 АЙ ТЕГІН (бұрынғы 24 сағат орнына).
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек.
-- 0028-ден КЕЙІН орындаңыз.

-- ============================================================
-- 0) Схема: vehicle_type бағандары
-- ============================================================
alter table public.executor_profiles
  add column if not exists vehicle_type text not null default 'gazelle';
alter table public.orders
  add column if not exists vehicle_type text not null default 'gazelle';

do $$ begin
  alter table public.executor_profiles
    add constraint executor_profiles_vehicle_type_check check (vehicle_type in
      ('gazelle','furgon','kamaz','crane','manipulator','assenizator',
       'excavator','loader','minivan','tractor'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.orders
    add constraint orders_vehicle_type_check check (vehicle_type in
      ('gazelle','furgon','kamaz','crane','manipulator','assenizator',
       'excavator','loader','minivan','tractor'));
exception when duplicate_object then null; end $$;

create index if not exists idx_orders_vehicle_type
  on public.orders (vehicle_type) where status = 'searching';

-- ============================================================
-- 1) Тариф бағасы: бірыңғай 300 ₸ (күн/түн бірдей)
-- ============================================================
insert into public.app_settings (key, value) values
  ('tariffs', '{"simple_day": 300, "simple_night": 300, "vip_day": 300, "vip_night": 300}')
on conflict (key) do update set value = excluded.value;

-- ============================================================
-- 2) Сыйымдылық — санатсыз (бір ғана тариф)
-- ============================================================

-- Белсенді тариф бар ма: ауысым бітпеген ЖӘНЕ лимит қалған сессия, не триал.
create or replace function public.exec_has_capacity(p_exec uuid)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tariff_sessions
    where executor_id = p_exec
      and ((not is_trial and coalesce(orders_left,0) > 0 and expires_at > now())
        or (is_trial and expires_at > now()))
  );
$$;

-- Орындаушы осы заказды ала ала ма? (§5/§6 + КӨЛІК ТҮРІ сәйкестігі)
create or replace function public.exec_can_take(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
  exec_city text;
  o_from text; o_to text;
  o_intercity boolean;
  has_active boolean;
  base_visible boolean;
  route_visible boolean;
  can_stack boolean;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found or ep.status <> 'approved' then return false; end if;
  if o.client_id = p_exec then return false; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  -- Бірыңғай тариф: белсенді тариф (не триал) болуы керек
  if not public.exec_has_capacity(p_exec) then return false; end if;

  exec_city := public.norm_city(ep.city);
  o_from := public.norm_city(o.from_city);
  o_to   := public.norm_city(o.to_city);
  o_intercity := (o_from is not null and o_to is not null and o_from <> o_to);

  base_visible := (exec_city is null) or (o_from is not null and o_from = exec_city);

  has_active := exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit'));

  route_visible := o_intercity and exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit')
      and public.norm_city(a.from_city) is not null
      and public.norm_city(a.to_city) is not null
      and public.norm_city(a.from_city) <> public.norm_city(a.to_city)
      and public.norm_city(a.to_city) = o_to);

  if not (base_visible or route_visible) then return false; end if;
  if not has_active then return true; end if;

  can_stack := o_intercity and exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit')
      and public.norm_city(a.from_city) is not null
      and public.norm_city(a.to_city) is not null
      and public.norm_city(a.from_city) <> public.norm_city(a.to_city)
      and (public.norm_city(a.to_city) = o_to
        or public.norm_city(a.from_city) = o_from));
  return can_stack;
end;
$$;

-- Заказ қабылданғанда лимиттен 1 шегеру (триал болса — тегін).
-- Ескі екі нұсқаны да өшіріп (0013 1-арг, 0014 2-арг), біреуін қалдырамыз.
drop function if exists public.consume_order(uuid);
drop function if exists public.consume_order(uuid, public.tariff_kind);
create function public.consume_order(p_exec uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if public.exec_trial_active(p_exec) then
    return;  -- тегін кезең — шегерілмейді
  end if;
  select id into v_id from public.tariff_sessions
   where executor_id = p_exec and not is_trial
     and coalesce(orders_left,0) > 0 and expires_at > now()
   order by orders_left asc, started_at asc
   limit 1;
  if v_id is not null then
    update public.tariff_sessions set orders_left = orders_left - 1 where id = v_id;
  end if;
end;
$$;

-- ============================================================
-- 3) §7 Жаңа орындаушыға 1 АЙ тегін (бұрын 24 сағат еді)
-- ============================================================
create or replace function public.grant_trial(p_exec uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare ep record;
begin
  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found or ep.trial_granted then return; end if;
  insert into public.tariff_sessions
    (executor_id, kind, fee, is_night, is_trial, orders_left, started_at, expires_at)
  values
    (p_exec, 'simple', 0, public.is_night_now(), true, null, now(), now() + interval '30 days');
  update public.executor_profiles set trial_granted = true where user_id = p_exec;
end;
$$;

-- ============================================================
-- 4) Тариф сатып алу — бірыңғай (p_kind еленбейді, 'simple' жазылады)
-- ============================================================
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

  update public.executor_profiles set balance = balance - v_price where user_id = v_uid;

  insert into public.balance_txns (executor_id, amount, type, note)
  values (v_uid, -v_price, 'tariff_fee', 'Тариф (1 ауысым)');

  insert into public.tariff_sessions
    (executor_id, kind, fee, is_night, is_trial, orders_left, started_at, expires_at)
  values
    (v_uid, 'simple', v_price, public.is_night_now(), false, 10, now(),
     public.current_window_end())
  returning id into v_session;

  return jsonb_build_object('session_id', v_session, 'fee', v_price,
                            'orders_left', 10, 'expires_at', public.current_window_end());
end;
$$;

-- ============================================================
-- 5) Заказ құру — КӨЛІК ТҮРІМЕН, тариф санатысыз (бәрі 'simple')
-- ============================================================
-- Ескі қолтаңбаларды өшіреміз (overload шатасуын болдырмау үшін).
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text);
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text,text);

create function public.create_order(
  p_type text,
  p_from_address text, p_from_lat float8, p_from_lng float8,
  p_to_address text,   p_to_lat float8,   p_to_lng float8,
  p_distance_km numeric,
  p_cargo text, p_comment text,
  p_size text,
  p_client_price bigint default null,
  p_photos text[] default '{}',
  p_from_city text default null,
  p_to_city text default null,
  p_tariff text default 'simple',
  p_vehicle_type text default 'gazelle'
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_vehicle text;
  v_id uuid;
  v_active int;
  v_intercity boolean;
  v_min bigint;
  v_from_city text;
  v_to_city text;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'client') then
    raise exception 'NOT_CLIENT';
  end if;

  v_vehicle := coalesce(nullif(trim(p_vehicle_type),''), 'gazelle');
  if v_vehicle not in ('gazelle','furgon','kamaz','crane','manipulator',
                       'assenizator','excavator','loader','minivan','tractor') then
    raise exception 'BAD_VEHICLE_TYPE';
  end if;

  if coalesce(trim(p_from_address),'') = '' or coalesce(trim(p_to_address),'') = ''
     or coalesce(trim(p_cargo),'') = '' then
    raise exception 'BAD_INPUT';
  end if;

  if p_from_lat < 40 or p_from_lat > 56 or p_from_lng < 46 or p_from_lng > 88
     or p_to_lat < 40 or p_to_lat > 56 or p_to_lng < 46 or p_to_lng > 88 then
    raise exception 'OUT_OF_KZ';
  end if;

  select count(*) into v_active from public.orders
  where client_id = v_uid
    and status in ('searching','accepted','arrived','loading','in_transit');
  if v_active >= 5 then raise exception 'TOO_MANY_ACTIVE'; end if;

  v_from_city := nullif(trim(coalesce(p_from_city,'')),'');
  v_to_city   := nullif(trim(coalesce(p_to_city,'')),'');

  v_intercity := (public.norm_city(v_from_city) is not null
                  and public.norm_city(v_to_city) is not null
                  and public.norm_city(v_from_city) <> public.norm_city(v_to_city));
  select coalesce((value->>(case when v_intercity then 'intercity' else 'city' end))::bigint,
                  case when v_intercity then 1000 else 100 end)
    into v_min from public.app_settings where key = 'order_min';
  v_min := coalesce(v_min, case when v_intercity then 1000 else 100 end);

  if p_client_price is null or p_client_price < v_min then
    if v_intercity then raise exception 'MIN_INTERCITY';
    else raise exception 'MIN_CITY'; end if;
  end if;

  insert into public.orders
    (client_id, type, tariff, vehicle_type, from_address, from_lat, from_lng, from_city,
     to_address, to_lat, to_lng, to_city, distance_km, cargo_desc, comment, size,
     client_price, system_price, photos)
  values
    (v_uid, 'bidding', 'simple', v_vehicle,
     trim(p_from_address), p_from_lat, p_from_lng, v_from_city,
     trim(p_to_address), p_to_lat, p_to_lng, v_to_city, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), 'small',
     p_client_price, null, coalesce(p_photos, '{}'))
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'intercity', v_intercity,
                            'vehicle_type', v_vehicle);
end;
$$;

-- ============================================================
-- 6) Ұсыныс беру — бірыңғай тариф + көлік түрі (exec_can_take ішінде)
-- ============================================================
create or replace function public.place_offer(p_order uuid, p_price bigint, p_message text default '')
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  ep record;
  v_existing record;
  v_id uuid;
  v_intercity boolean;
  v_min bigint;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into ep from public.executor_profiles where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  if not public.exec_has_capacity(v_uid) then raise exception 'NO_ORDERS_LEFT'; end if;
  if not public.exec_can_take(v_uid, p_order) then raise exception 'NOT_ELIGIBLE'; end if;

  v_intercity := (public.norm_city(o.from_city) is not null
                  and public.norm_city(o.to_city) is not null
                  and public.norm_city(o.from_city) <> public.norm_city(o.to_city));
  select coalesce((value->>(case when v_intercity then 'intercity' else 'city' end))::bigint,
                  case when v_intercity then 1000 else 100 end)
    into v_min from public.app_settings where key = 'order_min';
  v_min := coalesce(v_min, case when v_intercity then 1000 else 100 end);
  if p_price is null or p_price < v_min then
    if v_intercity then raise exception 'MIN_INTERCITY';
    else raise exception 'MIN_CITY'; end if;
  end if;

  select * into v_existing from public.offers
  where order_id = p_order and executor_id = v_uid for update;

  if found then
    if v_existing.status = 'accepted' then raise exception 'ALREADY_ACCEPTED'; end if;
    update public.offers
       set price = p_price, message = coalesce(trim(p_message),''),
           status = 'pending', created_at = now()
     where id = v_existing.id;
    return v_existing.id;
  end if;

  insert into public.offers (order_id, executor_id, price, message)
  values (p_order, v_uid, p_price, coalesce(trim(p_message),''))
  returning id into v_id;
  return v_id;
end;
$$;

-- ============================================================
-- 7) Ұсынысты қабылдау — бірыңғай лимиттен шегеру
-- ============================================================
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

  perform public.consume_order(ofr.executor_id);

  return jsonb_build_object('order_id', v_order_id, 'executor_id', ofr.executor_id);
end;
$$;

-- ============================================================
-- 8) executor_stats — бірыңғай тариф (ескі кілттер де қайтарылады —
--    ескі қосымша нұсқалары құламауы үшін)
-- ============================================================
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
  v_left bigint;
  v_until timestamptz;
  v_trial timestamptz;
  v_price bigint;
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

  select coalesce(sum(orders_left),0), max(expires_at)
    into v_left, v_until from public.tariff_sessions
   where executor_id = v_uid and not is_trial
     and coalesce(orders_left,0) > 0 and expires_at > now();
  select max(expires_at) into v_trial from public.tariff_sessions
   where executor_id = v_uid and is_trial and expires_at > now();

  v_price := public.tariff_price_now('simple');

  return jsonb_build_object(
    'balance', ep.balance,
    'total_earned', ep.total_earned,
    'today', v_today,
    'month', v_month,
    'busy_order_id', ep.busy_order_id,
    'orders_left', v_left,
    'left', v_left,
    'until', v_until,
    'trial_until', v_trial,
    'has_tariff', public.exec_has_capacity(v_uid),
    'is_night', public.is_night_now(),
    'price', v_price,
    'vehicle_year', ep.vehicle_year,
    'vehicle_type', ep.vehicle_type,
    'on_line', ep.on_line,
    'city', ep.city,
    -- ескі кілттер (кері үйлесімділік):
    'simple_left', v_left,
    'vip_left', 0,
    'simple_until', v_until,
    'vip_until', null,
    'simple_active', public.exec_has_capacity(v_uid),
    'vip_active', false,
    'price_simple', v_price,
    'price_vip', v_price
  );
end;
$$;

-- ============================================================
-- 9) mod_line_stats — көлік түрі + бірыңғай тариф белгісі
-- ============================================================
create or replace function public.mod_line_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_searching_bidding int;
  v_active_orders int;
  v_online jsonb;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  select count(*) into v_searching_bidding from public.orders
   where status = 'searching' and type = 'bidding';
  select count(*) into v_active_orders from public.orders
   where status in ('accepted','arrived','loading','in_transit');

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_online
  from (
    select ep.user_id,
           p.full_name,
           p.avatar_url,
           ep.vehicle_type,
           ep.busy_order_id,
           ep.on_line,
           public.exec_has_capacity(ep.user_id) as tariff_on,
           public.exec_trial_active(ep.user_id) as trial_on
    from public.executor_profiles ep
    join public.profiles p on p.id = ep.user_id
    where ep.status = 'approved'
      and public.exec_has_capacity(ep.user_id)
    order by p.full_name
  ) t;

  return jsonb_build_object(
    'searching_bidding', v_searching_bidding,
    'searching_instant', 0,
    'active_orders', v_active_orders,
    'online', v_online
  );
end;
$$;

grant execute on function public.mod_line_stats() to authenticated;

-- ============================================================
-- 10) Grants
-- ============================================================
revoke execute on function public.exec_has_capacity(uuid) from public, anon, authenticated;
revoke execute on function public.consume_order(uuid) from public, anon, authenticated;
revoke execute on function public.grant_trial(uuid) from public, anon, authenticated;

grant execute on function public.buy_tariff(text) to authenticated;
grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,
  text[],text,text,text,text) to authenticated;
grant execute on function public.place_offer(uuid,bigint,text) to authenticated;
grant execute on function public.accept_offer(uuid) to authenticated;
grant execute on function public.executor_stats() to authenticated;
