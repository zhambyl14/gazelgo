-- GazelGo · 0014_tariff_orders_corrections.sql
-- Пайдаланушы нақтылаған өзгерістер:
--   • Газель ӨЛШЕМІ мүлдем алынды (тіркеуде де, фильтрде де жоқ).
--   • Заказдың түрі = ТАРИФ САНАТЫ: 'simple' (қарапайым) немесе 'vip' (форс-мажор/
--     бағалы жүк). Клиент таңдайды. Екеуі де bidding (клиент баға қояды).
--   • Орындаушы Простой тарифпен — тек simple заказдарды, VIP тарифпен — тек vip
--     заказдарды көреді (лента бөлек). Өлшемге қарамайды.
--   • ТАРИФ = 1 АУЫСЫМ (12 сағат: 08:00–20:00 не 20:00–08:00), сол ауысымда МАКС
--     10 заказ. Ауысым бітсе НЕ 10 заказ алынса — тариф жабылады, қайта сатып алу.
--     Простой мен VIP бөлек: әрқайсысының ауысымы да, 10 лимиті де өз тұсында.
--   • VIP тарифті тек көлік жылы жеткілікті жаңа болса сатып алуға болады.
--   • Адрес түзетулері (crowd-fix): клиент картадағы нүктенің атын түзетсе,
--     сол маңдағы нүктелерге кейін сол ат ұсынылады (address_corrections).
--   • Тіркеу құжаттары: права+селфи, куәлік+селфи, шетел паспорты+селфи.
-- 0013-тен КЕЙІН орындаңыз.

-- ============================================================
-- 0) Схема
-- ============================================================
alter table public.orders
  add column if not exists tariff public.tariff_kind not null default 'simple';

alter table public.executor_profiles
  add column if not exists id_selfie_path text,      -- куәлікпен селфи
  add column if not exists license_selfie_path text, -- правамен селфи
  add column if not exists passport_path text,        -- шетел паспорты (болса)
  add column if not exists passport_selfie_path text; -- паспортпен селфи

-- ============================================================
-- 1) Баптаулар: VIP көлік жылы шегі
-- ============================================================
insert into public.app_settings (key, value) values
  ('vehicle_rules', '{"vip_min_year": 2010}')
on conflict (key) do update set value = excluded.value;

-- ============================================================
-- 2) Сыйымдылық — тариф САНАТЫ бойынша (өлшем жоқ)
-- ============================================================

-- Осы санатта (simple/vip) белсенді тариф бар ма? Триал тек simple-ге жатады.
-- Тариф = 1 ауысым (12 сағат: 08:00–20:00 не 20:00–08:00) ІШІНДЕ, әрі 10 заказ
-- ЛИМИТІ бітпеген болса белсенді. Ауысым бітсе (expires_at өтсе) НЕ лимит бітсе
-- (orders_left=0) — тариф жабылады, қайта сатып алу керек.
create or replace function public.exec_has_kind(p_exec uuid, p_kind public.tariff_kind)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tariff_sessions
    where executor_id = p_exec
      and ((not is_trial and kind = p_kind
              and coalesce(orders_left,0) > 0 and expires_at > now())
        or (is_trial and p_kind = 'simple' and expires_at > now()))
  );
$$;

-- Орындаушы осы заказды ала ала ма? (§5/§6 + тариф санаты; ӨЛШЕМ ЖОҚ)
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

  -- Тариф санаты сай әрі лимит бар ма (Простой↔simple, VIP↔vip)
  if not public.exec_has_kind(p_exec, o.tariff) then return false; end if;

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

-- Заказ қабылданғанда сол САНАТТЫҢ лимитінен 1 шегеру (триал болса тегін).
create or replace function public.consume_order(p_exec uuid, p_kind public.tariff_kind default 'simple')
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if p_kind = 'simple' and public.exec_trial_active(p_exec) then
    return;  -- тегін кезең — simple заказ шегерілмейді
  end if;
  select id into v_id from public.tariff_sessions
   where executor_id = p_exec and not is_trial and kind = p_kind
     and coalesce(orders_left,0) > 0 and expires_at > now()
   order by orders_left asc, started_at asc
   limit 1;
  if v_id is not null then
    update public.tariff_sessions set orders_left = orders_left - 1 where id = v_id;
  end if;
end;
$$;

-- ============================================================
-- 3) Тариф сатып алу — VIP көлік жылы шегі
-- ============================================================
create or replace function public.buy_tariff(p_kind text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_kind public.tariff_kind;
  ep record;
  v_price bigint;
  v_session uuid;
  v_min_year int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_kind := p_kind::public.tariff_kind;

  select * into ep from public.executor_profiles where user_id = v_uid for update;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  -- Осы санатта белсенді ауысым тұрса — қайта сатып алуға болмайды
  -- (ауысым бітсін не 10 заказ бітсін, содан кейін ғана жаңасы).
  if exists (select 1 from public.tariff_sessions
             where executor_id = v_uid and not is_trial and kind = v_kind
               and coalesce(orders_left,0) > 0 and expires_at > now()) then
    raise exception 'ALREADY_ACTIVE';
  end if;

  -- VIP: көлік жылы жеткілікті жаңа болуы керек
  if v_kind = 'vip' then
    select coalesce((value->>'vip_min_year')::int, 2010) into v_min_year
      from public.app_settings where key = 'vehicle_rules';
    v_min_year := coalesce(v_min_year, 2010);
    if ep.vehicle_year is null or ep.vehicle_year < v_min_year then
      raise exception 'VIP_YEAR_%', v_min_year;
    end if;
  end if;

  v_price := public.tariff_price_now(p_kind);
  if ep.balance < v_price then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.executor_profiles set balance = balance - v_price where user_id = v_uid;

  insert into public.balance_txns (executor_id, amount, type, note)
  values (v_uid, -v_price, 'tariff_fee',
          case when v_kind = 'simple' then 'Қарапайым тариф (1 ауысым)'
               else 'VIP тариф (1 ауысым)' end);

  -- Ауысым соңында бітеді (08:00 не 20:00), әрі 10 заказ лимиті бар.
  insert into public.tariff_sessions
    (executor_id, kind, fee, is_night, is_trial, orders_left, started_at, expires_at)
  values
    (v_uid, v_kind, v_price, public.is_night_now(), false, 10, now(),
     public.current_window_end())
  returning id into v_session;

  return jsonb_build_object('session_id', v_session, 'fee', v_price,
                            'orders_left', 10, 'expires_at', public.current_window_end());
end;
$$;

-- ============================================================
-- 4) Заказ құру — тариф санаты (simple/vip), өлшем елеусіз
-- ============================================================
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
  p_tariff text default 'simple'
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_size public.vehicle_size;
  v_tariff public.tariff_kind;
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

  v_size := coalesce(nullif(p_size,''), 'small')::public.vehicle_size;  -- өлшем ескерілмейді
  v_tariff := coalesce(nullif(p_tariff,''), 'simple')::public.tariff_kind;

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
    (client_id, type, tariff, from_address, from_lat, from_lng, from_city,
     to_address, to_lat, to_lng, to_city, distance_km, cargo_desc, comment, size,
     client_price, system_price, photos)
  values
    (v_uid, 'bidding', v_tariff, trim(p_from_address), p_from_lat, p_from_lng, v_from_city,
     trim(p_to_address), p_to_lat, p_to_lng, v_to_city, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), v_size,
     p_client_price, null, coalesce(p_photos, '{}'))
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'intercity', v_intercity, 'tariff', v_tariff);
end;
$$;

-- ============================================================
-- 5) Ұсыныс беру — тариф санаты + қала/маршрут (өлшем жоқ)
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

  if not public.exec_has_kind(v_uid, o.tariff) then raise exception 'NO_ORDERS_LEFT'; end if;
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
-- 6) Ұсынысты қабылдау — санат лимитінен шегеру
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

  if not public.exec_has_kind(ofr.executor_id, o.tariff) then raise exception 'EXEC_NO_ORDERS'; end if;
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

  perform public.consume_order(ofr.executor_id, o.tariff);

  return jsonb_build_object('order_id', v_order_id, 'executor_id', ofr.executor_id);
end;
$$;

-- ============================================================
-- 7) executor_stats — санат бойынша қалған лимит
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
  v_simple_left bigint;
  v_vip_left bigint;
  v_simple_until timestamptz;
  v_vip_until timestamptz;
  v_trial timestamptz;
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

  -- Тек АҒЫМДАҒЫ ауысымдағы (мерзімі бітпеген) сессиялар есептеледі.
  select coalesce(sum(orders_left),0), max(expires_at)
    into v_simple_left, v_simple_until from public.tariff_sessions
   where executor_id = v_uid and kind = 'simple' and not is_trial
     and coalesce(orders_left,0) > 0 and expires_at > now();
  select coalesce(sum(orders_left),0), max(expires_at)
    into v_vip_left, v_vip_until from public.tariff_sessions
   where executor_id = v_uid and kind = 'vip' and not is_trial
     and coalesce(orders_left,0) > 0 and expires_at > now();
  select max(expires_at) into v_trial from public.tariff_sessions
   where executor_id = v_uid and is_trial and expires_at > now();

  return jsonb_build_object(
    'balance', ep.balance,
    'total_earned', ep.total_earned,
    'today', v_today,
    'month', v_month,
    'busy_order_id', ep.busy_order_id,
    'orders_left', v_simple_left + v_vip_left,
    'simple_left', v_simple_left,
    'vip_left', v_vip_left,
    'simple_until', v_simple_until,
    'vip_until', v_vip_until,
    'trial_until', v_trial,
    'has_tariff', public.exec_has_kind(v_uid,'simple') or public.exec_has_kind(v_uid,'vip'),
    'simple_active', public.exec_has_kind(v_uid,'simple'),
    'vip_active', public.exec_has_kind(v_uid,'vip'),
    'is_night', public.is_night_now(),
    'price_simple', public.tariff_price_now('simple'),
    'price_vip', public.tariff_price_now('vip'),
    'vehicle_year', ep.vehicle_year,
    'on_line', ep.on_line,
    'city', ep.city
  );
end;
$$;

-- ============================================================
-- 8) Адрес түзетулері (crowd-fix)
-- ============================================================
create table if not exists public.address_corrections (
  id         uuid primary key default gen_random_uuid(),
  lat        double precision not null,
  lng        double precision not null,
  label      text not null,
  votes      integer not null default 1,
  created_at timestamptz not null default now()
);
create index if not exists idx_addr_corr_geo on public.address_corrections (lat, lng);
alter table public.address_corrections enable row level security;  -- тек RPC арқылы

-- Нүктенің маңындағы (шамамен p_radius метр) ең сенімді түзетілген атауы.
create or replace function public.nearby_address(
  p_lat double precision, p_lng double precision, p_radius_m double precision default 130)
returns text
language sql stable security definer
set search_path = public, pg_temp
as $$
  select label from public.address_corrections
  where lat between p_lat - p_radius_m/111320.0 and p_lat + p_radius_m/111320.0
    and lng between p_lng - p_radius_m/(111320.0*greatest(cos(radians(p_lat)),0.1))
                and p_lng + p_radius_m/(111320.0*greatest(cos(radians(p_lat)),0.1))
  order by votes desc,
    ((lat-p_lat)*(lat-p_lat) + (lng-p_lng)*(lng-p_lng)) asc
  limit 1;
$$;

-- Клиент нүктенің атын түзеткенде сақтау (жақын әрі бірдей ат болса — дауыс +1).
create or replace function public.save_address_correction(
  p_lat double precision, p_lng double precision, p_label text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  r double precision := 60;  -- 60 м ішінде «сол нүкте» деп есептейміз
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  if coalesce(btrim(p_label),'') = '' then return; end if;

  select id into v_id from public.address_corrections
   where lat between p_lat - r/111320.0 and p_lat + r/111320.0
     and lng between p_lng - r/(111320.0*greatest(cos(radians(p_lat)),0.1))
                 and p_lng + r/(111320.0*greatest(cos(radians(p_lat)),0.1))
     and lower(btrim(label)) = lower(btrim(p_label))
   order by ((lat-p_lat)*(lat-p_lat) + (lng-p_lng)*(lng-p_lng)) asc
   limit 1;

  if v_id is not null then
    update public.address_corrections set votes = votes + 1 where id = v_id;
  else
    insert into public.address_corrections (lat, lng, label)
    values (p_lat, p_lng, btrim(p_label));
  end if;
end;
$$;

-- ============================================================
-- 9) Grants
-- ============================================================
revoke execute on function public.exec_has_kind(uuid, public.tariff_kind) from public, anon, authenticated;
revoke execute on function public.consume_order(uuid, public.tariff_kind) from public, anon, authenticated;

grant execute on function public.buy_tariff(text) to authenticated;
grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text,text) to authenticated;
grant execute on function public.place_offer(uuid,bigint,text) to authenticated;
grant execute on function public.accept_offer(uuid) to authenticated;
grant execute on function public.executor_stats() to authenticated;
grant execute on function public.nearby_address(double precision,double precision,double precision) to authenticated;
grant execute on function public.save_address_correction(double precision,double precision,text) to authenticated;

-- ============================================================
-- 10) submit_docs_update — жаңа құжат өрістерін қабылдау
-- ============================================================
create or replace function public.submit_docs_update(
  p_id_doc text default null,
  p_license text default null,
  p_tech text default null,
  p_photos text[] default null,
  p_id_selfie text default null,
  p_license_selfie text default null,
  p_passport text default null,
  p_passport_selfie text default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.executor_profiles
     set id_doc_path = coalesce(p_id_doc, id_doc_path),
         license_path = coalesce(p_license, license_path),
         tech_passport_path = coalesce(p_tech, tech_passport_path),
         id_selfie_path = coalesce(p_id_selfie, id_selfie_path),
         license_selfie_path = coalesce(p_license_selfie, license_selfie_path),
         passport_path = coalesce(p_passport, passport_path),
         passport_selfie_path = coalesce(p_passport_selfie, passport_selfie_path),
         vehicle_photos = coalesce(p_photos, vehicle_photos),
         docs_review_pending = true
   where user_id = auth.uid();
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

grant execute on function public.submit_docs_update(
  text,text,text,text[],text,text,text,text) to authenticated;
