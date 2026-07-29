-- ============================================================
-- Tasu · 0046_dual_role_and_taxi.sql
-- ============================================================
-- ЕКІ ҮЛКЕН ӨЗГЕРІС:
--
-- A) ҚОС РӨЛ (inDriver үлгісі) — «Орындаушы болу» / «Клиентке ауысу».
--    Бір аккаунт ЕКІ рөлді де ұстай алады. `profiles.role` — БҰРЫНҒЫДАЙ
--    БЕЛСЕНДІ рөл (бүкіл сервер логикасы: лента, push, board, заказ құру —
--    бәрі сол өрісті оқиды, сондықтан ЕШБІР ескі функцияны бұзбаймыз).
--    Жаңасы:
--      • has_client_role / has_executor_role — қандай рөлдер ашылған;
--      • client_rating / client_rating_count / client_trips  — КЛИЕНТ рейтингі;
--      • executor_rating / executor_rating_count / executor_trips — ОРЫНДАУШЫ.
--    `rating` / `rating_count` / `trips` — БЕЛСЕНДІ рөлдің АЙНАСЫ (mirror):
--    оларды `guard_profiles` триггері әр жазуда автоматты синхрондайды.
--    Осылайша ескі оқитын жерлер (профиль, board_feed, mod_*) өзгеріссіз
--    жұмыс істей береді, бірақ рөл ауысқанда рейтинг те АУЫСАДЫ.
--
-- B) ЖАҢА КӨЛІК ТҮРІ — «Такси» (taxi). Модератордың баптауындағы
--    `app_settings.taxi.enabled` арқылы ҚОСЫЛАДЫ/ӨШІРІЛЕДІ: өшулі болса
--    клиентте «Такси» бөлімі мүлдем көрінбейді (баяғыдай бір ғана көлік
--    карусель), қосулы болса — «Такси (ЖАҢА)» / «Жүк · Спецтехника» деген
--    екі санат шығады.
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек.
-- 0045-тен КЕЙІН орындаңыз. Идемпотентті — қайта орындауға болады.
-- ============================================================


-- ============================================================
-- 1) profiles: қос рөл + рөлге бөлінген рейтинг/рейс бағандары
-- ============================================================
alter table public.profiles
  add column if not exists has_client_role   boolean not null default false;
alter table public.profiles
  add column if not exists has_executor_role boolean not null default false;

alter table public.profiles
  add column if not exists client_rating         numeric(3,2) not null default 0;
alter table public.profiles
  add column if not exists client_rating_count   integer      not null default 0;
alter table public.profiles
  add column if not exists client_trips          integer      not null default 0;

alter table public.profiles
  add column if not exists executor_rating       numeric(3,2) not null default 0;
alter table public.profiles
  add column if not exists executor_rating_count integer      not null default 0;
alter table public.profiles
  add column if not exists executor_trips        integer      not null default 0;

-- ---------- бір реттік backfill (қайта орындауға қауіпсіз) ----------
-- Ағымдағы рөл қай болса — жинақталған рейтинг/рейс сол рөлдікі деп
-- есептейміз (бұрын бөлінбеген еді). Тек ӘЛІ КӨШІРІЛМЕГЕН жазбаларға.
update public.profiles p
   set has_executor_role = true,
       executor_rating       = case when p.executor_rating_count = 0 then p.rating       else p.executor_rating       end,
       executor_rating_count = case when p.executor_rating_count = 0 then p.rating_count else p.executor_rating_count end,
       executor_trips        = case when p.executor_trips = 0        then p.trips        else p.executor_trips        end
 where p.role = 'executor' and p.has_executor_role = false;

update public.profiles p
   set has_client_role = true,
       client_rating       = case when p.client_rating_count = 0 then p.rating       else p.client_rating       end,
       client_rating_count = case when p.client_rating_count = 0 then p.rating_count else p.client_rating_count end,
       client_trips        = case when p.client_trips = 0        then p.trips        else p.client_trips        end
 where p.role = 'client' and p.has_client_role = false;

-- Модератор екі рөлге де ауыспайды — бірақ бағандар бос қалмасын.
update public.profiles set has_client_role = true
 where role = 'moderator' and has_client_role = false;

-- Орындаушы профилі бар, бірақ қазір клиент режимінде отырғандар (бұл
-- миграциядан кейінгі күй) — флагы жоғалып қалмауы үшін.
update public.profiles p
   set has_executor_role = true
 where p.has_executor_role = false
   and exists (select 1 from public.executor_profiles e where e.user_id = p.id);


-- ============================================================
-- 2) guard_profiles: қорғау + БЕЛСЕНДІ РӨЛ АЙНАСЫН синхрондау
-- ============================================================
-- Айна (rating/rating_count/trips) — ӘРҚАШАН белсенді рөлдің мәні. Оны
-- триггердің өзі қояды, сол себепті:
--   • клиент қолмен көтере алмайды (тексеру бұрынғыдай);
--   • ескі серверлік код `trips = trips + 1` десе де — айна қайта
--     есептеліп, ҚОС САНАУ БОЛМАЙДЫ (нақты санағыш — рөлдік бағандар);
--   • `switch_role` рөлді ауыстырса — рейтинг сол сәтте ауысады.
create or replace function public.guard_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- Пайдаланушының өз қолымен өзгертуіне тыйым (сервер функциялары
  -- security definer болғандықтан current_user = postgres болады).
  if current_user not in ('postgres','service_role','supabase_admin') then
    if new.role is distinct from old.role
       or new.rating is distinct from old.rating
       or new.rating_count is distinct from old.rating_count
       or new.trust_score is distinct from old.trust_score
       or new.blocked_at is distinct from old.blocked_at
       or new.block_reason is distinct from old.block_reason
       or new.has_client_role is distinct from old.has_client_role
       or new.has_executor_role is distinct from old.has_executor_role
       or new.client_rating is distinct from old.client_rating
       or new.client_rating_count is distinct from old.client_rating_count
       or new.client_trips is distinct from old.client_trips
       or new.executor_rating is distinct from old.executor_rating
       or new.executor_rating_count is distinct from old.executor_rating_count
       or new.executor_trips is distinct from old.executor_trips then
      raise exception 'FORBIDDEN_COLUMN';
    end if;
  end if;

  -- ---- белсенді рөлдің айнасы ----
  if new.role = 'executor' then
    new.rating       := new.executor_rating;
    new.rating_count := new.executor_rating_count;
    new.trips        := new.executor_trips;
  elsif new.role = 'client' then
    new.rating       := new.client_rating;
    new.rating_count := new.client_rating_count;
    new.trips        := new.client_trips;
  end if;
  return new;
end;
$$;

-- INSERT кезінде де айна дұрыс болуы үшін (жаңа тіркелген аккаунт).
create or replace function public.sync_profile_role_mirror_ins()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.role = 'executor' then
    new.has_executor_role := true;
    new.rating       := new.executor_rating;
    new.rating_count := new.executor_rating_count;
    new.trips        := new.executor_trips;
  elsif new.role = 'client' then
    new.has_client_role := true;
    new.rating       := new.client_rating;
    new.rating_count := new.client_rating_count;
    new.trips        := new.client_trips;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profile_role_mirror_ins on public.profiles;
create trigger trg_profile_role_mirror_ins
  before insert on public.profiles
  for each row execute function public.sync_profile_role_mirror_ins();


-- ============================================================
-- 3) recompute_rating: рейтингті РӨЛ БОЙЫНША бөлек есептеу
-- ============================================================
-- reviews.author_role — пікірді КІМ жазғанын білдіреді:
--   author_role = 'client'   → бағаланған адам ОРЫНДАУШЫ рөлінде болған
--   author_role = 'executor' → бағаланған адам КЛИЕНТ рөлінде болған
-- Сол себепті екі рейтинг ешқашан араласпайды: клиенттік рейтинг
-- орындаушыға ауысқанда көрінбейді, керісінше де солай.
--
-- ЕСКІ ЖАЗБАЛАР: `author_role` бағаны 0006-да қосылған. Оған дейінгі
-- пікірлер ТЕК «клиент → орындаушы» бағыты болатын (кестеде басқа бағыт
-- мүлдем қаралмаған), сол себепті `author_role is null` → 'client' деп
-- есептеледі. Әйтпесе ол пікірлер екі рейтингке де кірмей, жинақталған
-- бағалар жоғалып кететін.
create or replace function public.recompute_rating(p_user uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.profiles p
     set executor_rating       = coalesce(x.exec_avg, 0),
         executor_rating_count = coalesce(x.exec_cnt, 0),
         client_rating         = coalesce(x.cli_avg, 0),
         client_rating_count   = coalesce(x.cli_cnt, 0)
    from (
      select
        -- Жақшалар МІНДЕТТІ: `::numeric` FILTER-мен бірге тұрғанда
        -- түсініксіз оқылмауы үшін агрегат толық жақшаға алынған.
        round((avg(r.rating) filter (where coalesce(r.author_role,'client') = 'client'))::numeric, 2)
          as exec_avg,
        (count(*) filter (where coalesce(r.author_role,'client') = 'client'))::int
          as exec_cnt,
        round((avg(r.rating) filter (where r.author_role = 'executor'))::numeric, 2)
          as cli_avg,
        (count(*) filter (where r.author_role = 'executor'))::int
          as cli_cnt
      from public.reviews r
      where r.target_id = p_user
    ) x
   where p.id = p_user;
end;
$$;

-- Бар деректі бір рет қайта есептейміз (бөлінген бағандарды толтыру үшін).
do $$
declare r record;
begin
  for r in select distinct target_id from public.reviews where target_id is not null loop
    perform public.recompute_rating(r.target_id);
  end loop;
end $$;


-- ============================================================
-- 4) Рейс санағышы (trips) — рөл бойынша, заказ аяқталғанда
-- ============================================================
-- Бұрын `order_advance` ішінде `profiles.trips + 1` жазылатын. Енді айна
-- автоматты болғандықтан ол жазу зиянсыз (қайта есептеледі), ал НАҚТЫ
-- санағыш осы триггерде — қай жолмен аяқталса да (order_advance,
-- mod_set_order_status) БІР РЕТ өседі.
create or replace function public.bump_role_trips_on_complete()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    if new.client_id is not null then
      update public.profiles set client_trips = client_trips + 1 where id = new.client_id;
    end if;
    if new.executor_id is not null then
      update public.profiles set executor_trips = executor_trips + 1 where id = new.executor_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bump_role_trips on public.orders;
create trigger trg_bump_role_trips
  after update of status on public.orders
  for each row execute function public.bump_role_trips_on_complete();

-- Бұрын аяқталған заказдар бойынша рөлдік санағышты бір рет толтыру.
update public.profiles p
   set client_trips = coalesce(c.n, 0)
  from (select client_id as id, count(*) n from public.orders
         where status = 'completed' group by client_id) c
 where p.id = c.id and p.client_trips = 0;

update public.profiles p
   set executor_trips = coalesce(e.n, 0)
  from (select executor_id as id, count(*) n from public.orders
         where status = 'completed' and executor_id is not null
         group by executor_id) e
 where p.id = e.id and p.executor_trips = 0;

-- Айнаны бір рет күшпен жаңарту (триггер BEFORE UPDATE-те өзі қояды).
update public.profiles set full_name = full_name;


-- ============================================================
-- 5) switch_role — рөл ауыстыру (қосымша рөл алу)
-- ============================================================
-- Қайтарады: {role, needs_application}
--   needs_application = true → орындаушы профилі әлі жоқ, қосымша
--   «өтінім толтыру» экранын ашуы керек.
create or replace function public.switch_role(p_role text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  p record;
  v_active int;
  v_needs boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_role not in ('client','executor') then raise exception 'BAD_ROLE'; end if;

  select * into p from public.profiles where id = v_uid for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if p.blocked_at is not null then raise exception 'ACCOUNT_BLOCKED'; end if;
  -- Модератор рөлі ауыспайды.
  if p.role = 'moderator' then raise exception 'FORBIDDEN'; end if;

  v_needs := (p_role = 'executor')
         and not exists (select 1 from public.executor_profiles where user_id = v_uid);

  if p.role::text = p_role then
    return jsonb_build_object('role', p_role, 'needs_application', v_needs);
  end if;

  -- Белсенді заказ бар кезде ауысуға болмайды: клиенттің заказы да,
  -- орындаушының рейсі де «ауада» қалып қоймауы үшін.
  select count(*) into v_active
    from public.orders
   where status in ('searching','accepted','arrived','loading','in_transit')
     and (client_id = v_uid or executor_id = v_uid);
  if v_active > 0 then raise exception 'HAS_ACTIVE_ORDERS'; end if;

  update public.profiles
     set role = p_role::public.user_role,
         has_client_role   = has_client_role   or (p_role = 'client'),
         has_executor_role = has_executor_role or (p_role = 'executor')
   where id = v_uid;

  -- Орындаушыдан кетсе — линиядан шығарамыз (жаңа заказ push келмеуі үшін).
  if p_role = 'client' then
    update public.executor_profiles set on_line = false where user_id = v_uid;
  end if;

  return jsonb_build_object('role', p_role, 'needs_application', v_needs);
end;
$$;

grant execute on function public.switch_role(text) to authenticated;

-- Ағымдағы қол жетімді рөлдер (қосымшадағы «ауысу» батырмасы үшін).
create or replace function public.my_roles()
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'role', p.role::text,
    'has_client', p.has_client_role,
    'has_executor', p.has_executor_role,
    'client_rating', p.client_rating,
    'client_rating_count', p.client_rating_count,
    'executor_rating', p.executor_rating,
    'executor_rating_count', p.executor_rating_count,
    'has_executor_profile', exists (select 1 from public.executor_profiles e where e.user_id = p.id)
  )
  from public.profiles p where p.id = auth.uid();
$$;

grant execute on function public.my_roles() to authenticated;


-- ============================================================
-- 6) exec_can_see — ТЕК БЕЛСЕНДІ ОРЫНДАУШЫҒА
-- ============================================================
-- Клиент режиміне ауысқан адам орындаушы лентасын да, «жаңа заказ»
-- push-ын да АЛМАУЫ керек (уведомлениелер белсенді рөлге сай келеді).
-- `exec_can_take` осының үстіне құрылған, `notify_executors_new_order`
-- `exec_can_take`-ті шақырады — сондықтан бір ғана жерді түзету жеткілікті.
create or replace function public.exec_can_see(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' then return false; end if;

  -- БЕЛСЕНДІ РӨЛ орындаушы болуы шарт (қос рөл, 0046).
  if not exists (select 1 from public.profiles
                  where id = p_exec and role = 'executor') then
    return false;
  end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found then return false; end if;      -- статус ТЕКСЕРІЛМЕЙДІ
  if o.client_id = p_exec then return false; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  return true;
end;
$$;


-- ============================================================
-- 6b) listing_json — автордың РӨЛДІК рейтингі
-- ============================================================
-- Хабарландыруда автордың рөлі САҚТАЛҒАН (`l.author_role`): орындаушы
-- «қызмет» жариялайды, клиент «жұмыс». Сол себепті рейтингті ДӘЛ СОЛ РӨЛ
-- бойынша береміз — әйтпесе автор кейін екінші рөлге ауысып кетсе,
-- лентадағы бағасы «бөтен» рөлдің бағасы болып көрінетін.
--
-- Бұл — 0043-тегі `listing_json`-ның ТОЛЫҚ көшірмесі, тек үш жол өзгерді.
create or replace function public.listing_json(l public.listings, p_mine boolean)
returns jsonb
language sql stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id',             l.id,
    'kind',           l.kind,
    'vehicle_type',   l.vehicle_type,
    'city',           l.city,
    'body',           l.body,
    'price_text',     l.price_text,
    'duration_days',  l.duration_days,
    'photos',         to_jsonb(l.photos),
    -- көру саны тек АВТОРҒА беріледі (басқаға null)
    'views',          case when p_mine then l.views else null end,
    'status',         l.status,
    'created_at',     l.created_at,
    'expires_at',     l.expires_at,
    'mine',           p_mine,
    'author_id',      l.author_id,
    'author_role',    l.author_role,
    'author_name',    p.full_name,
    'author_avatar',  p.avatar_url,
    -- ↓ РӨЛДІК рейтинг (0046)
    'author_rating',
      case when l.author_role = 'executor' then p.executor_rating
           else p.client_rating end,
    'author_rating_count',
      case when l.author_role = 'executor' then p.executor_rating_count
           else p.client_rating_count end,
    'author_trips',
      case when l.author_role = 'executor' then p.executor_trips
           else p.client_trips end
  )
  from public.profiles p where p.id = l.author_id;
$$;


-- ============================================================
-- 7) ЖАҢА КӨЛІК ТҮРІ — «Такси» (taxi)
-- ============================================================
alter table public.executor_profiles
  drop constraint if exists executor_profiles_vehicle_type_check;
alter table public.executor_profiles
  add constraint executor_profiles_vehicle_type_check check (vehicle_type in
    ('taxi','gazelle','furgon','kamaz','fura','crane','manipulator','assenizator',
     'excavator','loader','minivan','tractor','avtovyshka'));

alter table public.orders
  drop constraint if exists orders_vehicle_type_check;
alter table public.orders
  add constraint orders_vehicle_type_check check (vehicle_type in
    ('taxi','gazelle','furgon','kamaz','fura','crane','manipulator','assenizator',
     'excavator','loader','minivan','tractor','avtovyshka'));

-- ---------- Такси бөлімі қосулы ма (модератор баптауы) ----------
insert into public.app_settings (key, value)
values ('taxi', jsonb_build_object('enabled', false))
on conflict (key) do nothing;

-- Модератор баптауының ақ тізіміне 'taxi' қосылады (қалғаны 0043-тегідей).
create or replace function public.mod_update_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if p_key not in ('tariffs', 'payment', 'version_gate', 'order_min',
                   'vehicle_rules', 'listings', 'taxi') then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

create or replace function public.taxi_enabled()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select (value->>'enabled')::boolean from public.app_settings where key = 'taxi'),
    false);
$$;

grant execute on function public.taxi_enabled() to anon, authenticated;

-- ---------- create_order: 'taxi' валидацияға + такси ӨШУЛІ болса тыйым ----------
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
  if v_vehicle not in ('taxi','gazelle','furgon','kamaz','fura','crane','manipulator',
                       'assenizator','excavator','loader','minivan','tractor',
                       'avtovyshka') then
    raise exception 'BAD_VEHICLE_TYPE';
  end if;
  -- Такси бөлімі модератор жағынан өшірулі болса — заказ қабылданбайды
  -- (клиенте ол бөлім көрінбейді де, бұл — серверлік сақтандырғыш).
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


-- ============================================================
-- 8) phone_registered — кіру экранындағы «бұл нөмір тіркелмеген» кеңесі
-- ============================================================
-- Кіру сәтсіз болғанда қосымша: «құпиясөз қате ме, әлде мүлдем тіркелмеген
-- бе?» — соны ажыратып, қолданушыны ТІРКЕЛУ бетіне бағыттау үшін.
-- Тек boolean қайтарады (аты-жөні, т.б. ЕШБІР дерек берілмейді).
create or replace function public.phone_registered(p_phone text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles
     where regexp_replace(phone, '\D', '', 'g')
         = regexp_replace(coalesce(p_phone,''), '\D', '', 'g')
       and coalesce(p_phone,'') <> ''
  );
$$;

grant execute on function public.phone_registered(text) to anon, authenticated;
