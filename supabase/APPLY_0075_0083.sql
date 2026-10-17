-- Tasu · 0075–0083 миграциялары БІР файлда (жұмыс ноутбугынан келген жаңа мүмкіндіктер).
-- Supabase → SQL Editor-ға толық қойып, Run басыңыз. Әр бөлім идемпотентті — қайталап орындауға болады.
-- Тексеру: select proname from pg_proc where proname in ('order_chat_send','set_order_recipient','mod_dashboard_series'); — 3 жол шығуы керек.


-- ################################################################
-- ### 0075_live_tracking_eta.sql
-- ################################################################
-- ============================================================
-- Tasu · 0075_live_tracking_eta.sql
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


-- ################################################################
-- ### 0076_recipient_delivery_code.sql
-- ################################################################
-- ============================================================
-- Tasu · 0076_recipient_delivery_code.sql
-- ============================================================
-- АЛУШЫҒА СІЛТЕМЕ және ЖЕТКІЗУ КОДЫ.
--
-- Мәселе: жүкті көбіне БАСҚА адам қабылдайды. Ол көліктің қайда екенін
-- білмейді, ал жүк дұрыс адамға тапсырылғанына кепіл жоқ.
--
-- Шешім:
--   * Клиент заказға АЛУШЫНЫ (аты + телефоны) қосады — `order_recipients`.
--   * Сервер 4 таңбалы КОД жасайды. Код орындаушыға КӨРІНБЕЙДІ (кестеге
--     тікелей қатынас жоқ, тек RPC арқылы, ал орындаушыға код берілмейді).
--   * Алушыға WhatsApp арқылы ЖЕКЕ сілтеме жіберіледі (`/track/<token>`):
--     картада көлік, келу уақыты және КОД. Бұл токен `orders.share_token`
--     емес (ол заказ жолында тұр, лентадағы орындаушылар да оқи алады) —
--     алушының өз токені, тек осы кестеде.
--   * Орындаушы «Аяқтау» басқанда алушыдан кодты сұрап енгізеді
--     (`verify_delivery_code`). Код расталмайынша заказ АЯҚТАЛМАЙДЫ
--     (триггер `CODE_REQUIRED` шығарады).
--   * Алушы кодты жоғалтса — клиент өз қосымшасынан «Жүк жетті» деп растай
--     алады (`client_confirm_delivery`), модератор кез келген уақытта.
--   * Код 6 рет қате енгізілсе — құлыпталады (CODE_LOCKED), тек клиент не
--     модератор растай алады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0075-тен кейін).
-- ============================================================

create table if not exists public.order_recipients (
  order_id          uuid primary key references public.orders(id) on delete cascade,
  name              text not null default '',
  phone             text not null,
  delivery_code     text,
  token             uuid not null default gen_random_uuid(),
  code_verified_at  timestamptz,
  verified_by       text,          -- 'code' | 'client' | 'moderator'
  attempts          int not null default 0,
  created_at        timestamptz not null default now()
);

create unique index if not exists idx_order_recipients_token
  on public.order_recipients (token);

alter table public.order_recipients enable row level security;
-- Тікелей SELECT/INSERT саясаты ӘДЕЙІ ЖОҚ: код орындаушыға көрінбеуі керек.
-- Барлық қатынас төмендегі SECURITY DEFINER функциялары арқылы.

-- Телефонды 7XXXXXXXXXX пішініне келтіру (қосымшадағы Phone.normalize-пен
-- бірдей ереже). Дұрыс емес болса — null.
create or replace function public.norm_kz_phone(p_raw text)
returns text
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  d text := regexp_replace(coalesce(p_raw, ''), '\D', '', 'g');
begin
  if length(d) = 11 and left(d, 1) = '8' then d := '7' || substr(d, 2); end if;
  if length(d) = 10 then d := '7' || d; end if;
  if length(d) = 11 and left(d, 2) = '77' then return d; end if;
  return null;
end;
$$;

-- ============================================================
-- 1) Клиент алушыны қосады / өзгертеді / алып тастайды
-- ============================================================
create or replace function public.set_order_recipient(
  p_order uuid,
  p_name text,
  p_phone text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_phone text;
  r record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status not in ('searching','accepted','arrived','loading','in_transit') then
    raise exception 'NOT_AVAILABLE';
  end if;

  -- Бос телефон — алушыны алып тастау (код әлі расталмаған болса ғана).
  if coalesce(trim(p_phone), '') = '' then
    delete from public.order_recipients
     where order_id = p_order and code_verified_at is null;
    return null;
  end if;

  v_phone := public.norm_kz_phone(p_phone);
  if v_phone is null then raise exception 'BAD_PHONE'; end if;

  insert into public.order_recipients (order_id, name, phone, delivery_code)
  values (p_order, left(coalesce(trim(p_name), ''), 80), v_phone,
          lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict (order_id) do update
    set name = excluded.name,
        phone = excluded.phone,
        delivery_code = coalesce(public.order_recipients.delivery_code,
                                 excluded.delivery_code);

  select * into r from public.order_recipients where order_id = p_order;
  return jsonb_build_object(
    'name', r.name,
    'phone', r.phone,
    'code', r.delivery_code,
    'token', r.token::text,
    'verified_at', r.code_verified_at
  );
end;
$$;

grant execute on function public.set_order_recipient(uuid, text, text) to authenticated;

-- ============================================================
-- 2) Алушы туралы мәлімет (кім сұрайтынына қарай)
-- ============================================================
-- Клиент пен модератор — бәрін (кодты қоса). Тағайындалған орындаушы —
-- аты мен телефонын (хабарласу үшін) және «код керек пе» белгісін, бірақ
-- КОДТЫҢ ӨЗІН ЕМЕС.
create or replace function public.get_order_recipient(p_order uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  r record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  select * into r from public.order_recipients where order_id = p_order;
  if not found then return null; end if;

  if o.client_id = v_uid or public.is_moderator() then
    return jsonb_build_object(
      'name', r.name, 'phone', r.phone,
      'code', r.delivery_code, 'token', r.token::text,
      'verified_at', r.code_verified_at, 'verified_by', r.verified_by,
      'attempts', r.attempts
    );
  end if;

  if o.executor_id = v_uid
     and o.status in ('accepted','arrived','loading','in_transit','completed') then
    return jsonb_build_object(
      'name', r.name, 'phone', r.phone,
      'has_code', r.delivery_code is not null,
      'verified_at', r.code_verified_at,
      'attempts', r.attempts
    );
  end if;

  raise exception 'FORBIDDEN';
end;
$$;

grant execute on function public.get_order_recipient(uuid) to authenticated;

-- ============================================================
-- 3) Орындаушы алушыдан алған кодты енгізеді
-- ============================================================
-- Қате кодта ҚАТЕ ШЫҒАРМАЙМЫЗ (әйтпесе транзакция кері қайтып, қате
-- әрекеттер саналмай қалар еді) — {ok:false, left:N} қайтарамыз.
create or replace function public.verify_delivery_code(p_order uuid, p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  r record;
  c_max constant int := 6;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.executor_id is distinct from v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status not in ('arrived','loading','in_transit') then
    raise exception 'BAD_TRANSITION';
  end if;

  select * into r from public.order_recipients where order_id = p_order for update;
  if not found then
    return jsonb_build_object('ok', true);
  end if;
  if r.delivery_code is null or r.code_verified_at is not null then
    return jsonb_build_object('ok', true);
  end if;
  if r.attempts >= c_max then raise exception 'CODE_LOCKED'; end if;

  if trim(coalesce(p_code, '')) = r.delivery_code then
    update public.order_recipients
       set code_verified_at = now(), verified_by = 'code'
     where order_id = p_order;
    return jsonb_build_object('ok', true);
  end if;

  update public.order_recipients set attempts = attempts + 1
   where order_id = p_order;
  return jsonb_build_object('ok', false, 'left', greatest(c_max - r.attempts - 1, 0));
end;
$$;

grant execute on function public.verify_delivery_code(uuid, text) to authenticated;

-- ============================================================
-- 4) Клиент жеткізуді өзі растайды (алушы кодты жоғалтса)
-- ============================================================
create or replace function public.client_confirm_delivery(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.client_id <> v_uid and not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  update public.order_recipients
     set code_verified_at = coalesce(code_verified_at, now()),
         verified_by = coalesce(verified_by,
                                case when o.client_id = v_uid then 'client'
                                     else 'moderator' end)
   where order_id = p_order;
end;
$$;

grant execute on function public.client_confirm_delivery(uuid) to authenticated;

-- ============================================================
-- 5) Код расталмайынша заказ аяқталмайды
-- ============================================================
create or replace function public.guard_delivery_code()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    -- Модератор (оқыс жағдай) — тексерусіз.
    if public.is_moderator() then return new; end if;
    if exists (
      select 1 from public.order_recipients r
       where r.order_id = new.id
         and r.delivery_code is not null
         and r.code_verified_at is null
    ) then
      raise exception 'CODE_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_delivery_code on public.orders;
create trigger trg_guard_delivery_code
  before update of status on public.orders
  for each row execute function public.guard_delivery_code();

-- ============================================================
-- 6) track_order v2 — алушының беті (код + келу уақыты) / бөлісу беті
-- ============================================================
-- Токен екі түрлі болуы мүмкін:
--   * АЛУШЫ токені (order_recipients.token) — бет кодты да көрсетеді әрі
--     share_trip баптауына тәуелсіз жұмыс істейді;
--   * БӨЛІСУ токені (orders.share_token) — бұрынғыдай, кодсыз.
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
  v_order_id uuid;
  v_is_recipient boolean := false;
  v_recipient_name text;
  v_code text;
  v_verified_at timestamptz;
  v_executor_name text;
  v_lat float8; v_lng float8; v_heading float8; v_loc_at timestamptz;
begin
  begin
    v_token := p_token::uuid;
  exception when others then
    return jsonb_build_object('error', 'NOT_FOUND');
  end;

  select order_id, name, delivery_code, code_verified_at
    into v_order_id, v_recipient_name, v_code, v_verified_at
    from public.order_recipients where token = v_token;
  if v_order_id is not null then
    v_is_recipient := true;
    select * into o from public.orders where id = v_order_id;
    if not found then return jsonb_build_object('error', 'NOT_FOUND'); end if;
  else
    select coalesce((value->>'enabled')::boolean, false) into v_enabled
      from public.app_settings where key = 'share_trip';
    if not coalesce(v_enabled, false) then
      return jsonb_build_object('error', 'DISABLED');
    end if;
    select * into o from public.orders where share_token = v_token;
    if not found then
      return jsonb_build_object('error', 'NOT_FOUND');
    end if;
  end if;

  if o.executor_id is not null then
    -- Тек ЕСІМІ (тегісіз) — бөтен адамға толық аты-жөн керек емес.
    select split_part(trim(full_name), ' ', 1) into v_executor_name
      from public.profiles where id = o.executor_id;
  end if;

  select coalesce((value->>'enabled')::boolean, false) into v_live
    from public.app_settings where key = 'live_tracking';

  if coalesce(v_live, false) and o.status in ('accepted','arrived','loading','in_transit') then
    select lat, lng, heading, updated_at into v_lat, v_lng, v_heading, v_loc_at
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
    'arrive_by', o.arrive_by, 'arrived_at', o.arrived_at,
    'executor_name', v_executor_name,
    'lat', v_lat, 'lng', v_lng, 'heading', v_heading, 'loc_updated_at', v_loc_at,
    'is_recipient', v_is_recipient,
    'recipient_name', v_recipient_name,
    -- Код тек алушының бетінде әрі әлі расталмаған болса.
    'delivery_code', case
      when v_is_recipient and v_verified_at is null then v_code
    end,
    'delivered', case when v_is_recipient then v_verified_at is not null end
  );
end;
$$;

grant execute on function public.track_order(text) to anon, authenticated;


-- ################################################################
-- ### 0077_order_extras_price_hint.sql
-- ################################################################
-- ============================================================
-- Tasu · 0077_order_extras_price_hint.sql
-- ============================================================
--   1) ҚОСЫМША ҚЫЗМЕТТЕР (міндетті емес): тиеуші саны, қабат, лифт.
--      Газель/жүк заказдарының көбінде «жүк тиеуші керек пе, нешінші
--      қабат, лифт бар ма» деген сұрақ бар — бұрын клиент оны түсініктемеге
--      еркін мәтінмен жазатын (не мүлдем жазбайтын), орындаушы баға
--      қойғанда білмейтін. Енді — нақты өрістер, лентада белгі болып шығады.
--   2) update_order_details — клиент заказды ІЗДЕУ кезінде өңдей алады:
--      сипаттама, түсініктеме, қосымша қызметтер (бұрын тек бағаны көтеруге
--      болатын — қате жазылса, заказды тоқтатып, қайта беру керек еді).
--      create_order-ге ТИІСПЕЙМІЗ: қосымша өрістер заказ құрылған соң осы
--      функциямен жазылады (ескі қосымша нұсқалары бұрынғыдай жұмыс істейді).
--   3) order_price_hint — ҰСЫНЫЛАТЫН БАҒА: соңғы 90 күндегі ұқсас (көлік
--      түрі, қашықтық, қала) аяқталған заказдардың нақты бағасы бойынша
--      «әдетте 5 500 – 7 000 ₸». Дерек аз болса (< 5) — ештеңе қайтармайды
--      (қате кеңес бергеннен үндемеген жақсы). `pricing_hint` баптауымен
--      қосылады/өшіріледі (0060-та бұрыннан бар, әдепкі — қосулы).
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0076-тен кейін).
-- ============================================================

-- ============================================================
-- 1) Қосымша қызметтер өрістері
-- ============================================================
alter table public.orders add column if not exists loaders smallint not null default 0;
alter table public.orders add column if not exists floor_from smallint;
alter table public.orders add column if not exists floor_to smallint;
alter table public.orders add column if not exists has_elevator boolean;

do $$ begin
  alter table public.orders add constraint orders_loaders_range
    check (loaders between 0 and 10);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.orders add constraint orders_floors_range
    check ((floor_from is null or floor_from between -5 and 60)
       and (floor_to is null or floor_to between -5 and 60));
exception when duplicate_object then null; end $$;

-- ============================================================
-- 2) Клиент заказды іздеу кезінде өңдейді
-- ============================================================
-- null параметр — «өзгертпе». Қосымша қызметтер БІР ТОП болып жазылады:
-- p_loaders берілсе, қабат пен лифт те берілген мәнге ауысады (null —
-- тазалау).
create or replace function public.update_order_details(
  p_order uuid,
  p_cargo text default null,
  p_comment text default null,
  p_loaders int default null,
  p_floor_from int default null,
  p_floor_to int default null,
  p_elevator boolean default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  if p_cargo is not null and trim(p_cargo) = '' then
    raise exception 'BAD_INPUT';
  end if;
  if p_loaders is not null and (p_loaders < 0 or p_loaders > 10) then
    raise exception 'BAD_INPUT';
  end if;
  if (p_floor_from is not null and (p_floor_from < -5 or p_floor_from > 60))
     or (p_floor_to is not null and (p_floor_to < -5 or p_floor_to > 60)) then
    raise exception 'BAD_INPUT';
  end if;

  update public.orders
     set cargo_desc = case when p_cargo is null then cargo_desc
                           else left(trim(p_cargo), 500) end,
         comment = case when p_comment is null then comment
                        else left(trim(p_comment), 500) end,
         loaders = coalesce(p_loaders, loaders),
         floor_from = case when p_loaders is null then floor_from
                           else p_floor_from end,
         floor_to = case when p_loaders is null then floor_to
                         else p_floor_to end,
         has_elevator = case when p_loaders is null then has_elevator
                             else p_elevator end
   where id = p_order;
end;
$$;

grant execute on function
  public.update_order_details(uuid, text, text, int, int, int, boolean)
  to authenticated;

-- ============================================================
-- 3) Ұсынылатын баға
-- ============================================================
create index if not exists idx_orders_completed_vehicle
  on public.orders (vehicle_type, completed_at desc)
  where status = 'completed';

create or replace function public.order_price_hint(
  p_vehicle text,
  p_distance_km numeric,
  p_city text default null,
  p_intercity boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_enabled boolean;
  v_lo numeric;
  v_hi numeric;
  v_city text := public.norm_city(p_city);
  v_n int := 0;
  v_p25 numeric;
  v_p50 numeric;
  v_p75 numeric;
begin
  if p_vehicle is null or p_distance_km is null or p_distance_km <= 0 then
    return null;
  end if;

  select coalesce((value->>'enabled')::boolean, true) into v_enabled
    from public.app_settings where key = 'pricing_hint';
  if not coalesce(v_enabled, true) then return null; end if;

  -- Ұқсас қашықтық терезесі: қысқа сапарларда ±3 км, ұзындарда −40% / +50%.
  v_lo := greatest(p_distance_km * 0.6, p_distance_km - 3);
  v_hi := p_distance_km * 1.5 + 3;

  -- 1-қадам: СОЛ ҚАЛАДАҒЫ заказдар (қала ішіндегі заказ үшін).
  if not coalesce(p_intercity, false) and v_city is not null then
    select count(*),
           percentile_cont(0.25) within group (order by s.price),
           percentile_cont(0.5)  within group (order by s.price),
           percentile_cont(0.75) within group (order by s.price)
      into v_n, v_p25, v_p50, v_p75
      from (
        select coalesce(o.final_price, o.client_price)::numeric as price
          from public.orders o
         where o.status = 'completed'
           and o.completed_at > now() - interval '90 days'
           and o.vehicle_type::text = p_vehicle
           and coalesce(o.final_price, o.client_price) > 0
           and o.distance_km between v_lo and v_hi
           and public.norm_city(o.from_city) = v_city
      ) s;
  end if;

  -- 2-қадам: дерек аз — барлық қала бойынша (межгород белгісі сәйкес).
  if coalesce(v_n, 0) < 5 then
    select count(*),
           percentile_cont(0.25) within group (order by s.price),
           percentile_cont(0.5)  within group (order by s.price),
           percentile_cont(0.75) within group (order by s.price)
      into v_n, v_p25, v_p50, v_p75
      from (
        select coalesce(o.final_price, o.client_price)::numeric as price
          from public.orders o
         where o.status = 'completed'
           and o.completed_at > now() - interval '90 days'
           and o.vehicle_type::text = p_vehicle
           and coalesce(o.final_price, o.client_price) > 0
           and o.distance_km between v_lo and v_hi
           and (coalesce(public.norm_city(o.from_city), '')
                  <> coalesce(public.norm_city(o.to_city), ''))
               = coalesce(p_intercity, false)
      ) s;
  end if;

  if coalesce(v_n, 0) < 5 then return null; end if;

  return jsonb_build_object(
    'low',     (round(v_p25 / 100) * 100)::bigint,
    'typical', (round(v_p50 / 100) * 100)::bigint,
    'high',    (round(v_p75 / 100) * 100)::bigint,
    'samples', v_n
  );
end;
$$;

grant execute on function public.order_price_hint(text, numeric, text, boolean)
  to anon, authenticated;


-- ################################################################
-- ### 0078_order_chat.sql
-- ################################################################
-- ============================================================
-- Tasu · 0078_order_chat.sql
-- ============================================================
-- ЗАКАЗ ЧАТЫ: клиент ↔ орындаушы (+ модератор бақылайды).
--
--   * Чат тек заказ ҚАБЫЛДАНҒАН соң ашылады (accepted … in_transit) және
--     аяқталғаннан кейін 24 сағатқа дейін (жоғалған зат т.б. үшін).
--   * Хабар жіберілгенде екінші тарапқа push кетеді.
--   * МОДЕРАТОР барлық чатты оқи алады (иесінің 2026-10-16 талабы:
--     «оқи алуға, тексеріп отыруға доступ болсын») және қажет болса өзі
--     жаза алады («Модератор» белгісімен). Сілтеме не балағат сөз бар хабар
--     `flagged` белгісін алады — модератор оларды бірінші көреді.
--   * Пайдаланушылар чаттың модератор тарапынан қаралуы мүмкін екенін
--     біледі (қосымшада чаттың басында ескерту тұрады).
--   * `order_chat` баптауы (әдепкі — қосулы) арқылы өшіруге болады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0077-тен кейін).
-- ============================================================

create table if not exists public.order_messages (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  sender_role text not null check (sender_role in ('client','executor','moderator')),
  body        text not null check (length(trim(body)) between 1 and 1000),
  flagged     boolean not null default false,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists idx_order_messages_order
  on public.order_messages (order_id, created_at);
create index if not exists idx_order_messages_recent
  on public.order_messages (created_at desc);

-- Заказдың тарабы ма (клиент не тағайындалған орындаушы). SECURITY DEFINER —
-- RLS саясатының ішінде orders кестесінің өз RLS-іне тірелмеу үшін.
create or replace function public.is_order_party(p_order uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.orders o
     where o.id = p_order
       and (o.client_id = auth.uid() or o.executor_id = auth.uid())
  );
$$;

grant execute on function public.is_order_party(uuid) to authenticated;

alter table public.order_messages enable row level security;

drop policy if exists order_messages_read on public.order_messages;
create policy order_messages_read on public.order_messages
  for select to authenticated
  using (public.is_moderator() or public.is_order_party(order_id));
-- INSERT/UPDATE саясаты ЖОҚ — тек төмендегі RPC арқылы.

insert into public.app_settings (key, value)
values ('order_chat', jsonb_build_object('enabled', true))
on conflict (key) do nothing;

-- ============================================================
-- Хабар жіберу
-- ============================================================
create or replace function public.order_chat_send(p_order uuid, p_body text)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role text;
  v_body text := trim(coalesce(p_body, ''));
  v_flag boolean;
  v_id uuid;
  v_enabled boolean;
  v_targets uuid[];
  v_preview text;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if v_body = '' then raise exception 'EMPTY'; end if;
  if length(v_body) > 1000 then v_body := left(v_body, 1000); end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  if o.client_id = v_uid then
    v_role := 'client';
  elsif o.executor_id = v_uid then
    v_role := 'executor';
  elsif public.is_moderator() then
    v_role := 'moderator';
  else
    raise exception 'FORBIDDEN';
  end if;

  if v_role <> 'moderator' then
    select coalesce((value->>'enabled')::boolean, true) into v_enabled
      from public.app_settings where key = 'order_chat';
    if not coalesce(v_enabled, true) then raise exception 'DISABLED'; end if;

    if not (o.status in ('accepted','arrived','loading','in_transit')
            or (o.status = 'completed'
                and o.completed_at > now() - interval '24 hours')) then
      raise exception 'CHAT_CLOSED';
    end if;
  end if;

  -- Модератордың назарына: сілтеме не балағат сөз.
  v_flag := v_body ~* '(https?://|www\.|t\.me/|wa\.me/)'
         or v_body ~* '(бляд|сука|хуй|пизд|ебан|мразь|qotaq|қотақ|сігіл)';

  insert into public.order_messages (order_id, sender_id, sender_role, body, flagged)
  values (p_order, v_uid, v_role, v_body, v_flag)
  returning id into v_id;

  -- Екінші тарапқа push.
  v_targets := array_remove(array[
    case when v_role <> 'client' then o.client_id end,
    case when v_role <> 'executor' then o.executor_id end
  ], null);
  v_preview := case when length(v_body) > 90 then left(v_body, 90) || '…'
                    else v_body end;

  if coalesce(array_length(v_targets, 1), 0) > 0 then
    perform public.send_push(
      case v_role when 'moderator' then 'Модератордан хабар'
                  when 'client' then 'Клиенттен хабар'
                  else 'Орындаушыдан хабар' end,
      v_preview,
      jsonb_build_object('type', 'order_chat', 'order_id', p_order::text),
      v_targets,
      case v_role when 'moderator' then 'Сообщение модератора'
                  when 'client' then 'Сообщение от клиента'
                  else 'Сообщение от исполнителя' end,
      v_preview
    );
  end if;

  return v_id;
end;
$$;

grant execute on function public.order_chat_send(uuid, text) to authenticated;

-- ============================================================
-- Оқылды деп белгілеу (тек тараптар — модератор оқығаны есепке алынбайды)
-- ============================================================
create or replace function public.order_chat_mark_read(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.is_order_party(p_order) then return; end if;
  update public.order_messages
     set read_at = now()
   where order_id = p_order
     and sender_id <> v_uid
     and read_at is null;
end;
$$;

grant execute on function public.order_chat_mark_read(uuid) to authenticated;

-- ============================================================
-- Модератор: соңғы чаттар тізімі (белгіленгендері бірінші сүзгімен)
-- ============================================================
create or replace function public.mod_order_chats(
  p_limit int default 60,
  p_flagged_only boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  return coalesce((
    select jsonb_agg(x order by x.last_at desc)
      from (
        select m.order_id,
               max(m.created_at) as last_at,
               count(*) as total,
               count(*) filter (where m.flagged) as flagged,
               (array_agg(m.body order by m.created_at desc))[1] as last_body,
               o.status::text as status,
               o.from_address, o.to_address,
               pc.full_name as client_name,
               pe.full_name as executor_name
          from public.order_messages m
          join public.orders o on o.id = m.order_id
          left join public.profiles pc on pc.id = o.client_id
          left join public.profiles pe on pe.id = o.executor_id
         group by m.order_id, o.status, o.from_address, o.to_address,
                  pc.full_name, pe.full_name
        having (not coalesce(p_flagged_only, false))
            or count(*) filter (where m.flagged) > 0
         order by max(m.created_at) desc
         limit greatest(1, least(coalesce(p_limit, 60), 200))
      ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.mod_order_chats(int, boolean) to authenticated;


-- ################################################################
-- ### 0079_favorites_blocks.sql
-- ################################################################
-- ============================================================
-- Tasu · 0079_favorites_blocks.sql
-- ============================================================
-- ТАҢДАУЛЫ ОРЫНДАУШЫЛАР ❤ және «МАҒАН КӨРСЕТПЕУ».
--
--   * Клиент жақсы жұмыс істеген орындаушыны ТАҢДАУЛЫ деп белгілейді.
--     Сол клиент жаңа заказ бергенде таңдаулы орындаушыға (заказ оған сай
--     болса) АРНАЙЫ push кетеді: «Сізді таңдаулы деп белгілеген клиенттен
--     жаңа заказ» — ол бәрінен бұрын көңіл бөледі. Ұсыныстар тізімінде
--     таңдаулылар бірінші тұрады.
--   * Клиент жаман тәжірибеден кейін орындаушыны БҰҒАТТАЙДЫ — сол
--     орындаушы бұл клиенттің заказдарын лентада көрмейді, ұсыныс бере
--     алмайды, push алмайды (`exec_can_see` арқылы — ол лентаға да,
--     `exec_can_take`/`place_offer`-ге де, push-қа да ортақ тексеріс).
--   * Екеуі бір-бірін жоққа шығарады: бұғаттаса — таңдаулыдан шығады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0078-дан кейін).
-- ============================================================

create table if not exists public.client_favorites (
  client_id   uuid not null references public.profiles(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (client_id, executor_id)
);

create table if not exists public.client_blocks (
  client_id   uuid not null references public.profiles(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (client_id, executor_id)
);

create index if not exists idx_client_favorites_exec
  on public.client_favorites (executor_id);
create index if not exists idx_client_blocks_exec
  on public.client_blocks (executor_id);

alter table public.client_favorites enable row level security;
alter table public.client_blocks enable row level security;

-- Клиент тек ӨЗ тізімін оқиды; өзгерту — RPC арқылы.
drop policy if exists client_favorites_read on public.client_favorites;
create policy client_favorites_read on public.client_favorites
  for select to authenticated using (client_id = auth.uid());

drop policy if exists client_blocks_read on public.client_blocks;
create policy client_blocks_read on public.client_blocks
  for select to authenticated using (client_id = auth.uid());

-- ============================================================
-- Белгілеу: 'favorite' | 'block' | 'none'
-- ============================================================
create or replace function public.set_executor_pref(p_executor uuid, p_kind text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_executor is null or p_executor = v_uid then raise exception 'BAD_INPUT'; end if;
  if p_kind not in ('favorite', 'block', 'none') then raise exception 'BAD_INPUT'; end if;

  -- Тек бірге жұмыс істеген (кемінде бір заказда кездескен) орындаушыны
  -- белгілеуге болады — бөтен адамдарды тізімге жинау мүмкін емес.
  if p_kind <> 'none' and not exists (
    select 1 from public.orders o
     where o.client_id = v_uid and o.executor_id = p_executor
  ) and not exists (
    select 1 from public.offers f
      join public.orders o on o.id = f.order_id
     where o.client_id = v_uid and f.executor_id = p_executor
  ) then
    raise exception 'FORBIDDEN';
  end if;

  delete from public.client_favorites where client_id = v_uid and executor_id = p_executor;
  delete from public.client_blocks where client_id = v_uid and executor_id = p_executor;

  if p_kind = 'favorite' then
    insert into public.client_favorites (client_id, executor_id) values (v_uid, p_executor);
  elsif p_kind = 'block' then
    insert into public.client_blocks (client_id, executor_id) values (v_uid, p_executor);
  end if;
end;
$$;

grant execute on function public.set_executor_pref(uuid, text) to authenticated;

-- Бұғат тексерісі — SECURITY DEFINER (exec_can_see орындаушы атынан
-- шақырылуы мүмкін, ал ол клиенттің бұғат тізімін RLS бойынша оқи алмайды).
create or replace function public.is_blocked_by_client(p_client uuid, p_exec uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.client_blocks b
     where b.client_id = p_client and b.executor_id = p_exec
  );
$$;

-- ============================================================
-- exec_can_see v3 — 0063 нұсқасы + клиенттің бұғаты
-- ============================================================
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
  -- Алдын ала тапсырыс (0060): уақыты жетпеген заказ лентада көрінбейді.
  if o.scheduled_at is not null and o.scheduled_at > now() then return false; end if;

  -- БЕЛСЕНДІ РӨЛ орындаушы болуы шарт (0046/0063).
  if not exists (select 1 from public.profiles
                  where id = p_exec and role = 'executor') then
    return false;
  end if;

  if o.client_id = p_exec then return false; end if;

  -- Клиент бұл орындаушыны бұғаттаған (0079) — заказ оған мүлдем көрінбейді.
  if public.is_blocked_by_client(o.client_id, p_exec) then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;

  -- ТАНЫСУ РЕЖИМІ (0063): өтінім әлі толтырылмаған — сүзгі жоқ.
  if not found then return true; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  -- ҚАЛА СҮЗГІСІ (0053): жергілікті заказ тек сол қаладағы орындаушыға.
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
-- Жаңа заказ push-ы v2 — 0071 нұсқасы + таңдаулыларға бөлек мәтін
-- ============================================================
create or replace function public.notify_executors_new_order()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fav   uuid[];
  v_ready uuid[];
  v_idle  uuid[];
begin
  if new.status <> 'searching' then return new; end if;

  -- 1) Осы клиенттің ТАҢДАУЛЫ орындаушылары (заказ оларға сай болса).
  select array_agg(f.executor_id) into v_fav
    from public.client_favorites f
    join public.executor_profiles ep on ep.user_id = f.executor_id
   where f.client_id = new.client_id
     and ep.status = 'approved'
     and ep.order_push_enabled = true
     and public.exec_can_see(f.executor_id, new.id);

  -- 2) Қалғандары — 0071-дегідей (таңдаулыларға екінші push кетпейді).
  select
    array_agg(ep.user_id) filter (where public.exec_can_take(ep.user_id, new.id)),
    array_agg(ep.user_id) filter (where not public.exec_can_take(ep.user_id, new.id))
  into v_ready, v_idle
  from public.executor_profiles ep
  where ep.status = 'approved'
    and ep.order_push_enabled = true
    and ep.user_id <> new.client_id
    and not (ep.user_id = any(coalesce(v_fav, '{}'::uuid[])))
    and public.exec_can_see(ep.user_id, new.id);

  if coalesce(array_length(v_fav, 1), 0) > 0 then
    perform public.send_push(
      'Таңдаулы клиентіңізден заказ ❤',
      'Сізді таңдаулы деп белгілеген клиент жаңа заказ берді — қараңыз.',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_fav,
      'Заказ от клиента, где вы в избранном ❤',
      'Клиент, отметивший вас избранным, создал новый заказ — посмотрите.'
    );
  end if;

  if coalesce(array_length(v_ready, 1), 0) > 0 then
    perform public.send_push(
      'Жаңа заказ',
      'Сізге сай жаңа заказ шықты — тезірек қараңыз.',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_ready,
      'Новый заказ',
      'Появился подходящий заказ — посмотрите скорее.'
    );
  end if;

  if coalesce(array_length(v_idle, 1), 0) > 0 then
    perform public.send_push(
      'Жаңа заказ',
      'Сізге сай жаңа заказ шықты. Алу үшін линияға шығыңыз (тариф).',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_idle,
      'Новый заказ',
      'Появился подходящий заказ. Чтобы взять его, выйдите на линию (тариф).'
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;


-- ################################################################
-- ### 0080_notifications_inbox.sql
-- ################################################################
-- ============================================================
-- Tasu · 0080_notifications_inbox.sql
-- ============================================================
-- ХАБАРЛАМАЛАР ОРТАЛЫҒЫ 🔔
--
-- Бұрын push келіп-кетті де, ізі қалмайтын: хабарландыруды байқамай
-- жіберген адам «маған не келді?» деп ешқайдан қарай алмайтын (әсіресе
-- push рұқсаты өшірулі не web-те). Енді `send_push` жіберген әр хабарлама
-- алушының `notifications` кестесіне де жазылады — қосымшада 🔔 белгісі
-- оқылмағандар санымен тұрады.
--
--   * Модераторларға «broadcast» (нақты алушысыз) хабарлар жазылмайды.
--   * Заказ чатының хабарлары (`order_chat`) жазылмайды — оның өз экраны бар.
--   * `send_push` қолтаңбасы ӨЗГЕРМЕЙДІ — оны шақыратын барлық триггер
--     бұрынғыдай жұмыс істейді.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0079-ден кейін).
-- ============================================================

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text not null,
  body       text not null default '',
  title_ru   text,
  body_ru    text,
  data       jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists notifications_own_read on public.notifications;
create policy notifications_own_read on public.notifications
  for select to authenticated using (user_id = auth.uid());

-- ============================================================
-- send_push v2 — 0045 нұсқасы + хабарламалар орталығына жазу
-- ============================================================
create or replace function public.send_push(
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_target_user_ids uuid[] default null,
  p_title_ru text default null,
  p_body_ru text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
begin
  -- 1) Хабарламалар орталығы. Сәтсіз болса да push кете береді.
  if p_target_user_ids is not null
     and coalesce(p_data->>'type', '') <> 'order_chat' then
    begin
      insert into public.notifications (user_id, title, body, title_ru, body_ru, data)
      select distinct u, p_title, coalesce(p_body, ''), p_title_ru, p_body_ru,
             coalesce(p_data, '{}'::jsonb)
        from unnest(p_target_user_ids) as u
       where u is not null
         and exists (select 1 from public.profiles p where p.id = u);
    exception when others then
      null;
    end;
  end if;

  -- 2) Push (0045-тегідей).
  select value into v_secret from public.app_secrets where key = 'push_trigger_secret';
  if v_secret is null or v_secret = '' then
    return;
  end if;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/push-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'title', p_title,
      'body', p_body,
      'title_ru', coalesce(p_title_ru, p_title),
      'body_ru', coalesce(p_body_ru, p_body),
      'data', coalesce(p_data, '{}'::jsonb),
      'target_user_ids', to_jsonb(p_target_user_ids)
    )
  );
exception when others then
  null;
end;
$$;

-- ============================================================
-- Барлығын оқылды деп белгілеу / ескілерін тазалау
-- ============================================================
create or replace function public.notifications_mark_all_read()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and read_at is null;
end;
$$;

grant execute on function public.notifications_mark_all_read() to authenticated;

-- 60 күннен ескі хабарламалар — апта сайын тазаланады (pg_cron бар болса).
do $$ begin
  perform cron.unschedule('notifications_cleanup');
exception when others then null; end $$;

do $$ begin
  perform cron.schedule(
    'notifications_cleanup',
    '17 3 * * 1',
    $cron$delete from public.notifications where created_at < now() - interval '60 days'$cron$
  );
exception when others then null; end $$;


-- ################################################################
-- ### 0081_review_tags.sql
-- ################################################################
-- ============================================================
-- Tasu · 0081_review_tags.sql
-- ============================================================
-- БАҒАЛАУ ТЕГТЕРІ: жұлдыздан бөлек «не ұнады / не ұнамады».
--
-- Бұрын бағалау тек 1–5 жұлдыз + еркін мәтін еді: «4 жұлдыз» — неге 4?
-- Енді бір басумен нақты тег: «Уақтылы», «Жүкке ұқыпты», «Сыпайы» /
-- «Кешікті», «Жүкті бүлдірді»… Профильде олардың жиынтығы көрінеді
-- («Уақтылы ×12») — келесі клиент таңдағанда пайдалы.
--
-- Тегтер ТҰРАҚТЫ КОДПЕН сақталады (аудармасы қосымшада), рұқсат етілген
-- тізімнен тыс код елеусіз қалады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0080-ден кейін).
-- ============================================================

alter table public.reviews add column if not exists tags text[] not null default '{}';

drop function if exists public.submit_review(uuid, int, text);

create or replace function public.submit_review(
  p_order uuid,
  p_rating int,
  p_comment text default '',
  p_tags text[] default '{}')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role public.user_role;
  v_target uuid;
  v_tags text[];
  c_allowed constant text[] := array[
    -- оң
    'punctual', 'careful', 'polite', 'helpful', 'clean_car', 'clear_info',
    'ready_on_time',
    -- теріс
    'late', 'rude', 'damaged', 'overpriced', 'long_wait', 'wrong_info'
  ];
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'BAD_RATING'; end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status <> 'completed' then raise exception 'NOT_COMPLETED'; end if;
  if o.executor_id is null then raise exception 'NOT_FOUND'; end if;

  if v_uid = o.client_id then
    v_role := 'client'; v_target := o.executor_id;
  elsif v_uid = o.executor_id then
    v_role := 'executor'; v_target := o.client_id;
  else
    raise exception 'FORBIDDEN';
  end if;

  if exists (select 1 from public.reviews where order_id = p_order and author_role = v_role) then
    raise exception 'ALREADY_REVIEWED';
  end if;

  select coalesce(array_agg(distinct t), '{}') into v_tags
    from unnest(coalesce(p_tags, '{}')) as t
   where t = any (c_allowed);

  insert into public.reviews
    (order_id, client_id, executor_id, author_role, author_id, target_id,
     rating, comment, tags)
  values
    (p_order, o.client_id, o.executor_id, v_role, v_uid, v_target,
     p_rating, coalesce(trim(p_comment),''), v_tags[1:6]);

  perform public.recompute_rating(v_target);
end;
$$;

grant execute on function public.submit_review(uuid, int, text, text[]) to authenticated;

-- ============================================================
-- Адамның алған тегтерінің жиынтығы (профиль, ұсыныс карточкасы)
-- ============================================================
-- p_role — адамның БАҒАЛАНҒАН рөлі: 'executor' (клиенттер берген тегтер)
-- не 'client' (орындаушылар берген тегтер).
create or replace function public.user_review_tags(p_user uuid, p_role text default 'executor')
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(tag, cnt), '{}'::jsonb)
    from (
      select t as tag, count(*) as cnt
        from public.reviews r, unnest(r.tags) as t
       where r.target_id = p_user
         and r.author_role::text = case when p_role = 'client'
                                        then 'executor' else 'client' end
       group by t
    ) s;
$$;

grant execute on function public.user_review_tags(uuid, text) to anon, authenticated;


-- ################################################################
-- ### 0082_moderator_tools.sql
-- ################################################################
-- ============================================================
-- Tasu · 0082_moderator_tools.sql
-- ============================================================
-- МОДЕРАТОР ҚҰРАЛДАРЫ:
--   1) mod_dashboard_series — Шолудағы графиктер: күн сайынғы заказдар
--      (берілді / аяқталды / тоқтады), айналым (GMV), тариф сатылымы
--      (платформаның түсімі), расталған толтырулар, жаңа тіркелулер.
--   2) mod_broadcast — ЖАППАЙ ХАБАРЛАМА: барлық орындаушыға / клиентке
--      (орындаушыларға — қала мен көлік түрі бойынша сүзгімен). Push +
--      хабарламалар орталығы (0080).
--   3) mod_audit_log — ӘРЕКЕТТЕР ЖУРНАЛЫ: кім, қашан, не істеді (растау,
--      бұғаттау, баланс түзету, толтыру, статус, баптау). RPC-лерге ТИІСПЕЙМІЗ —
--      журналды кестелердегі ТРИГГЕРЛЕР толтырады, тек өзгерісті модератор
--      жасаса ғана.
--   4) mod_update_setting — жаңа баптаулар кілттері: order_chat, nearby_map.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0081-дан кейін).
-- ============================================================

-- ============================================================
-- 1) Графиктерге арналған күндік қатар
-- ============================================================
create or replace function public.mod_dashboard_series(p_days int default 14)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_days  int := greatest(1, least(coalesce(p_days, 14), 90));
  v_today date := (now() at time zone 'Asia/Almaty')::date;
  v_from  timestamptz;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  v_from := (v_today - (v_days - 1))::timestamp at time zone 'Asia/Almaty';

  return coalesce((
    with days as (
      select (v_today - g)::date as d
        from generate_series(0, v_days - 1) as g
    ),
    o as (
      select (created_at at time zone 'Asia/Almaty')::date as d,
             count(*) as created,
             count(*) filter (where status = 'completed') as completed,
             count(*) filter (where status in ('cancelled', 'expired')) as cancelled,
             coalesce(sum(coalesce(final_price, client_price))
                        filter (where status = 'completed'), 0) as gmv
        from public.orders
       where created_at >= v_from
       group by 1
    ),
    t as (
      select (started_at at time zone 'Asia/Almaty')::date as d,
             coalesce(sum(fee), 0) as tariffs,
             count(*) as tariff_count
        from public.tariff_sessions
       where started_at >= v_from
       group by 1
    ),
    tp as (
      select (coalesce(reviewed_at, created_at) at time zone 'Asia/Almaty')::date as d,
             coalesce(sum(amount), 0) as topups
        from public.topup_requests
       where status = 'approved'
         and coalesce(reviewed_at, created_at) >= v_from
       group by 1
    ),
    u as (
      select (created_at at time zone 'Asia/Almaty')::date as d,
             count(*) filter (where role = 'client') as new_clients,
             count(*) filter (where role = 'executor' or has_executor_role) as new_executors
        from public.profiles
       where created_at >= v_from
       group by 1
    )
    select jsonb_agg(
             jsonb_build_object(
               'day', days.d,
               'created', coalesce(o.created, 0),
               'completed', coalesce(o.completed, 0),
               'cancelled', coalesce(o.cancelled, 0),
               'gmv', coalesce(o.gmv, 0),
               'tariffs', coalesce(t.tariffs, 0),
               'tariff_count', coalesce(t.tariff_count, 0),
               'topups', coalesce(tp.topups, 0),
               'new_clients', coalesce(u.new_clients, 0),
               'new_executors', coalesce(u.new_executors, 0)
             )
             order by days.d
           )
      from days
      left join o on o.d = days.d
      left join t on t.d = days.d
      left join tp on tp.d = days.d
      left join u on u.d = days.d
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.mod_dashboard_series(int) to authenticated;

-- ============================================================
-- 2) Әрекеттер журналы
-- ============================================================
create table if not exists public.mod_audit_log (
  id           bigserial primary key,
  moderator_id uuid references public.profiles(id) on delete set null,
  action       text not null,
  target_type  text not null,
  target_id    text,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

create index if not exists idx_mod_audit_created on public.mod_audit_log (created_at desc);
create index if not exists idx_mod_audit_target on public.mod_audit_log (target_id);

alter table public.mod_audit_log enable row level security;

drop policy if exists mod_audit_read on public.mod_audit_log;
create policy mod_audit_read on public.mod_audit_log
  for select to authenticated using (public.is_moderator());

-- Журналға жазу — ТЕК өзгерісті модератор жасаса (клиенттің/орындаушының
-- өз әрекеті, cron, бот — жазылмайды). Қате болса өзгерістің өзін
-- тоқтатпайды.
create or replace function public.mod_audit(
  p_action text,
  p_target_type text,
  p_target_id text,
  p_details jsonb default '{}'::jsonb)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then return; end if;
  insert into public.mod_audit_log (moderator_id, action, target_type, target_id, details)
  values (auth.uid(), p_action, p_target_type, p_target_id,
          coalesce(p_details, '{}'::jsonb));
exception when others then
  null;
end;
$$;

-- --- орындаушы мәртебесі мен құжат сұранымы ---
create or replace function public.audit_executor_profiles()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    perform public.mod_audit('executor_status', 'executor', new.user_id::text,
      jsonb_build_object('from', old.status, 'to', new.status,
                         'comment', new.moderation_comment));
  end if;
  if new.docs_update_requested and not coalesce(old.docs_update_requested, false) then
    perform public.mod_audit('docs_requested', 'executor', new.user_id::text,
      jsonb_build_object('fields', to_jsonb(new.docs_update_fields),
                         'comment', new.docs_update_comment));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_executor_profiles on public.executor_profiles;
create trigger trg_audit_executor_profiles
  after update on public.executor_profiles
  for each row execute function public.audit_executor_profiles();

-- --- толтыру шешімі ---
create or replace function public.audit_topups()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    perform public.mod_audit('topup_' || new.status::text, 'executor',
      new.executor_id::text,
      jsonb_build_object('topup_id', new.id, 'amount', new.amount, 'note', new.note));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_topups on public.topup_requests;
create trigger trg_audit_topups
  after update on public.topup_requests
  for each row execute function public.audit_topups();

-- --- аккаунт бұғаты мен сенім деңгейі ---
create or replace function public.audit_profiles()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.blocked_at is distinct from old.blocked_at then
    perform public.mod_audit(
      case when new.blocked_at is null then 'account_unblock' else 'account_block' end,
      'user', new.id::text,
      jsonb_build_object('reason', new.block_reason));
  end if;
  if new.trust_score is distinct from old.trust_score then
    perform public.mod_audit('trust_score', 'user', new.id::text,
      jsonb_build_object('from', old.trust_score, 'to', new.trust_score));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_profiles on public.profiles;
create trigger trg_audit_profiles
  after update on public.profiles
  for each row execute function public.audit_profiles();

-- --- балансты қолмен түзету ---
create or replace function public.audit_balance_txns()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.type = 'adjustment' then
    perform public.mod_audit('balance_adjust', 'executor', new.executor_id::text,
      jsonb_build_object('amount', new.amount, 'note', new.note));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_balance_txns on public.balance_txns;
create trigger trg_audit_balance_txns
  after insert on public.balance_txns
  for each row execute function public.audit_balance_txns();

-- --- заказ статусын модератор өзгертсе ---
create or replace function public.audit_orders()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    perform public.mod_audit('order_status', 'order', new.id::text,
      jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_orders on public.orders;
create trigger trg_audit_orders
  after update of status on public.orders
  for each row execute function public.audit_orders();

-- --- баптаулар ---
create or replace function public.audit_settings()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public.mod_audit('setting_change', 'setting', new.key,
    jsonb_build_object('value', new.value));
  return new;
end;
$$;

drop trigger if exists trg_audit_settings on public.app_settings;
create trigger trg_audit_settings
  after insert or update on public.app_settings
  for each row execute function public.audit_settings();

-- ============================================================
-- 3) Жаппай хабарлама
-- ============================================================
-- p_audience: 'executors' | 'clients' | 'all'. Қала мен көлік түрі —
-- тек орындаушыларға (клиенттің тұрақты қаласы сақталмайды).
-- 500-ден бөліп жібереміз (push-notify функциясына бір сұраныста тым
-- үлкен тізім жібермеу үшін). Қайтарады: алушылар саны.
create or replace function public.mod_broadcast(
  p_audience text,
  p_title text,
  p_body text,
  p_city text default null,
  p_vehicle text default null)
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
  v_n int;
  v_i int := 1;
  v_city text := public.norm_city(p_city);
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(trim(p_title), '') = '' or coalesce(trim(p_body), '') = '' then
    raise exception 'EMPTY';
  end if;
  if p_audience not in ('executors', 'clients', 'all') then
    raise exception 'BAD_INPUT';
  end if;

  select array_agg(distinct p.id) into v_ids
    from public.profiles p
    left join public.executor_profiles ep on ep.user_id = p.id
   where p.role <> 'moderator'
     and p.blocked_at is null
     and (
       (p_audience in ('executors', 'all')
          and ep.user_id is not null
          and ep.status = 'approved'
          and (v_city is null or public.norm_city(ep.city) = v_city)
          and (p_vehicle is null or ep.vehicle_type::text = p_vehicle))
       or
       (p_audience in ('clients', 'all')
          and p.has_client_role
          and v_city is null and p_vehicle is null)
     );

  v_n := coalesce(array_length(v_ids, 1), 0);
  while v_i <= v_n loop
    perform public.send_push(
      trim(p_title),
      trim(p_body),
      jsonb_build_object('type', 'broadcast'),
      v_ids[v_i : least(v_i + 499, v_n)],
      trim(p_title),
      trim(p_body)
    );
    v_i := v_i + 500;
  end loop;

  perform public.mod_audit('broadcast', 'audience', p_audience,
    jsonb_build_object('title', p_title, 'body', p_body, 'city', p_city,
                       'vehicle', p_vehicle, 'recipients', v_n));
  return v_n;
end;
$$;

grant execute on function public.mod_broadcast(text, text, text, text, text) to authenticated;

-- ============================================================
-- 4) Баптаулардың рұқсат тізімі (0072 + жаңа кілттер)
-- ============================================================
create or replace function public.mod_update_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if p_key not in (
    'tariffs', 'payment', 'version_gate', 'order_min', 'vehicle_rules',
    'listings', 'taxi', 'topup_bot', 'support_bot', 'support', 'bonus',
    'repeat_order', 'pricing_hint', 'scheduled_orders', 'live_tracking',
    'share_trip', 'referral', 'news', 'support_contact',
    'order_chat', 'nearby_map'
  ) then
    raise exception 'BAD_KEY';
  end if;
  -- WhatsApp нөмірі: тек цифрлар, елдік кодпен (7XXXXXXXXXX).
  if p_key = 'support_contact'
     and coalesce(p_value->>'whatsapp', '') !~ '^[0-9]{10,15}$' then
    raise exception 'BAD_PHONE';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

insert into public.app_settings (key, value)
values ('nearby_map', jsonb_build_object('enabled', true))
on conflict (key) do nothing;


-- ################################################################
-- ### 0083_mod_live_map.sql
-- ################################################################
-- ============================================================
-- Tasu · 0083_mod_live_map.sql
-- ============================================================
-- МОДЕРАТОРДЫҢ ТІРІ КАРТАСЫ: сұраныс пен ұсыныс бір картада.
--
--   * орындаушылар — соңғы 30 минутта орнын жібергендер (0075: белсенді
--     заказда 15с сайын, бос әрі линияда болса минутына бір рет): көлік
--     түрі, бос / заказда / үзілісте, аты-жөні мен телефоны;
--   * заказдар — іздеудегі және орындалып жатқан (соңғы 3 күн) заказдардың
--     алу нүктелері.
--
-- Модератор «Алматыда заказ көп, бос көлік аз» дегенді бір қарағанда
-- көреді, қажет болса орындаушыға қоңырау шалады не жаппай хабарлама
-- жібереді.
--
-- executor_locations-қа тікелей SELECT саясаты ӘДЕЙІ жоқ (0060) — модератор
-- да тек осы SECURITY DEFINER функциясы арқылы оқиды.
--
-- 0075-тен КЕЙІН қолданылады (heading бағаны керек). Идемпотентті.
-- ============================================================

create or replace function public.mod_live_map()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  return jsonb_build_object(
    'executors', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', l.executor_id,
               'lat', l.lat,
               'lng', l.lng,
               'heading', l.heading,
               'updated_at', l.updated_at,
               'order_id', l.order_id,
               'vehicle_type', ep.vehicle_type::text,
               'name', p.full_name,
               'phone', p.phone,
               'busy', ep.busy_order_id is not null or l.order_id is not null,
               'on_line', coalesce(ep.on_line, true)
             ))
        from public.executor_locations l
        join public.executor_profiles ep on ep.user_id = l.executor_id
        join public.profiles p on p.id = l.executor_id
       where l.updated_at > now() - interval '30 minutes'
         and ep.status = 'approved'
    ), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', o.id,
               'lat', o.from_lat,
               'lng', o.from_lng,
               'status', o.status::text,
               'vehicle_type', o.vehicle_type::text,
               'price', coalesce(o.final_price, o.client_price),
               'created_at', o.created_at,
               'from_city', o.from_city
             ))
        from public.orders o
       where o.status in ('searching', 'accepted', 'arrived', 'loading', 'in_transit')
         and o.created_at > now() - interval '3 days'
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.mod_live_map() to authenticated;

