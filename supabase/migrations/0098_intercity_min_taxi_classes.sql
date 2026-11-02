-- ============================================================
-- Tasu · 0098_intercity_min_taxi_classes.sql
-- ============================================================
-- 1) ҚАЛА ІШІ / ҚАЛААРАЛЫҚ МИНИМУМ БӨЛЕК (0092-ні түзету).
--    Бұрын «1 км = 100 ₸» қалааралық сапарға да қолданылатын: Астана—Тараз
--    1200 км болса, заказдың минимумы 120 000 ₸ болып, клиентке өте қиын
--    болатын. Енді:
--      * км бойынша минимум (min_per_km) — ТЕК ҚАЛА ІШІНДЕ;
--      * қалааралықта км есепке алынбайды: көлік түріне жеке ТҮРАҚТЫ
--        минимум (vehicle_types.min_intercity, бастапқыда 1000 ₸).
--    vehicle_min_price(түр, км, қалааралық) — үшінші параметр қосылды.
--    create_order / place_offer / mod_save_vehicle_type қайта жазылды.
--
-- 2) ТАКСИ САНАТТАРЫ (Эконом / Комфорт / Бизнес). Модератор қосқышымен
--    басқарылады (бастапқыда ӨШІК: app_settings.taxi_classes.enabled).
--      * executor_profiles.taxi_class — жүргізушінің санаты;
--      * taxi_class_rules — «марка (+модель) (+жылдан бастап) → санат»
--        ережелері, модератор өзі енгізеді;
--      * қосқыш қосылғанда санаты жоқ ескі таксистер ережеге сай АВТОМАТ
--        бөлінеді (сәйкес ереже жоқ болса — Эконом);
--      * жаңа тіркелген таксист санатын өзі таңдайды (таңдамаса — автомат);
--      * бекітілген жүргізуші санатын ӨЗІ өзгерте алмайды (guard), тек
--        модератор. Көлігі ауысса (0097) санат ережеге сай қайта есептеледі.
--
-- Идемпотентті. Supabase SQL Editor-да не MCP арқылы қолданылады (0097-ден кейін).
-- ============================================================

-- ------------------------------------------------------------
-- 1.1) Қалааралық түрақты минимум
-- ------------------------------------------------------------
alter table public.vehicle_types
  add column if not exists min_intercity int not null default 1000;

do $$ begin
  alter table public.vehicle_types add constraint vehicle_types_min_intercity_range
    check (min_intercity between 0 and 10000000);
exception when duplicate_object then null; end $$;

comment on column public.vehicle_types.min_intercity is
  'Қалааралық заказдың түрақты минималды бағасы, ₸ (0098). Км есепке алынбайды';

-- ------------------------------------------------------------
-- 1.2) vehicle_min_price v2
-- ------------------------------------------------------------
-- Қала ішінде: км × ₸/км (0092 формуласы). Қалааралықта: min_intercity.
drop function if exists public.vehicle_min_price(text, numeric);

create or replace function public.vehicle_min_price(
  p_vehicle text, p_distance_km numeric, p_intercity boolean default false)
returns bigint
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when coalesce(p_intercity, false)
      then greatest(v.min_intercity, 0)::bigint
      when v.min_per_km_enabled and v.min_per_km > 0
           and coalesce(p_distance_km, 0) > 0
      then (ceil((round(p_distance_km * 100) * v.min_per_km) / 1000.0) * 10)::bigint
      else 0
    end
    from public.vehicle_types v
    where v.code = p_vehicle
  ), 0);
$$;

grant execute on function public.vehicle_min_price(text, numeric, boolean)
  to anon, authenticated;

-- ------------------------------------------------------------
-- 1.3) mod_save_vehicle_type v3 (+ p_min_intercity)
-- ------------------------------------------------------------
drop function if exists public.mod_save_vehicle_type(
  text,text,text,text,text,text,text,boolean,boolean,boolean,int);

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
  p_min_per_km int default null,
  p_min_intercity int default null
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
  if p_min_intercity is not null
     and (p_min_intercity < 0 or p_min_intercity > 10000000) then
    raise exception 'BAD_INPUT';
  end if;

  select * into v_row from public.vehicle_types where code = v_code;

  if v_row.code is null then
    if coalesce(btrim(p_label_kk), '') = '' then raise exception 'BAD_INPUT'; end if;
    select coalesce(max(sort_order), 0) + 10 into v_next from public.vehicle_types;
    insert into public.vehicle_types
      (code, label_kk, label_ru, desc_kk, desc_ru, icon_url, emoji,
       sort_order, is_taxi, active, built_in, min_per_km_enabled, min_per_km,
       min_intercity)
    values
      (v_code, btrim(p_label_kk), coalesce(btrim(p_label_ru), ''),
       coalesce(btrim(p_desc_kk), ''), coalesce(btrim(p_desc_ru), ''),
       nullif(btrim(coalesce(p_icon_url, '')), ''),
       coalesce(nullif(btrim(coalesce(p_emoji, '')), ''), '🚚'),
       v_next, coalesce(p_is_taxi, false), coalesce(p_active, true), false,
       coalesce(p_min_per_km_enabled, false), coalesce(p_min_per_km, 0),
       coalesce(p_min_intercity, 1000))
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
      min_intercity = coalesce(p_min_intercity, min_intercity),
      updated_at = now()
     where code = v_code
    returning * into v_row;
  end if;

  return v_row;
end;
$$;

grant execute on function public.mod_save_vehicle_type(
  text,text,text,text,text,text,text,boolean,boolean,boolean,int,int)
  to authenticated;

-- ------------------------------------------------------------
-- 1.4) create_order — 0092 нұсқасы, минимум қалаға қарай
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

  -- Көлік түрінің минимумы (0098): қала ішінде — км бойынша, қалааралықта —
  -- түрақты сома (км есепке алынбайды).
  v_km_min := public.vehicle_min_price(v_vehicle, p_distance_km, v_intercity);
  if p_client_price < v_km_min then
    if v_intercity then
      raise exception 'MIN_INTERCITY' using detail = v_km_min::text;
    else
      raise exception 'MIN_PER_KM' using detail = v_km_min::text;
    end if;
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
-- 1.5) place_offer — 0092 нұсқасы, минимум қалаға қарай
-- ------------------------------------------------------------
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

  if p_price < public.vehicle_min_price(o.vehicle_type, o.distance_km, v_intercity) then
    if v_intercity then raise exception 'MIN_INTERCITY';
    else raise exception 'MIN_PER_KM'; end if;
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
-- 2.1) Такси санаттары: баған, ереже кестесі, баптау
-- ------------------------------------------------------------
alter table public.executor_profiles
  add column if not exists taxi_class text;

do $$ begin
  alter table public.executor_profiles add constraint executor_profiles_taxi_class_check
    check (taxi_class is null or taxi_class in ('economy', 'comfort', 'business'));
exception when duplicate_object then null; end $$;

comment on column public.executor_profiles.taxi_class is
  'Такси санаты: economy / comfort / business (0098). Тек санаттар қосулы болса';

create table if not exists public.taxi_class_rules (
  id uuid primary key default gen_random_uuid(),
  brand text not null,                       -- кіші әріппен, бос жол емес
  model text not null default '',            -- бос = маркасының бәрі
  min_year int not null default 0,           -- 0 = кез келген жыл
  class text not null check (class in ('economy', 'comfort', 'business')),
  created_at timestamptz not null default now(),
  constraint taxi_class_rules_brand_nonempty check (btrim(brand) <> ''),
  constraint taxi_class_rules_year_range check (min_year between 0 and 2100),
  constraint taxi_class_rules_unique unique (brand, model, min_year)
);

-- Кестеге тікелей қол жеткізу жоқ: тек төмендегі SECURITY DEFINER RPC-лар.
alter table public.taxi_class_rules enable row level security;

insert into public.app_settings (key, value)
values ('taxi_classes', jsonb_build_object('enabled', false))
on conflict (key) do nothing;

create or replace function public.taxi_classes_enabled()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select (value->>'enabled')::boolean
      from public.app_settings where key = 'taxi_classes'
  ), false);
$$;

grant execute on function public.taxi_classes_enabled() to anon, authenticated;

-- Марка/модель/жыл бойынша санат. Алдымен нақтырақ ереже (моделі бар,
-- жылы үлкенірек); ешқайсысы сәйкес келмесе — economy.
create or replace function public.taxi_class_for(
  p_brand text, p_model text, p_year int)
returns text
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select r.class
      from public.taxi_class_rules r
     where r.brand = lower(btrim(coalesce(p_brand, '')))
       and (r.model = ''
            or position(r.model in lower(coalesce(p_model, ''))) > 0)
       and coalesce(p_year, 0) >= r.min_year
     order by (r.model <> '') desc, r.min_year desc, r.created_at
     limit 1
  ), 'economy');
$$;

grant execute on function public.taxi_class_for(text, text, int) to authenticated;

-- ------------------------------------------------------------
-- 2.2) Санатты автомат қою (триггер)
-- ------------------------------------------------------------
-- guard_executor_profiles-тен КЕЙІН жұмыс істейді (аты «zz»): орындаушының
-- өз өзгерісі алдымен тексеріледі, ал автомат қойылған санат тексерілмейді.
create or replace function public.executor_taxi_class_auto()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.vehicle_type::text is distinct from 'taxi' then
    new.taxi_class := null;
    return new;
  end if;
  if not public.taxi_classes_enabled() then return new; end if;

  if tg_op = 'INSERT' then
    if new.taxi_class is null then
      new.taxi_class := public.taxi_class_for(
        new.vehicle_brand, new.vehicle_model, new.vehicle_year);
    end if;
  else
    if new.taxi_class is null
       or (old.status = 'approved'
           and new.taxi_class is not distinct from old.taxi_class
           and (new.vehicle_brand, new.vehicle_model, new.vehicle_year,
                new.vehicle_type::text)
               is distinct from
               (old.vehicle_brand, old.vehicle_model, old.vehicle_year,
                old.vehicle_type::text)) then
      new.taxi_class := public.taxi_class_for(
        new.vehicle_brand, new.vehicle_model, new.vehicle_year);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_zz_executor_taxi_class on public.executor_profiles;
create trigger trg_zz_executor_taxi_class
  before insert or update on public.executor_profiles
  for each row execute function public.executor_taxi_class_auto();

-- ------------------------------------------------------------
-- 2.3) guard_executor_profiles — 0086 нұсқасы + санатты өзгертуге тыйым
-- ------------------------------------------------------------
create or replace function public.guard_executor_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    new.updated_at := now();
    return new;
  end if;
  if new.balance is distinct from old.balance
     or new.total_earned is distinct from old.total_earned
     or new.busy_order_id is distinct from old.busy_order_id
     or new.moderated_by is distinct from old.moderated_by
     or new.moderated_at is distinct from old.moderated_at
     or new.moderation_comment is distinct from old.moderation_comment
     or new.docs_update_requested is distinct from old.docs_update_requested
     or new.docs_update_comment is distinct from old.docs_update_comment
     or new.docs_update_fields is distinct from old.docs_update_fields
     or new.docs_review_pending is distinct from old.docs_review_pending
     or new.trial_granted is distinct from old.trial_granted
     or new.is_umay is distinct from old.is_umay
     -- Бекітілген жүргізуші санатын өзі өзгерте алмайды (0098).
     or (old.status = 'approved'
         and old.taxi_class is not null
         and new.taxi_class is distinct from old.taxi_class) then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  if new.status is distinct from old.status
     and not (old.status = 'rejected' and new.status = 'pending') then
    raise exception 'FORBIDDEN_STATUS';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- 2.4) Модератор RPC-лары
-- ------------------------------------------------------------
-- Баптау, ережелер және әр санаттағы жүргізуші саны.
create or replace function public.mod_taxi_classes()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  return jsonb_build_object(
    'enabled', public.taxi_classes_enabled(),
    'rules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'brand', r.brand, 'model', r.model,
        'min_year', r.min_year, 'class', r.class)
        order by r.brand, r.model, r.min_year)
        from public.taxi_class_rules r
    ), '[]'::jsonb),
    'counts', jsonb_build_object(
      'economy',  (select count(*) from public.executor_profiles
                    where vehicle_type::text = 'taxi' and taxi_class = 'economy'),
      'comfort',  (select count(*) from public.executor_profiles
                    where vehicle_type::text = 'taxi' and taxi_class = 'comfort'),
      'business', (select count(*) from public.executor_profiles
                    where vehicle_type::text = 'taxi' and taxi_class = 'business'),
      'none',     (select count(*) from public.executor_profiles
                    where vehicle_type::text = 'taxi' and taxi_class is null)
    )
  );
end;
$$;

grant execute on function public.mod_taxi_classes() to authenticated;

-- Қосу/өшіру. Қосқанда санаты жоқ барлық таксист ережеге сай бөлінеді.
create or replace function public.mod_set_taxi_classes_enabled(p_enabled boolean)
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_n int := 0;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.app_settings (key, value)
  values ('taxi_classes', jsonb_build_object('enabled', coalesce(p_enabled, false)))
  on conflict (key) do update set value = excluded.value;

  if coalesce(p_enabled, false) then
    update public.executor_profiles e
       set taxi_class = public.taxi_class_for(
             e.vehicle_brand, e.vehicle_model, e.vehicle_year)
     where e.vehicle_type::text = 'taxi' and e.taxi_class is null;
    get diagnostics v_n = row_count;
  end if;

  perform public.mod_audit('taxi_classes_toggle', 'setting', 'taxi_classes',
    jsonb_build_object('enabled', coalesce(p_enabled, false), 'assigned', v_n));
  return v_n;
end;
$$;

grant execute on function public.mod_set_taxi_classes_enabled(boolean) to authenticated;

-- Ереже қосу/өзгерту. Марка мен модель кіші әріпке келтіріледі.
create or replace function public.mod_save_taxi_class_rule(
  p_brand text, p_model text, p_min_year int, p_class text,
  p_id uuid default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_brand text := lower(btrim(coalesce(p_brand, '')));
  v_model text := lower(btrim(coalesce(p_model, '')));
  v_year int := coalesce(p_min_year, 0);
  v_id uuid;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if v_brand = '' or p_class not in ('economy', 'comfort', 'business')
     or v_year < 0 or v_year > 2100 then
    raise exception 'BAD_INPUT';
  end if;

  if p_id is null then
    insert into public.taxi_class_rules (brand, model, min_year, class)
    values (v_brand, v_model, v_year, p_class)
    on conflict (brand, model, min_year) do update set class = excluded.class
    returning id into v_id;
  else
    update public.taxi_class_rules
       set brand = v_brand, model = v_model, min_year = v_year, class = p_class
     where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'NOT_FOUND'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'DUPLICATE_RULE';
end;
$$;

grant execute on function public.mod_save_taxi_class_rule(text, text, int, text, uuid)
  to authenticated;

create or replace function public.mod_delete_taxi_class_rule(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  delete from public.taxi_class_rules where id = p_id;
end;
$$;

grant execute on function public.mod_delete_taxi_class_rule(uuid) to authenticated;

-- БАРЛЫҚ таксистің санатын ережеге сай қайта есептеу (қолмен қойылғандар
-- да қайта есептеледі — модератор батырманы басқанда ғана).
create or replace function public.mod_reassign_taxi_classes()
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  update public.executor_profiles e
     set taxi_class = public.taxi_class_for(
           e.vehicle_brand, e.vehicle_model, e.vehicle_year)
   where e.vehicle_type::text = 'taxi';
  get diagnostics v_n = row_count;
  perform public.mod_audit('taxi_classes_reassign', 'setting', 'taxi_classes',
    jsonb_build_object('count', v_n));
  return v_n;
end;
$$;

grant execute on function public.mod_reassign_taxi_classes() to authenticated;

-- Бір жүргізушіге санатты қолмен қою.
create or replace function public.mod_set_executor_taxi_class(
  p_user uuid, p_class text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator()
     or not public.mod_can('executors') then
    raise exception 'FORBIDDEN';
  end if;
  if p_class not in ('economy', 'comfort', 'business') then
    raise exception 'BAD_INPUT';
  end if;
  update public.executor_profiles
     set taxi_class = p_class
   where user_id = p_user and vehicle_type::text = 'taxi';
  if not found then raise exception 'NOT_FOUND'; end if;
  perform public.mod_audit('executor_taxi_class', 'executor', p_user::text,
    jsonb_build_object('class', p_class));
end;
$$;

grant execute on function public.mod_set_executor_taxi_class(uuid, text) to authenticated;

notify pgrst, 'reload schema';
