-- ============================================================
-- Tasu · 0047_order_stops.sql
-- ============================================================
-- КӨП МЕКЕНЖАЙ («адрес қосу», Яндекс/inDriver үлгісі).
--
-- Клиент бір заказбен БІРНЕШЕ жерге жеткізе алады: алу нүктесі (A) +
-- жеткізу нүктелері. Схеманы БҰЗБАЙМЫЗ:
--   • `from_*` — БІРІНШІ нүкте (алу), бұрынғыдай;
--   • `to_*`   — СОҢҒЫ нүкте (ақырғы жеткізу), бұрынғыдай;
--   • `stops`  — ЖАҢА: солардың АРАСЫНДАҒЫ аялдамалар (jsonb массив).
-- Осылайша ескі барлық код (лента, exec_can_take қала ережесі, push,
-- модератор экрандары) өзгеріссіз жұмыс істей береді — оларға маршрут
-- әрқашан «A → … → B» болып көрінеді.
--
-- Аялдама форматы: {"address": text, "lat": num, "lng": num, "city": text|null}
--
-- ШЕКТЕУ: аралық аялдама ЕҢ КӨБІ 2 → маршрутта барлығы 4 нүктеге дейін
-- (1 алу + 3 жеткізу). Санын өзгерту үшін осы файлдағы `k_max_stops`
-- мәнін және қосымшадағы `kMaxExtraStops` тұрақтысын түзетіңіз.
--
-- ЕСКЕРТУ: 0046-дан КЕЙІН орындаңыз. Идемпотентті.
-- ============================================================

-- ============================================================
-- 1) orders.stops
-- ============================================================
alter table public.orders
  add column if not exists stops jsonb not null default '[]'::jsonb;

-- Массив екеніне және шектен аспауына кепілдік (бүлінген дерек кірмесін).
alter table public.orders drop constraint if exists orders_stops_check;
alter table public.orders
  add constraint orders_stops_check check (
    jsonb_typeof(stops) = 'array' and jsonb_array_length(stops) <= 2
  );


-- ============================================================
-- 2) Көмекші: аялдамалар массивін тексеру + тазалау
-- ============================================================
-- Қайтарады: тазаланған jsonb массив (тек қажет өрістер, trim жасалған).
-- Қате болса exception лақтырады — заказ жартылай құрылып қалмайды.
create or replace function public.clean_order_stops(p_stops jsonb)
returns jsonb
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  k_max_stops constant int := 2;
  v_out jsonb := '[]'::jsonb;
  s jsonb;
  v_addr text;
  v_lat  double precision;
  v_lng  double precision;
  v_city text;
begin
  if p_stops is null or jsonb_typeof(p_stops) = 'null' then
    return '[]'::jsonb;
  end if;
  if jsonb_typeof(p_stops) <> 'array' then
    raise exception 'BAD_STOPS';
  end if;
  if jsonb_array_length(p_stops) > k_max_stops then
    raise exception 'TOO_MANY_STOPS';
  end if;

  for s in select * from jsonb_array_elements(p_stops) loop
    if jsonb_typeof(s) <> 'object' then raise exception 'BAD_STOPS'; end if;
    v_addr := nullif(trim(coalesce(s->>'address','')), '');
    if v_addr is null then raise exception 'BAD_STOPS'; end if;
    begin
      v_lat := (s->>'lat')::double precision;
      v_lng := (s->>'lng')::double precision;
    exception when others then
      raise exception 'BAD_STOPS';
    end;
    if v_lat is null or v_lng is null then raise exception 'BAD_STOPS'; end if;
    -- Қазақстан шекарасы (create_order-дегі тексерумен бірдей)
    if v_lat < 40 or v_lat > 56 or v_lng < 46 or v_lng > 88 then
      raise exception 'OUT_OF_KZ';
    end if;
    v_city := nullif(trim(coalesce(s->>'city','')), '');
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'address', v_addr, 'lat', v_lat, 'lng', v_lng, 'city', v_city));
  end loop;
  return v_out;
end;
$$;


-- ============================================================
-- 3) create_order — аялдамаларды қабылдайды
-- ============================================================
-- Ескі қолтаңбаларды ДРОП жасаймыз: екі overload қалса PostgREST «Could
-- not choose the best candidate function» қатесін береді (0042-дегі тәртіп).
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,
  text[],text,text,text,text);
-- 0029-дан БҰРЫНҒЫ, көлік түрі жоқ ең ескі қолтаңба да базада қалып
-- қалған еді (0029/0040/0042 оны дропқа қоспаған) — оны да өшіреміз,
-- әйтпесе екі кандидат болып, RPC мүлдем шақырылмайтын күйге түсуі мүмкін.
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[]);

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
  if v_vehicle not in ('taxi','gazelle','furgon','kamaz','fura','crane','manipulator',
                       'assenizator','excavator','loader','minivan','tractor',
                       'avtovyshka') then
    raise exception 'BAD_VEHICLE_TYPE';
  end if;
  if v_vehicle = 'taxi' and not public.taxi_enabled() then
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

  -- Аралық аялдамалар (0047): тексеріліп, тазаланады.
  v_stops := public.clean_order_stops(p_stops);

  select count(*) into v_active from public.orders
  where client_id = v_uid
    and status in ('searching','accepted','arrived','loading','in_transit');
  if v_active >= 5 then raise exception 'TOO_MANY_ACTIVE'; end if;

  v_from_city := nullif(trim(coalesce(p_from_city,'')),'');
  v_to_city   := nullif(trim(coalesce(p_to_city,'')),'');

  -- МЕЖГОРОД: БАРЛЫҚ нүктенің (алу + аялдамалар + жеткізу) қаласын
  -- жинап, әртүрлі қала БІРДЕН ДЕ КӨП болса — қалааралық заказ.
  -- Бұрын тек from/to салыстырылатын: аралық аялдама басқа қалада
  -- болса, ол ескерілмей, минимум баға қала ішіндегідей қалып қоятын.
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


-- ============================================================
-- 4) ЕСКІ RPC ҚАЛДЫҚТАРЫН ТАЗАЛАУ (алдын алу)
-- ============================================================
-- Ескі миграциялар функция ҚОЛТАҢБАСЫН өзгерткенде ескісін дропқа
-- қоспаған кездер болған. Нәтижесінде базада бір атпен ЕКІ функция
-- қалады да, PostgREST «Could not choose the best candidate function»
-- деп RPC-ді мүлдем шақыра алмайтын күйге түсуі мүмкін.
--
-- 0023-тен бұрынғы `submit_docs_update` (селфи/паспорт өрістері жоқ):
drop function if exists public.submit_docs_update(text, text, text, text[]);
-- Тексеру (базада қос overload қалмағанына көз жеткізу):
--   select proname, count(*) from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname='public' group by proname having count(*) > 1;
