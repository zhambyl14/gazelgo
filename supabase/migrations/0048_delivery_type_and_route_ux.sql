-- ============================================================
-- Tasu · 0048_delivery_type_and_route_ux.sql
-- ============================================================
-- ЖАҢА КӨЛІК ТҮРІ — «Доставка» (delivery).
--
-- «Такси» САНАТЫ енді ЕКІ түрден тұрады (спецтехника санатында газель,
-- фургон, КамАЗ… болатыны сияқты):
--   • taxi     — жолаушы тасымалы (заказ формасы: жолаушы саны);
--   • delivery — ЖЕҢІЛ КӨЛІКПЕН ұсақ жүк жеткізу (форма: не жеткізу
--     керек — яғни таксидікі емес, доставканыкі).
--
-- Екеуі де `app_settings.taxi.enabled` қосқышына тәуелді: модератор
-- «Такси» бөлімін өшірсе, доставка да көрінбейді (бір санат).
--
-- ЕСКЕРТУ: 0047-ден КЕЙІН орындаңыз. Идемпотентті.
-- ============================================================

-- ============================================================
-- 1) Көлік түрі шектеулеріне 'delivery' қосу
-- ============================================================
alter table public.executor_profiles
  drop constraint if exists executor_profiles_vehicle_type_check;
alter table public.executor_profiles
  add constraint executor_profiles_vehicle_type_check check (vehicle_type in
    ('taxi','delivery','gazelle','furgon','kamaz','fura','crane','manipulator',
     'assenizator','excavator','loader','minivan','tractor','avtovyshka'));

alter table public.orders
  drop constraint if exists orders_vehicle_type_check;
alter table public.orders
  add constraint orders_vehicle_type_check check (vehicle_type in
    ('taxi','delivery','gazelle','furgon','kamaz','fura','crane','manipulator',
     'assenizator','excavator','loader','minivan','tractor','avtovyshka'));


-- ============================================================
-- 2) create_order — 'delivery' валидацияға + такси санатының қосқышы
-- ============================================================
-- 0047-дегі нұсқаның көшірмесі, тек ЕКІ жері өзгерді:
--   • рұқсат етілген түрлер тізіміне 'delivery' кірді;
--   • такси бөлімінің тексеруі енді ЕКІ түрге де қолданылады
--     (`v_vehicle in ('taxi','delivery')`).
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
  p_stops jsonb default '[]'::jsonb
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
  v_stops jsonb;
  v_cities text[];
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'client') then
    raise exception 'NOT_CLIENT';
  end if;

  v_vehicle := coalesce(nullif(trim(p_vehicle_type),''), 'gazelle');
  if v_vehicle not in ('taxi','delivery','gazelle','furgon','kamaz','fura','crane',
                       'manipulator','assenizator','excavator','loader','minivan',
                       'tractor','avtovyshka') then
    raise exception 'BAD_VEHICLE_TYPE';
  end if;
  -- Такси САНАТЫ (такси + доставка) өшірулі болса — заказ қабылданбайды.
  if v_vehicle in ('taxi','delivery') and not public.taxi_enabled() then
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
     client_price, system_price, photos, stops)
  values
    (v_uid, 'bidding', 'simple', v_vehicle,
     trim(p_from_address), p_from_lat, p_from_lng, v_from_city,
     trim(p_to_address), p_to_lat, p_to_lng, v_to_city, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), 'small',
     p_client_price, null, coalesce(p_photos, '{}'), v_stops)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'intercity', v_intercity,
                            'vehicle_type', v_vehicle,
                            'stops', jsonb_array_length(v_stops));
end;
$$;

grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,
  text[],text,text,text,text,jsonb) to authenticated;
