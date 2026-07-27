-- GazelGo · 0042_avtovyshka_vehicle_type.sql
-- ЖАҢА КӨЛІК ТҮРІ: «Автовышка» (avtovyshka) — биіктікте жұмыс істеуге
-- арналған автокөтергіш. executor_profiles/orders CHECK тізіміне +
-- create_order валидациясына 'avtovyshka' қосылады (0040-тегі fura
-- үлгісі бойынша).
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек.
-- 0041-ден КЕЙІН орындаңыз.

-- ============================================================
-- 1) «Автовышка» көлік түрін CHECK тізіміне қосу
-- ============================================================
alter table public.executor_profiles
  drop constraint if exists executor_profiles_vehicle_type_check;
alter table public.executor_profiles
  add constraint executor_profiles_vehicle_type_check check (vehicle_type in
    ('gazelle','furgon','kamaz','fura','crane','manipulator','assenizator',
     'excavator','loader','minivan','tractor','avtovyshka'));

alter table public.orders
  drop constraint if exists orders_vehicle_type_check;
alter table public.orders
  add constraint orders_vehicle_type_check check (vehicle_type in
    ('gazelle','furgon','kamaz','fura','crane','manipulator','assenizator',
     'excavator','loader','minivan','tractor','avtovyshka'));

-- ============================================================
-- 2) create_order — 'avtovyshka' валидацияға қосылды (қалғаны 0040-дай)
-- ============================================================
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text,text,text);

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
  if v_vehicle not in ('gazelle','furgon','kamaz','fura','crane','manipulator',
                       'assenizator','excavator','loader','minivan','tractor',
                       'avtovyshka') then
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

grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,
  text[],text,text,text,text) to authenticated;
