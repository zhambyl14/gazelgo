-- ============================================================
-- Tasu · 0060_client_features_batch.sql
-- ============================================================
-- Клиентке пайдалы 4 жаңа фича — БӘРІ модератор баптауында (app_settings)
-- қосу/өшіру арқылы басқарылады:
--   1) АЛДЫН АЛА ТАПСЫРЫС (scheduled_orders) — orders.scheduled_at.
--      Enum ӨЗГЕРТІЛМЕЙДІ (статус әрдайым 'searching' болып қалады) —
--      орындаушыға тек scheduled_at әлі келмеген заказ КӨРІНБЕЙДІ
--      (exec_can_see), scheduled_at жеткен соң автоматты (cron-сыз, тек
--      уақыт шарты) көрінеді.
--   2) ОРЫНДАУШЫНЫ КАРТАДА ТІРІ КӨРСЕТУ (live_tracking) — executor_locations
--      кестесі + update/get RPC, polling арқылы (Realtime 4G-де құлайды,
--      бұрыннан барлық стрим polling-ке көшірілген).
--   3) САПАРДЫ БӨЛІСУ (share_trip) — orders.share_token + анонимді
--      track_order(token) RPC (авторизациясыз да шақырылады).
--   4) ЖАТТЫҚҚА ШАҚЫРУ БОНУСЫ (referral) — profiles.referral_code/
--      referred_by/referral_count. ТЕК ҰПАЙ/САНАҚ (пайдаланушы 2026-08-07
--      таңдады) — балансқа/ақшаға ЕШҚАНДАЙ әсері жоқ, тек профильде
--      «Сіз N адам шақырдыңыз» көрсетіледі.
--
-- Тапсырысты қайталау мен ұсынылған баға көрсеткіші — ТЕК клиент жағында
-- (schema өзгерісі қажет емес), тек app_settings-ке жаңа кілт қосылады.
--
-- ЕСКЕРТУ: идемпотентті, SQL Editor-да ҚОЛМЕН қолдану керек (Supabase MCP
-- бұл сессияда авторизацияланбаған).
-- ============================================================

-- ============================================================
-- 0) mod_update_setting allow-list кеңейту
-- ============================================================
create or replace function public.mod_update_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if p_key not in (
    'tariffs', 'payment', 'version_gate', 'order_min', 'vehicle_rules',
    'listings', 'taxi', 'topup_bot', 'support_bot', 'bonus',
    'repeat_order', 'pricing_hint', 'scheduled_orders', 'live_tracking',
    'share_trip', 'referral'
  ) then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

-- Әдепкі баптаулар — модератор экраны бірінші рет ашылғанда бос болмауы
-- үшін. `on conflict do nothing` — бар болса тимейді.
insert into public.app_settings (key, value) values
  ('repeat_order', jsonb_build_object('enabled', true)),
  ('pricing_hint', jsonb_build_object('enabled', true)),
  ('scheduled_orders', jsonb_build_object(
    'enabled', false, 'min_hours_ahead', 2, 'max_days_ahead', 14
  )),
  ('live_tracking', jsonb_build_object('enabled', false)),
  ('share_trip', jsonb_build_object('enabled', false)),
  ('referral', jsonb_build_object(
    'enabled', false, 'executor_bonus_amount', 200
  ))
on conflict (key) do nothing;

-- ============================================================
-- 1) АЛДЫН АЛА ТАПСЫРЫС — orders.scheduled_at
-- ============================================================
alter table public.orders add column if not exists scheduled_at timestamptz;

create or replace function public.create_order(
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
  p_vehicle_type text default 'gazelle',
  p_stops jsonb default '[]'::jsonb,
  p_scheduled_at timestamptz default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_vehicle text;
  v_is_taxi boolean;
  v_id uuid;
  v_active int;
  v_intercity boolean;
  v_min bigint;
  v_from_city text;
  v_to_city text;
  v_stops jsonb;
  v_cities text[];
  v_scheduled timestamptz;
  v_sched_enabled boolean;
  v_min_hours int;
  v_max_days int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'client') then
    raise exception 'NOT_CLIENT';
  end if;

  v_vehicle := lower(coalesce(nullif(trim(p_vehicle_type),''), 'gazelle'));
  select is_taxi into v_is_taxi
    from public.vehicle_types where code = v_vehicle and active;
  if v_is_taxi is null then raise exception 'BAD_VEHICLE_TYPE'; end if;
  -- Такси САНАТЫ (такси + доставка) өшірулі болса — заказ қабылданбайды.
  if v_is_taxi and not public.taxi_enabled() then
    raise exception 'TAXI_OFF';
  end if;

  if coalesce(trim(p_from_address),'') = '' or coalesce(trim(p_to_address),'') = ''
     or coalesce(trim(p_cargo),'') = '' then
    raise exception 'BAD_INPUT';
  end if;

  if p_from_lat < 40 or p_from_lat > 56 or p_from_lng < 46 or p_from_lng > 88
     or p_to_lat < 40 or p_to_lat > 56 or p_to_lng < 46 or p_to_lng > 88 then
    raise exception 'OUT_OF_KZ';
  end if;

  -- Алдын ала тапсырыс (0060): фича өшулі болса — берілген уақыт елеусіз
  -- қалдырылады (қате шығармаймыз, әдепкі «дәл қазір» заказ болады).
  select coalesce((value->>'enabled')::boolean, false),
         coalesce((value->>'min_hours_ahead')::int, 2),
         coalesce((value->>'max_days_ahead')::int, 14)
    into v_sched_enabled, v_min_hours, v_max_days
    from public.app_settings where key = 'scheduled_orders';

  v_scheduled := p_scheduled_at;
  if v_scheduled is not null and coalesce(v_sched_enabled, false) then
    if v_scheduled < now() + make_interval(hours => v_min_hours) then
      raise exception 'SCHEDULE_TOO_SOON';
    end if;
    if v_scheduled > now() + make_interval(days => v_max_days) then
      raise exception 'SCHEDULE_TOO_FAR';
    end if;
  else
    v_scheduled := null;
  end if;

  v_stops := public.clean_order_stops(p_stops);

  select count(*) into v_active from public.orders
  where client_id = v_uid
    and status in ('searching','accepted','arrived','loading','in_transit');
  if v_active >= 5 then raise exception 'TOO_MANY_ACTIVE'; end if;

  v_from_city := nullif(trim(coalesce(p_from_city,'')),'');
  v_to_city   := nullif(trim(coalesce(p_to_city,'')),'');

  select array_agg(distinct c) into v_cities
    from (
      select public.norm_city(v_from_city) as c
      union all select public.norm_city(v_to_city)
      union all select public.norm_city(s->>'city')
                  from jsonb_array_elements(v_stops) s
    ) q
   where c is not null;
  v_intercity := coalesce(array_length(v_cities, 1), 0) > 1;

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
     client_price, system_price, photos, stops, scheduled_at)
  values
    (v_uid, 'bidding', 'simple', v_vehicle,
     trim(p_from_address), p_from_lat, p_from_lng, v_from_city,
     trim(p_to_address), p_to_lat, p_to_lng, v_to_city, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), 'small',
     p_client_price, null, coalesce(p_photos, '{}'), v_stops, v_scheduled)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'intercity', v_intercity,
                            'vehicle_type', v_vehicle,
                            'stops', jsonb_array_length(v_stops),
                            'scheduled_at', v_scheduled);
end;
$$;

grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,
  text[],text,text,text,text,jsonb,timestamptz) to authenticated;

-- Орындаушыға scheduled_at әлі келмеген заказ КӨРІНБЕЙДІ. exec_can_take
-- та осы функцияны бірінші шақыратындықтан (0041), қабылдау да автоматты
-- бұғатталады — бөлек түзету қажет емес.
create or replace function public.exec_can_see(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
  exec_city text;
  o_from text;
  o_to   text;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' then return false; end if;
  if o.scheduled_at is not null and o.scheduled_at > now() then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found then return false; end if;      -- статус ТЕКСЕРІЛМЕЙДІ

  if o.client_id = p_exec then return false; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  -- ҚАЛА СҮЗГІСІ (0053): жергілікті заказ тек сол қаладағы орындаушыға
  -- КӨРІНЕДІ де. Межгород — бәріне. Қала бапталмаса — сүзгі жоқ.
  exec_city := public.norm_city(ep.city);
  o_from := public.norm_city(o.from_city);
  o_to   := public.norm_city(o.to_city);

  if exec_city is not null and o_from is not null
     and (o_to is null or o_from = o_to)  -- жергілікті (межгород емес)
     and exec_city <> o_from then
    return false;
  end if;

  return true;
end;
$$;

-- ============================================================
-- 2) ОРЫНДАУШЫНЫ КАРТАДА ТІРІ КӨРСЕТУ — executor_locations
-- ============================================================
create table if not exists public.executor_locations (
  executor_id uuid primary key references public.profiles(id) on delete cascade,
  order_id    uuid references public.orders(id) on delete set null,
  lat         double precision not null,
  lng         double precision not null,
  updated_at  timestamptz not null default now()
);

alter table public.executor_locations enable row level security;
-- Тікелей SELECT саясаты ЖОҚ — қатынас тек төмендегі SECURITY DEFINER
-- RPC-лар арқылы (клиент тек ӨЗ заказының орындаушысын көреді).

-- Орындаушы ағымдағы орнын жібереді (белсенді заказы болса ғана мағыналы,
-- бірақ шектеу қоймаймыз — order_id жоқ болса жай сақталады, ешкім оқымайды).
create or replace function public.update_executor_location(p_lat float8, p_lng float8)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_lat < 40 or p_lat > 56 or p_lng < 46 or p_lng > 88 then
    raise exception 'OUT_OF_KZ';
  end if;

  select id into v_order from public.orders
   where executor_id = v_uid and status in ('accepted','arrived','loading','in_transit')
   order by accepted_at desc limit 1;

  insert into public.executor_locations (executor_id, order_id, lat, lng, updated_at)
  values (v_uid, v_order, p_lat, p_lng, now())
  on conflict (executor_id) do update
    set order_id = excluded.order_id, lat = excluded.lat, lng = excluded.lng,
        updated_at = now();
end;
$$;

grant execute on function public.update_executor_location(float8, float8) to authenticated;

-- Клиент өз заказының орындаушысының орнын сұрайды (polling, 10-15с).
create or replace function public.get_order_executor_location(p_order_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_client uuid;
  v_lat float8; v_lng float8; v_at timestamptz;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select client_id into v_client from public.orders where id = p_order_id;
  if v_client is null then raise exception 'NOT_FOUND'; end if;
  if v_client <> v_uid then raise exception 'FORBIDDEN'; end if;

  select lat, lng, updated_at into v_lat, v_lng, v_at
    from public.executor_locations where order_id = p_order_id;
  if v_lat is null then return null; end if;

  return jsonb_build_object('lat', v_lat, 'lng', v_lng, 'updated_at', v_at);
end;
$$;

grant execute on function public.get_order_executor_location(uuid) to authenticated;

-- ============================================================
-- 3) САПАРДЫ БӨЛІСУ — orders.share_token + анонимді track_order
-- ============================================================
alter table public.orders add column if not exists share_token uuid;
create unique index if not exists idx_orders_share_token on public.orders (share_token)
  where share_token is not null;

-- Клиент өз заказына сілтеме сұрайды — бірінші рет токен жасалады,
-- кейін сол қалпы қайтарылады (сілтеме тұрақты болу үшін).
create or replace function public.get_order_share_token(p_order_id uuid)
returns text
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_token uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (
    select 1 from public.orders where id = p_order_id and client_id = v_uid
  ) then
    raise exception 'FORBIDDEN';
  end if;

  select share_token into v_token from public.orders where id = p_order_id;
  if v_token is null then
    v_token := gen_random_uuid();
    update public.orders set share_token = v_token where id = p_order_id;
  end if;
  return v_token::text;
end;
$$;

grant execute on function public.get_order_share_token(uuid) to authenticated;

-- Токен арқылы АВТОРИЗАЦИЯСЫЗ (қонақ) қарау — тек минималды мәлімет
-- (нақты телефон/бет-әлпет жоқ), share_trip баптауы өшулі болса ЖҰМЫС
-- ІСТЕМЕЙДІ («DISABLED»).
create or replace function public.track_order(p_token text)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_token uuid;
  v_enabled boolean;
  v_live boolean;
  o record;
  v_executor_name text;
  v_lat float8; v_lng float8; v_loc_at timestamptz;
begin
  begin
    v_token := p_token::uuid;
  exception when others then
    return jsonb_build_object('error', 'NOT_FOUND');
  end;

  select coalesce((value->>'enabled')::boolean, false) into v_enabled
    from public.app_settings where key = 'share_trip';
  if not coalesce(v_enabled, false) then
    return jsonb_build_object('error', 'DISABLED');
  end if;

  select * into o from public.orders where share_token = v_token;
  if not found then
    return jsonb_build_object('error', 'NOT_FOUND');
  end if;

  if o.executor_id is not null then
    select full_name into v_executor_name from public.profiles where id = o.executor_id;
  end if;

  select coalesce((value->>'enabled')::boolean, false) into v_live
    from public.app_settings where key = 'live_tracking';

  if coalesce(v_live, false) and o.status in ('accepted','arrived','loading','in_transit') then
    select lat, lng, updated_at into v_lat, v_lng, v_loc_at
      from public.executor_locations where order_id = o.id;
  end if;

  return jsonb_build_object(
    'status', o.status,
    'vehicle_type', o.vehicle_type,
    'from_city', o.from_city, 'to_city', o.to_city,
    'from_address', o.from_address, 'to_address', o.to_address,
    'from_lat', o.from_lat, 'from_lng', o.from_lng,
    'to_lat', o.to_lat, 'to_lng', o.to_lng,
    'distance_km', o.distance_km,
    'created_at', o.created_at, 'accepted_at', o.accepted_at,
    'completed_at', o.completed_at,
    'executor_name', v_executor_name,
    'lat', v_lat, 'lng', v_lng, 'loc_updated_at', v_loc_at
  );
end;
$$;

grant execute on function public.track_order(text) to anon, authenticated;

-- ============================================================
-- 4) ЖАТТЫҚҚА ШАҚЫРУ БОНУСЫ (ұпай ғана) — profiles.referral_*
-- ============================================================
create or replace function public.gen_referral_code()
returns text
language sql
as $$
  select upper(substr(md5(gen_random_uuid()::text), 1, 6));
$$;

alter table public.profiles
  add column if not exists referral_code text,
  add column if not exists referred_by uuid references public.profiles(id),
  add column if not exists referral_count integer not null default 0;

alter table public.profiles
  alter column referral_code set default public.gen_referral_code();

update public.profiles set referral_code = public.gen_referral_code()
 where referral_code is null;

create unique index if not exists idx_profiles_referral_code
  on public.profiles (referral_code);

-- Жаңа тіркелген пайдаланушы ӨЗІ (кірген соң, бір рет) шақырушы кодын
-- жібереді. Signup edge function-ға ТИМЕЙДІ — авторизацияланған сессиямен
-- бөлек шақырылады, тіркелу ағынын қиындатпайды.
create or replace function public.redeem_referral_code(p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_referrer uuid;
  v_enabled boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select coalesce((value->>'enabled')::boolean, false) into v_enabled
    from public.app_settings where key = 'referral';
  if not coalesce(v_enabled, false) then raise exception 'DISABLED'; end if;

  if v_code = '' then raise exception 'BAD_CODE'; end if;

  if exists (
    select 1 from public.profiles where id = v_uid and referred_by is not null
  ) then
    raise exception 'ALREADY_REFERRED';
  end if;

  select id into v_referrer from public.profiles where referral_code = v_code;
  if v_referrer is null then raise exception 'BAD_CODE'; end if;
  if v_referrer = v_uid then raise exception 'SELF_REFERRAL'; end if;

  update public.profiles set referred_by = v_referrer where id = v_uid;
  update public.profiles set referral_count = referral_count + 1 where id = v_referrer;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.redeem_referral_code(text) to authenticated;
