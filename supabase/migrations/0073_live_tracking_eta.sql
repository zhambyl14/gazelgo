-- ============================================================
-- Tasu · 0073_live_tracking_eta.sql
-- ============================================================
-- КЕЛУ УАҚЫТЫ (ETA) және ОРЫНДАУШЫНЫ КАРТАДА ТІРІ КӨРСЕТУ (inDrive үлгісі).
--
--   1) offers.eta_min — орындаушы ұсыныспен бірге «неше минутта жетемін»
--      таңдайды (3 / 5 / 7 / 10 / 15 / 20 / 30). place_offer жаңа
--      p_eta_min параметрін алады — ӘДЕПКІСІ null, сондықтан ескі қосымша
--      нұсқалары бұрынғыдай жұмыс істей береді.
--   2) orders.executor_eta_min / arrive_by — ұсыныс қабылданған сәтте
--      уәде етілген келу уақыты заказға жазылады (ТРИГГЕР арқылы —
--      accept_offer функциясына тиіспейміз). orders.arrived_at — «Келдім»
--      басылған сәт (клиент пен орындаушыда күту таймері үшін).
--   3) executor_locations.heading / speed — картадағы көліктің бағыты.
--   4) nearby_executors — клиенттің картасында ЖАҚЫН МАҢДАҒЫ бос
--      орындаушылар (көлік түрінің белгісімен). Жеке орын ашылмайды:
--      координата ~100 м дәлдікке дейін дөңгелектенеді, аты/id жоқ.
--   5) live_tracking баптауы ҚОСЫЛАДЫ (иесінің 2026-10-16 өтініші: клиент
--      орындаушының қайда келе жатқанын картадан көруі керек). Модератор
--      қаласа «Баптаулар» бетінен қайта өшіре алады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0072-ден кейін).
-- ============================================================

-- ============================================================
-- 1) offers.eta_min + place_offer v2
-- ============================================================
alter table public.offers add column if not exists eta_min int;

do $$ begin
  alter table public.offers add constraint offers_eta_min_range
    check (eta_min is null or (eta_min between 1 and 240));
exception when duplicate_object then null; end $$;

-- Ескі қолтаңбаны алып тастаймыз: PostgREST екі нұсқаның арасында
-- таңдай алмай қалмауы үшін (жаңасы ескі шақыруды да қабылдайды —
-- p_eta_min әдепкісі null).
drop function if exists public.place_offer(uuid, bigint, text);

create or replace function public.place_offer(
  p_order uuid,
  p_price bigint,
  p_message text default '',
  p_eta_min int default null)
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
  if p_eta_min is not null and (p_eta_min < 1 or p_eta_min > 240) then
    raise exception 'BAD_INPUT';
  end if;

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
           eta_min = p_eta_min,
           status = 'pending', created_at = now()
     where id = v_existing.id;
    return v_existing.id;
  end if;

  insert into public.offers (order_id, executor_id, price, message, eta_min)
  values (p_order, v_uid, p_price, coalesce(trim(p_message),''), p_eta_min)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.place_offer(uuid, bigint, text, int) to authenticated;

-- ============================================================
-- 2) orders: уәде етілген келу уақыты + «Келдім» сәті
-- ============================================================
alter table public.orders add column if not exists executor_eta_min int;
alter table public.orders add column if not exists arrive_by timestamptz;
alter table public.orders add column if not exists arrived_at timestamptz;

create or replace function public.order_eta_stamp()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eta int;
begin
  -- Қайта іздеуге оралды (орындаушы бас тартты) — уәде мен күту тазаланады.
  if new.status = 'searching' then
    new.executor_eta_min := null;
    new.arrive_by := null;
    new.arrived_at := null;
    return new;
  end if;

  -- Ұсыныс қабылданды — сол орындаушының ұсынысындағы ETA заказға жазылады.
  if new.status = 'accepted' and old.status is distinct from 'accepted'
     and new.executor_id is not null then
    select f.eta_min into v_eta
      from public.offers f
     where f.order_id = new.id and f.executor_id = new.executor_id
     order by f.created_at desc
     limit 1;
    new.executor_eta_min := v_eta;
    new.arrive_by := case
      when v_eta is null then null
      else now() + make_interval(mins => v_eta)
    end;
  end if;

  if new.status = 'arrived' and old.status is distinct from 'arrived' then
    new.arrived_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_order_eta_stamp on public.orders;
create trigger trg_order_eta_stamp
  before update of status on public.orders
  for each row execute function public.order_eta_stamp();

-- ============================================================
-- 3) executor_locations: бағыт пен жылдамдық
-- ============================================================
alter table public.executor_locations add column if not exists heading double precision;
alter table public.executor_locations add column if not exists speed double precision;
create index if not exists idx_executor_locations_updated
  on public.executor_locations (updated_at desc);

drop function if exists public.update_executor_location(float8, float8);

create or replace function public.update_executor_location(
  p_lat float8,
  p_lng float8,
  p_heading float8 default null,
  p_speed float8 default null)
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

  insert into public.executor_locations
    (executor_id, order_id, lat, lng, heading, speed, updated_at)
  values (v_uid, v_order, p_lat, p_lng, p_heading, p_speed, now())
  on conflict (executor_id) do update
    set order_id = excluded.order_id, lat = excluded.lat, lng = excluded.lng,
        heading = excluded.heading, speed = excluded.speed, updated_at = now();
end;
$$;

grant execute on function public.update_executor_location(float8, float8, float8, float8)
  to authenticated;

-- Клиент (не модератор) өз заказының орындаушысының орнын сұрайды.
create or replace function public.get_order_executor_location(p_order_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_client uuid;
  l record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select client_id into v_client from public.orders where id = p_order_id;
  if v_client is null then raise exception 'NOT_FOUND'; end if;
  if v_client <> v_uid and not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  select lat, lng, heading, speed, updated_at into l
    from public.executor_locations where order_id = p_order_id;
  if not found then return null; end if;

  return jsonb_build_object(
    'lat', l.lat, 'lng', l.lng,
    'heading', l.heading, 'speed', l.speed,
    'updated_at', l.updated_at
  );
end;
$$;

grant execute on function public.get_order_executor_location(uuid) to authenticated;

-- ============================================================
-- 4) Жақын маңдағы бос орындаушылар (клиенттің картасы үшін)
-- ============================================================
-- Тек: соңғы 10 минутта орнын жіберген, расталған, қазір заказсыз әрі
-- тарифі белсенді (заказ ала алатын) орындаушылар. Жеке мәлімет жоқ.
create or replace function public.nearby_executors(
  p_lat float8,
  p_lng float8,
  p_vehicle text default null,
  p_radius_km float8 default 15)
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select
      round(l.lat::numeric, 3)::float8 as lat,
      round(l.lng::numeric, 3)::float8 as lng,
      ep.vehicle_type::text as vehicle_type,
      l.heading
    from public.executor_locations l
    join public.executor_profiles ep on ep.user_id = l.executor_id
    join public.profiles p on p.id = l.executor_id
    where l.updated_at > now() - interval '10 minutes'
      and l.order_id is null
      and ep.status = 'approved'
      and ep.busy_order_id is null
      and coalesce(ep.on_line, true)
      and p.role = 'executor'
      and (p_vehicle is null or ep.vehicle_type::text = p_vehicle)
      and abs(l.lat - p_lat) < (p_radius_km / 111.0)
      and abs(l.lng - p_lng) < (p_radius_km / (111.0 * cos(radians(p_lat))))
      and public.exec_has_capacity(l.executor_id)
    order by (l.lat - p_lat) ^ 2 + (l.lng - p_lng) ^ 2
    limit 30
  ) x;
$$;

grant execute on function public.nearby_executors(float8, float8, text, float8)
  to anon, authenticated;

-- ============================================================
-- 5) Тірі бақылауды қосу
-- ============================================================
insert into public.app_settings (key, value)
values ('live_tracking', jsonb_build_object('enabled', true))
on conflict (key) do update
  set value = public.app_settings.value || jsonb_build_object('enabled', true);
