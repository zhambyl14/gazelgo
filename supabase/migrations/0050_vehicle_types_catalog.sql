-- ============================================================
-- Tasu · 0050_vehicle_types_catalog.sql
-- ============================================================
-- КӨЛІК ТҮРЛЕРІ ЕНДІ МОДЕРАТОРДЫҢ ҚОЛЫНДА.
--
-- Бұрын түрлер қосымшаның ішінде де (Dart enum), базада да (CHECK тізімі)
-- қатып тұратын: жаңа түр қосу үшін код жазып, миграция шығарып, қосымшаны
-- қайта жариялау керек еді. Енді бәрі `public.vehicle_types` кестесінде:
--   • модератор түр ҚОСАДЫ / ӨШІРЕДІ / РЕТІН ауыстырады;
--   • иконканы PNG етіп ЖҮКТЕЙДІ (`vehicle-icons` bucket-і);
--   • атауы мен ҚЫСҚА АНЫҚТАМАСЫН қазақша/орысша жазады.
-- Қосымшаны жаңартудың қажеті жоқ — каталог серверден келеді.
--
-- Бұл миграция сонымен қатар ЕКІ ЖАҢА ТҮР қосады:
--   • zil  — «ЗиЛ»  (бұрынғы КамАЗ иконкасы соған көшті);
--   • tral — «Трал» (жаңа иконка).
-- Және «КамАЗ» жаңа иконка алды (сурет қосымшаның ішінде, кодпен келеді).
--
-- РЕТ (модератор сұрағаны): Такси · Газель · Манипулятор · Автовышка ·
-- Трактор 3в1 · ЗиЛ · КамАЗ · Фура · Трал · Кран · Экскаватор ·
-- Ассенизатор · Мини вэн · Фургон · Погрузчик.
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек,
-- 0049-дан КЕЙІН. Идемпотентті — бірнеше рет орындауға болады.
-- ============================================================


-- ============================================================
-- 1) Каталог кестесі
-- ============================================================
create table if not exists public.vehicle_types (
  code        text primary key,
  label_kk    text not null,
  label_ru    text not null default '',
  desc_kk     text not null default '',
  desc_ru     text not null default '',
  icon_url    text,
  emoji       text not null default '🚚',
  sort_order  int  not null default 1000,
  -- «Такси» САНАТЫНА жата ма (такси/доставка): бұлар спецтехника
  -- каруселінде емес, бөлек санатта тұрады және `taxi_enabled()`
  -- қосқышына бағынады.
  is_taxi     boolean not null default false,
  -- Өшірулі түр клиентке де, орындаушыға да КӨРІНБЕЙДІ, бірақ ескі
  -- заказдардағы сілтемесі бұзылмайды (сол себепті жою емес, өшіру).
  active      boolean not null default true,
  -- Қосымшамен бірге жеткен түр — иконкасы кодта бар, ЖОЮҒА БОЛМАЙДЫ
  -- (тек өшіруге). Модератор қосқандарын жоюға болады.
  built_in    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint vehicle_types_code_format
    check (code ~ '^[a-z][a-z0-9_]{1,30}$')
);

create index if not exists vehicle_types_order_idx
  on public.vehicle_types (sort_order, code);


-- ============================================================
-- 2) Әдепкі каталогты себу (қосымшадағы тізіммен ДӘЛ БІРДЕЙ)
-- ============================================================
-- `on conflict` — атауы мен анықтамасын модератор өзгертіп қойған болса
-- ҚАЙТА ЖАЗБАЙДЫ, тек built_in белгісін бекітеді. Жаңа екі түр (zil, tral)
-- жоқ болса ғана қосылады.
insert into public.vehicle_types
  (code, label_kk, label_ru, desc_kk, desc_ru, emoji, sort_order, is_taxi, built_in)
values
  ('taxi','Такси','Такси',
   'Жолаушы тасымалы','Перевозка пассажиров','🚕',10,true,true),
  ('delivery','Доставка','Доставка',
   'Жеңіл көлікпен ұсақ жүк жеткізу','Доставка мелких грузов легковым авто','📦',20,true,true),
  ('gazelle','Газель','Газель',
   'Әмбебап жүк тасымалы','Универсальные грузоперевозки','🚚',30,false,true),
  ('manipulator','Манипулятор','Манипулятор',
   'Кран-манипулятор: тиеу және тасымалдау','Кран-манипулятор: погрузка и перевозка','🚚',40,false,true),
  ('avtovyshka','Автовышка','Автовышка',
   'Биіктікте жұмыс','Работы на высоте','🚚',50,false,true),
  ('tractor','Трактор 3в1','Трактор 3в1',
   'Әмбебап трактор (3в1)','Универсальный трактор (3в1)','🚜',60,false,true),
  ('zil','ЗиЛ','ЗиЛ',
   'Орташа көлемдегі жүк тасымалы: құрылыс, ауыл шаруашылығы',
   'Перевозка средних грузов: стройка, село, быт','🚚',70,false,true),
  ('kamaz','КамАЗ','КамАЗ',
   'Ауыр жүк','Тяжёлые грузы','🚚',80,false,true),
  ('fura','Фура','Фура',
   'Ұзақ қашықтық','Дальние расстояния','🚚',90,false,true),
  ('tral','Трал','Трал',
   'Ауыр әрі ірі габаритті техниканы тасымалдау',
   'Перевозка тяжёлой и негабаритной техники','🚚',100,false,true),
  ('crane','Кран','Кран',
   'Автокран: жүк көтеру','Автокран: подъём грузов','🚚',110,false,true),
  ('excavator','Экскаватор','Экскаватор',
   'Қазу, жер жұмыстары','Копка, земляные работы','🚚',120,false,true),
  ('assenizator','Ассенизатор','Ассенизатор',
   'Сұйық қалдықтарды сору','Откачка жидких отходов','🚚',130,false,true),
  ('minivan','Мини вэн','Мини вэн',
   'Жолаушы және шағын жүк','Пассажиры и небольшой груз','🚚',140,false,true),
  ('furgon','Фургон','Фургон',
   'Жабық жүк тасымалы','Закрытые грузоперевозки','🚐',150,false,true),
  ('loader','Погрузчик','Погрузчик',
   'Тиегіш: тиеу, құрылыс жұмыстары','Погрузчик: погрузка, стройработы','🚚',160,false,true)
on conflict (code) do update
  set built_in = true,
      is_taxi  = excluded.is_taxi;

-- Базада бұрын болған, бірақ тізімде жоқ түр қалып қойса — ол да
-- каталогқа кіруі керек (әйтпесе 3-қадамдағы FK құлайды).
insert into public.vehicle_types (code, label_kk, sort_order, built_in)
select distinct v.code, v.code, 900, false
  from (
    select vehicle_type as code from public.orders
    union select vehicle_type from public.executor_profiles
    union select vehicle_type from public.listings
  ) v
 where v.code is not null
   and v.code ~ '^[a-z][a-z0-9_]{1,30}$'
on conflict (code) do nothing;


-- ============================================================
-- 3) CHECK тізімдерін СІЛТЕМЕГЕ (FK) ауыстыру
-- ============================================================
-- Бұрын әр жаңа түр үшін CHECK-ті қайта жазатынбыз. Енді сілтеме:
-- каталогта бар кез келген код автоматты жарамды болады, демек модератор
-- қосқан түр SQL-сыз жұмыс істейді.
alter table public.executor_profiles
  drop constraint if exists executor_profiles_vehicle_type_check;
alter table public.orders
  drop constraint if exists orders_vehicle_type_check;

alter table public.executor_profiles
  drop constraint if exists executor_profiles_vehicle_type_fkey;
alter table public.executor_profiles
  add constraint executor_profiles_vehicle_type_fkey
  foreign key (vehicle_type) references public.vehicle_types(code)
  on update cascade on delete restrict;

alter table public.orders
  drop constraint if exists orders_vehicle_type_fkey;
alter table public.orders
  add constraint orders_vehicle_type_fkey
  foreign key (vehicle_type) references public.vehicle_types(code)
  on update cascade on delete restrict;

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'listings'
                and column_name = 'vehicle_type') then
    alter table public.listings
      drop constraint if exists listings_vehicle_type_fkey;
    alter table public.listings
      add constraint listings_vehicle_type_fkey
      foreign key (vehicle_type) references public.vehicle_types(code)
      on update cascade on delete restrict;
  end if;
end $$;


-- ============================================================
-- 4) RLS: бәрі оқиды, тек модератор жазады
-- ============================================================
alter table public.vehicle_types enable row level security;

drop policy if exists "vehicle_types_read_all" on public.vehicle_types;
create policy "vehicle_types_read_all" on public.vehicle_types
  for select to anon, authenticated using (true);

drop policy if exists "vehicle_types_write_mod" on public.vehicle_types;
create policy "vehicle_types_write_mod" on public.vehicle_types
  for all to authenticated
  using (public.is_moderator()) with check (public.is_moderator());


-- ============================================================
-- 5) Иконка суреттеріне арналған bucket
-- ============================================================
insert into storage.buckets (id, name, public)
values ('vehicle-icons', 'vehicle-icons', true)
on conflict (id) do nothing;

drop policy if exists "vehicle_icons_read_all" on storage.objects;
create policy "vehicle_icons_read_all" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'vehicle-icons');

drop policy if exists "vehicle_icons_write_mod" on storage.objects;
create policy "vehicle_icons_write_mod" on storage.objects
  for all to authenticated
  using (bucket_id = 'vehicle-icons' and public.is_moderator())
  with check (bucket_id = 'vehicle-icons' and public.is_moderator());


-- ============================================================
-- 6) Клиентке арналған каталог (белсенділері ғана)
-- ============================================================
-- Такси санаты өшірулі болса — такси/доставка тізімге МҮЛДЕМ кірмейді
-- (клиент те, орындаушы да оны көрмеуі керек).
create or replace function public.vehicle_catalog()
returns setof public.vehicle_types
language sql stable security definer
set search_path = public, pg_temp
as $$
  select * from public.vehicle_types
   where active
     and (not is_taxi or public.taxi_enabled())
   order by sort_order, code;
$$;

grant execute on function public.vehicle_catalog() to anon, authenticated;


-- ============================================================
-- 7) Модератордың CRUD функциялары
-- ============================================================

-- 7.1 Модератор көретін ТОЛЫҚ тізім (өшірулілерін қоса).
create or replace function public.mod_vehicle_types()
returns setof public.vehicle_types
language sql stable security definer
set search_path = public, pg_temp
as $$
  select * from public.vehicle_types
   where public.is_moderator()
   order by sort_order, code;
$$;

grant execute on function public.mod_vehicle_types() to authenticated;


-- 7.2 Қосу / өзгерту. `p_code` жаңа болса — қосылады, бар болса —
-- берілген өрістері ғана жаңарады (null берілгені өзгермейді).
create or replace function public.mod_save_vehicle_type(
  p_code     text,
  p_label_kk text default null,
  p_label_ru text default null,
  p_desc_kk  text default null,
  p_desc_ru  text default null,
  p_icon_url text default null,
  p_emoji    text default null,
  p_is_taxi  boolean default null,
  p_active   boolean default null
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

  select * into v_row from public.vehicle_types where code = v_code;

  if v_row.code is null then
    -- ЖАҢА түр: атауы міндетті, реті тізімнің СОҢЫНА қойылады.
    if coalesce(btrim(p_label_kk), '') = '' then raise exception 'BAD_INPUT'; end if;
    select coalesce(max(sort_order), 0) + 10 into v_next from public.vehicle_types;
    insert into public.vehicle_types
      (code, label_kk, label_ru, desc_kk, desc_ru, icon_url, emoji,
       sort_order, is_taxi, active, built_in)
    values
      (v_code, btrim(p_label_kk), coalesce(btrim(p_label_ru), ''),
       coalesce(btrim(p_desc_kk), ''), coalesce(btrim(p_desc_ru), ''),
       nullif(btrim(coalesce(p_icon_url, '')), ''),
       coalesce(nullif(btrim(coalesce(p_emoji, '')), ''), '🚚'),
       v_next, coalesce(p_is_taxi, false), coalesce(p_active, true), false)
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
      updated_at = now()
     where code = v_code
    returning * into v_row;
  end if;

  return v_row;
end;
$$;

grant execute on function public.mod_save_vehicle_type(
  text,text,text,text,text,text,text,boolean,boolean) to authenticated;


-- 7.3 Ретті сақтау: кодтар тізімі берілген РЕТПЕН нөмірленеді.
create or replace function public.mod_reorder_vehicle_types(p_codes text[])
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_moderator() then raise exception 'NOT_MODERATOR'; end if;
  if p_codes is null or array_length(p_codes, 1) is null then return; end if;

  update public.vehicle_types v
     set sort_order = q.pos * 10,
         updated_at = now()
    from (select unnest(p_codes) as code,
                 generate_subscripts(p_codes, 1) as pos) q
   where v.code = q.code;
end;
$$;

grant execute on function public.mod_reorder_vehicle_types(text[]) to authenticated;


-- 7.4 Жою. Түр ҚОЛДАНЫЛҒАН болса (заказ/орындаушы/хабарландыру) жойылмайды
-- — оның орнына ӨШІРІЛЕДІ (`active = false`), сол себепті ескі заказдар
-- бұзылмайды. Қосымшамен бірге келген түрді (built_in) де тек өшіруге болады.
--
-- Қайтарады: 'deleted' немесе 'deactivated'.
create or replace function public.mod_delete_vehicle_type(p_code text)
returns text
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_code text := lower(btrim(coalesce(p_code, '')));
  v_row  public.vehicle_types;
  v_used boolean;
begin
  if not public.is_moderator() then raise exception 'NOT_MODERATOR'; end if;

  select * into v_row from public.vehicle_types where code = v_code;
  if v_row.code is null then raise exception 'NOT_FOUND'; end if;

  select exists (select 1 from public.orders where vehicle_type = v_code)
      or exists (select 1 from public.executor_profiles where vehicle_type = v_code)
      or exists (select 1 from public.listings where vehicle_type = v_code)
    into v_used;

  if v_row.built_in or v_used then
    update public.vehicle_types
       set active = false, updated_at = now()
     where code = v_code;
    return 'deactivated';
  end if;

  delete from public.vehicle_types where code = v_code;
  return 'deleted';
end;
$$;

grant execute on function public.mod_delete_vehicle_type(text) to authenticated;


-- ============================================================
-- 8) create_order — қатып қалған тізімнің орнына КАТАЛОГ тексерілуі
-- ============================================================
-- 0048-дегі нұсқаның көшірмесі, тек көлік түрін тексеру өзгерді: енді
-- жарамды түрлер `vehicle_types` кестесінен алынады, демек модератор
-- қосқан жаңа түрге заказ беруге БІРДЕН болады (SQL-сыз).
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
  v_is_taxi boolean;
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


-- ============================================================
-- 9) Хабарландырулар тақтасы (0043) — сол сияқты каталогқа сүйенеді
-- ============================================================
-- `create_listing` / `update_listing` ішіндегі қатып қалған тізімнің
-- орнына каталог тексеріледі. Такси санатының түрлері тақтада ЖОҚ
-- (тақта — жүк/спецтехника үшін), сол себепті `not is_taxi` шарты бар.
create or replace function public.valid_listing_vehicle(p_code text)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.vehicle_types
     where code = lower(btrim(coalesce(p_code, '')))
       and active and not is_taxi
  );
$$;

grant execute on function public.valid_listing_vehicle(text) to authenticated;

-- Функциялардың ДЕНЕСІН қайта жазбай, ішіндегі қатып қалған тізімді
-- ауыстырамыз: `create_listing`/`update_listing` 0043-те ұзын жазылған,
-- оларды түгел көшіріп қою — үнсіз айырмашылық шығару қаупі. Сол себепті
-- анықтамасын базадан алып, тек ОСЫ БІР шартты алмастырып, қайта саламыз.
-- Идемпотентті: екінші рет орындағанда тізім қалмағандықтан ештеңе
-- өзгермейді (ескерту де шықпайды — шарт әлдеқашан ауысқан).
do $$
declare
  r     record;
  v_new text;
begin
  for r in
    select p.oid,
           p.proname,
           pg_get_functiondef(p.oid) as def,
           pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('create_listing', 'update_listing')
  loop
    -- `p_vehicle_type not in ('gazelle', … )` — жол ауысуы да, бос орын да
    -- еркін болуы мүмкін, сол себепті регуляр өрнек.
    v_new := regexp_replace(
      r.def,
      'p_vehicle_type\s+not\s+in\s*\(\s*''gazelle''[^)]*\)',
      'not public.valid_listing_vehicle(p_vehicle_type)',
      'gi');

    if v_new <> r.def then
      execute v_new;
      raise notice 'vehicle catalog → %(%)', r.proname, r.args;
    elsif r.def !~ 'valid_listing_vehicle' then
      raise warning 'МАҢЫЗДЫ: %(%) ішіндегі көлік түрін тексеруді ҚОЛМЕН '
        'ауыстырыңыз → not public.valid_listing_vehicle(p_vehicle_type)',
        r.proname, r.args;
    end if;
  end loop;
end $$;
