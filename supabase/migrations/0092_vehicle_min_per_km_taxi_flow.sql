-- ============================================================
-- Tasu · 0092_vehicle_min_per_km_taxi_flow.sql
-- ============================================================
-- 1) МИНИМАЛДЫ СОМА — әр көлік түріне ЖЕКЕ, км-ге есептеледі.
--    Модератор «Көліктер» → түрді ашып, «Минималды сома (км-ге)» қосқышын
--    қосады және 1 км бағасын жазады (мыс. Такси: 100 ₸/км). Сонда А мен Б
--    арасы 10 км болса, клиент 1000 ₸-дан төмен баға қоя алмайды.
--      * vehicle_types.min_per_km_enabled / min_per_km
--      * vehicle_min_price(түр, км) — ең төменгі сома (10 ₸-ге дөңгелектеп
--        ЖОҒАРЫ қарай; қосымшадағы есептеумен дәл бірдей)
--      * create_order және place_offer: баға осыдан төмен болса — 'MIN_PER_KM'.
--        Қала/межгород минимумы (order_min) сақталады: ең үлкені алынады.
--      * mod_save_vehicle_type — екі жаңа параметр (ескі қолтаңба алынады).
--
-- 2) ТАКСИ статустарының push-ы: taxi/umay заказында «Жүргізуші жолда /
--    келді / Сапар басталды / Сапар аяқталды» (жүктегі «Орындаушы/Жүгіңіз»
--    емес). notify_order_status_change қайта жазылды.
--
-- Қосымша жаңа нұсқасы шықпай тұрып қолданыңыз. Идемпотентті.
-- Supabase SQL Editor-да не MCP арқылы қолданылады (0091-ден кейін).
-- ============================================================

-- ------------------------------------------------------------
-- 1.1) Баған
-- ------------------------------------------------------------
alter table public.vehicle_types
  add column if not exists min_per_km_enabled boolean not null default false,
  add column if not exists min_per_km int not null default 0;

do $$ begin
  alter table public.vehicle_types add constraint vehicle_types_min_per_km_range
    check (min_per_km between 0 and 100000);
exception when duplicate_object then null; end $$;

comment on column public.vehicle_types.min_per_km_enabled is
  'Минималды сома км-ге есептелсін бе (0092)';
comment on column public.vehicle_types.min_per_km is
  'Минималды сома: 1 км үшін ₸ (0092). Заказ бағасы ≥ км × осы мән';

-- ------------------------------------------------------------
-- 1.2) Ең төменгі соманы есептеу
-- ------------------------------------------------------------
-- cents = км × 100 (бүтінге дейін) → сома = cents × ₸/км / 100, 10 ₸-ге
-- жоғары дөңгелектеледі. Қосылмаған/түр жоқ/қашықтық жоқ болса — 0.
create or replace function public.vehicle_min_price(
  p_vehicle text, p_distance_km numeric)
returns bigint
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when v.min_per_km_enabled and v.min_per_km > 0
           and coalesce(p_distance_km, 0) > 0
      then (ceil((round(p_distance_km * 100) * v.min_per_km) / 1000.0) * 10)::bigint
      else 0
    end
    from public.vehicle_types v
    where v.code = p_vehicle
  ), 0);
$$;

grant execute on function public.vehicle_min_price(text, numeric)
  to anon, authenticated;

-- ------------------------------------------------------------
-- 1.3) mod_save_vehicle_type v2
-- ------------------------------------------------------------
drop function if exists public.mod_save_vehicle_type(
  text,text,text,text,text,text,text,boolean,boolean);

create or replace function public.mod_save_vehicle_type(
  p_code     text,
  p_label_kk text default null,
  p_label_ru text default null,
  p_desc_kk  text default null,
  p_desc_ru  text default null,
  p_icon_url text default null,
  p_emoji    text default null,
  p_is_taxi  boolean default null,
  p_active   boolean default null,
  p_min_per_km_enabled boolean default null,
  p_min_per_km int default null
)
returns public.vehicle_types
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_code text := lower(btrim(coalesce(p_code, '')));
  v_row  public.vehicle_types;
  v_next int;
begin
  if not public.is_moderator() then raise exception 'NOT_MODERATOR'; end if;
  if v_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'BAD_CODE'; end if;
  if p_min_per_km is not null and (p_min_per_km < 0 or p_min_per_km > 100000) then
    raise exception 'BAD_INPUT';
  end if;

  select * into v_row from public.vehicle_types where code = v_code;

  if v_row.code is null then
    if coalesce(btrim(p_label_kk), '') = '' then raise exception 'BAD_INPUT'; end if;
    select coalesce(max(sort_order), 0) + 10 into v_next from public.vehicle_types;
    insert into public.vehicle_types
      (code, label_kk, label_ru, desc_kk, desc_ru, icon_url, emoji,
       sort_order, is_taxi, active, built_in, min_per_km_enabled, min_per_km)
    values
      (v_code, btrim(p_label_kk), coalesce(btrim(p_label_ru), ''),
       coalesce(btrim(p_desc_kk), ''), coalesce(btrim(p_desc_ru), ''),
       nullif(btrim(coalesce(p_icon_url, '')), ''),
       coalesce(nullif(btrim(coalesce(p_emoji, '')), ''), '🚚'),
       v_next, coalesce(p_is_taxi, false), coalesce(p_active, true), false,
       coalesce(p_min_per_km_enabled, false), coalesce(p_min_per_km, 0))
    returning * into v_row;
  else
    update public.vehicle_types set
      label_kk   = coalesce(nullif(btrim(coalesce(p_label_kk, '')), ''), label_kk),
      label_ru   = coalesce(p_label_ru, label_ru),
      desc_kk    = coalesce(p_desc_kk,  desc_kk),
      desc_ru    = coalesce(p_desc_ru,  desc_ru),
      icon_url   = coalesce(nullif(btrim(coalesce(p_icon_url, '')), ''), icon_url),
      emoji      = coalesce(nullif(btrim(coalesce(p_emoji, '')), ''), emoji),
      is_taxi    = coalesce(p_is_taxi, is_taxi),
      active     = coalesce(p_active,  active),
      min_per_km_enabled = coalesce(p_min_per_km_enabled, min_per_km_enabled),
      min_per_km = coalesce(p_min_per_km, min_per_km),
      updated_at = now()
     where code = v_code
    returning * into v_row;
  end if;

  return v_row;
end;
$$;

grant execute on function public.mod_save_vehicle_type(
  text,text,text,text,text,text,text,boolean,boolean,boolean,int)
  to authenticated;

-- ------------------------------------------------------------
-- 1.4) create_order — 0060 нұсқасы + км бойынша минимум
-- ------------------------------------------------------------
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
  v_km_min bigint;
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

  -- Көлік түрінің км бойынша минимумы (0092): модератор қосқан болса.
  v_km_min := public.vehicle_min_price(v_vehicle, p_distance_km);
  if p_client_price < v_km_min then
    raise exception 'MIN_PER_KM' using detail = v_km_min::text;
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

-- ------------------------------------------------------------
-- 1.5) place_offer — 0075 нұсқасы + км бойынша минимум
-- ------------------------------------------------------------
-- Орындаушы да заказдың ең төменгі сомасынан төмен ұсыныс бере алмайды.
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

  if p_price < public.vehicle_min_price(o.vehicle_type, o.distance_km) then
    raise exception 'MIN_PER_KM';
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

-- ------------------------------------------------------------
-- 2) Такси статустарының push-ы
-- ------------------------------------------------------------
-- 0045 нұсқасы + taxi/umay заказында такси сөздігі. Алушылар мен
-- қалған мінез ӨЗГЕРМЕГЕН.
create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_title_kk text; v_body_kk text;
  v_title_ru text; v_body_ru text;
  v_target uuid;
  v_taxi boolean := coalesce(new.vehicle_type in ('taxi', 'umay'), false);
begin
  if new.status = old.status then return new; end if;

  v_target := new.client_id;

  case new.status
    when 'accepted' then
      if v_taxi then
        v_title_kk := 'Жүргізуші табылды';
        v_body_kk  := 'Жүргізуші заказды қабылдап, жолға шықты.';
        v_title_ru := 'Водитель найден';
        v_body_ru  := 'Водитель принял заказ и выехал.';
      else
        v_title_kk := 'Орындаушы табылды';
        v_body_kk  := 'Орындаушы заказды қабылдап, жолға шықты.';
        v_title_ru := 'Исполнитель найден';
        v_body_ru  := 'Исполнитель принял заказ и выехал.';
      end if;
    when 'arrived' then
      if v_taxi then
        v_title_kk := 'Жүргізуші келді';
        v_body_kk  := 'Көлік күтіп тұр — көлікке отырыңыз.';
        v_title_ru := 'Водитель прибыл';
        v_body_ru  := 'Машина ждёт — садитесь.';
      else
        v_title_kk := 'Орындаушы келді';
        v_body_kk  := 'Орындаушы жеткен жері — қарсы алыңыз.';
        v_title_ru := 'Исполнитель прибыл';
        v_body_ru  := 'Исполнитель на месте — встречайте.';
      end if;
    when 'loading' then
      v_target := new.executor_id;
      if v_taxi then
        v_title_kk := 'Жолаушы отырды';
        v_body_kk  := 'Енді «Жолға шықтық» деп белгілей аласыз.';
        v_title_ru := 'Пассажир сел';
        v_body_ru  := 'Теперь можно отметить «В пути».';
      else
        v_title_kk := 'Клиент тиеуді растады';
        v_body_kk  := 'Енді «Жолға шықтық» деп белгілей аласыз.';
        v_title_ru := 'Клиент подтвердил погрузку';
        v_body_ru  := 'Теперь можно отметить «В пути».';
      end if;
    when 'in_transit' then
      if v_taxi then
        v_title_kk := 'Сапар басталды';
        v_body_kk  := 'Жүргізуші сізді межелі жерге апара жатыр.';
        v_title_ru := 'Поездка началась';
        v_body_ru  := 'Водитель везёт вас к месту назначения.';
      else
        v_title_kk := 'Жүгіңіз жолда';
        v_body_kk  := 'Орындаушы жүкті жеткізуге шықты.';
        v_title_ru := 'Груз в пути';
        v_body_ru  := 'Исполнитель везёт груз к месту доставки.';
      end if;
    when 'completed' then
      if v_taxi then
        v_title_kk := 'Сапар аяқталды';
        v_body_kk  := 'Жүргізушіні бағалауды ұмытпаңыз ⭐';
        v_title_ru := 'Поездка завершена';
        v_body_ru  := 'Не забудьте оценить водителя ⭐';
      else
        v_title_kk := 'Заказ аяқталды';
        v_body_kk  := 'Орындаушыны бағалауды ұмытпаңыз ⭐';
        v_title_ru := 'Заказ завершён';
        v_body_ru  := 'Не забудьте оценить исполнителя ⭐';
      end if;
    when 'cancelled' then
      if new.cancelled_by is not null and new.cancelled_by = new.client_id then
        v_target := new.executor_id;
      else
        v_target := new.client_id;
      end if;
      v_title_kk := 'Заказ тоқтатылды';
      v_body_kk  := coalesce(nullif(new.cancel_reason, ''), 'Заказ тоқтатылды.');
      v_title_ru := 'Заказ отменён';
      v_body_ru  := coalesce(nullif(new.cancel_reason, ''), 'Заказ отменён.');
    when 'searching' then
      v_title_kk := 'Заказ қайта іздеуде';
      if v_taxi then
        v_body_kk  := 'Жүргізуші бас тартты — жаңа жүргізуші ізделуде 🔄';
        v_title_ru := 'Заказ снова в поиске';
        v_body_ru  := 'Водитель отказался — ищем нового 🔄';
      else
        v_body_kk  := 'Орындаушы бас тартты — жаңа орындаушы ізделуде 🔄';
        v_title_ru := 'Заказ снова в поиске';
        v_body_ru  := 'Исполнитель отказался — ищем нового 🔄';
      end if;
    else
      return new;
  end case;

  if v_target is null then return new; end if;

  perform public.send_push(
    v_title_kk, v_body_kk,
    jsonb_build_object('type', 'order_status', 'order_id', new.id::text,
                       'status', new.status::text,
                       'audience', case when v_target = new.client_id
                                        then 'client' else 'executor' end),
    array[v_target],
    v_title_ru, v_body_ru
  );
  return new;
exception when others then
  return new;
end;
$$;
