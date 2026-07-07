-- GazelGo · 0001_init.sql
-- Schema: enums, tables, indexes, helper functions, auth trigger, column guards.
-- Time zone of business logic: Asia/Almaty. Money unit: KZT (bigint, tenge).

create extension if not exists pgcrypto;

-- ---------- enums ----------
do $$ begin
  create type public.user_role as enum ('client','executor','moderator');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.vehicle_size as enum ('small','medium','large');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.executor_status as enum ('pending','approved','rejected','blocked');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_type as enum ('bidding','instant');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_status as enum
    ('searching','accepted','arrived','loading','in_transit','completed','cancelled','expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.offer_status as enum ('pending','accepted','rejected','withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tariff_kind as enum ('simple','vip');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.txn_type as enum ('topup','tariff_fee','refund','adjustment');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.topup_status as enum ('pending','approved','rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.dispatch_status as enum ('pending','accepted','declined','expired');
exception when duplicate_object then null; end $$;

-- ---------- tables ----------

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         public.user_role not null default 'client',
  full_name    text not null default '',
  phone        text not null default '',
  avatar_url   text,
  rating       numeric(3,2) not null default 0,
  rating_count integer not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists public.executor_profiles (
  user_id            uuid primary key references public.profiles(id) on delete cascade,
  status             public.executor_status not null default 'pending',
  vehicle_size       public.vehicle_size not null,
  vehicle_brand      text not null default '',
  vehicle_model      text not null default '',
  vehicle_year       integer,
  vehicle_plate      text not null default '',
  vehicle_photos     text[] not null default '{}',      -- storage paths in bucket "docs"
  id_doc_path        text,                              -- жеке куәлік
  license_path       text,                              -- жүргізуші куәлігі
  tech_passport_path text,                              -- техпаспорт
  moderation_comment text,
  moderated_by       uuid references public.profiles(id),
  moderated_at       timestamptz,
  balance            bigint not null default 0,          -- KZT
  total_earned       bigint not null default 0,          -- KZT (статистика)
  busy_order_id      uuid,                                -- активті заказ
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists public.tariff_sessions (
  id          uuid primary key default gen_random_uuid(),
  executor_id uuid not null references public.profiles(id) on delete cascade,
  kind        public.tariff_kind not null,
  fee         bigint not null,
  is_night    boolean not null default false,
  started_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index if not exists idx_sessions_active
  on public.tariff_sessions (executor_id, kind, expires_at desc);

create table if not exists public.balance_txns (
  id          uuid primary key default gen_random_uuid(),
  executor_id uuid not null references public.profiles(id) on delete cascade,
  amount      bigint not null,               -- + толтыру / - шегерім
  type        public.txn_type not null,
  note        text not null default '',
  ref_id      uuid,
  created_at  timestamptz not null default now()
);
create index if not exists idx_txns_executor
  on public.balance_txns (executor_id, created_at desc);

create table if not exists public.topup_requests (
  id           uuid primary key default gen_random_uuid(),
  executor_id  uuid not null references public.profiles(id) on delete cascade,
  amount       bigint not null check (amount > 0),
  receipt_path text,                          -- каспи чек (bucket "docs")
  status       public.topup_status not null default 'pending',
  note         text,
  reviewed_by  uuid references public.profiles(id),
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists idx_topups_status
  on public.topup_requests (status, created_at desc);

create table if not exists public.orders (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.profiles(id) on delete cascade,
  type          public.order_type not null,
  status        public.order_status not null default 'searching',
  from_address  text not null,
  from_lat      double precision not null,
  from_lng      double precision not null,
  to_address    text not null,
  to_lat        double precision not null,
  to_lng        double precision not null,
  distance_km   numeric(8,2) not null default 0,
  cargo_desc    text not null,
  comment       text not null default '',
  size          public.vehicle_size not null,
  client_price  bigint,          -- bidding: клиент ұсынған баға
  system_price  bigint,          -- instant: платформа бағасы
  final_price   bigint,          -- келісілген қорытынды баға
  executor_id   uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  accepted_at   timestamptz,
  completed_at  timestamptz,
  cancelled_by  uuid,
  cancel_reason text
);
create index if not exists idx_orders_feed on public.orders (status, type, size);
create index if not exists idx_orders_client on public.orders (client_id, created_at desc);
create index if not exists idx_orders_executor on public.orders (executor_id, created_at desc);

alter table public.executor_profiles
  drop constraint if exists fk_busy_order;
alter table public.executor_profiles
  add constraint fk_busy_order foreign key (busy_order_id)
  references public.orders(id) on delete set null;

create table if not exists public.offers (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  price       bigint not null check (price > 0),
  message     text not null default '',
  status      public.offer_status not null default 'pending',
  created_at  timestamptz not null default now(),
  unique (order_id, executor_id)
);
create index if not exists idx_offers_order on public.offers (order_id, status);
create index if not exists idx_offers_executor on public.offers (executor_id, created_at desc);

create table if not exists public.vip_dispatches (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  status      public.dispatch_status not null default 'pending',
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_dispatch_executor on public.vip_dispatches (executor_id, status);
create index if not exists idx_dispatch_order on public.vip_dispatches (order_id, created_at desc);

create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null unique references public.orders(id) on delete cascade,
  client_id   uuid not null references public.profiles(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  rating      integer not null check (rating between 1 and 5),
  comment     text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists idx_reviews_executor on public.reviews (executor_id, created_at desc);

create table if not exists public.earnings (
  id          uuid primary key default gen_random_uuid(),
  executor_id uuid not null references public.profiles(id) on delete cascade,
  order_id    uuid not null unique references public.orders(id) on delete cascade,
  amount      bigint not null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_earnings_executor on public.earnings (executor_id, created_at desc);

create table if not exists public.app_settings (
  key   text primary key,
  value jsonb not null
);

-- ---------- helper functions ----------

create or replace function public.is_moderator()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'moderator'
  );
$$;

-- Түнгі уақыт па? (Asia/Almaty, 20:00–08:00)
create or replace function public.is_night_now()
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select extract(hour from (now() at time zone 'Asia/Almaty'))::int >= 20
      or extract(hour from (now() at time zone 'Asia/Almaty'))::int < 8;
$$;

-- Ағымдағы смена терезесінің аяқталу уақыты (UTC timestamptz)
create or replace function public.current_window_end()
returns timestamptz
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  loc timestamp := now() at time zone 'Asia/Almaty';
  h int := extract(hour from loc)::int;
  d date := loc::date;
  end_loc timestamp;
begin
  if h >= 8 and h < 20 then
    end_loc := d + time '20:00';
  elsif h >= 20 then
    end_loc := (d + 1) + time '08:00';
  else
    end_loc := d + time '08:00';
  end if;
  return end_loc at time zone 'Asia/Almaty';
end;
$$;

-- Тарифтің қазіргі бағасы (түнде 50% жеңілдік — app_settings арқылы)
create or replace function public.tariff_price_now(p_kind text)
returns bigint
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  cfg jsonb;
  base bigint;
  disc numeric;
begin
  select value into cfg from public.app_settings where key = 'tariffs';
  if cfg is null then
    raise exception 'SETTINGS_MISSING';
  end if;
  if p_kind = 'simple' then
    base := (cfg->>'simple_day')::bigint;
  elsif p_kind = 'vip' then
    base := (cfg->>'vip_day')::bigint;
  else
    raise exception 'BAD_TARIFF';
  end if;
  disc := coalesce((cfg->>'night_discount')::numeric, 0.5);
  if public.is_night_now() then
    return round(base * (1 - disc));
  end if;
  return base;
end;
$$;

-- Жедел (instant) заказдың бағасын есептеу
create or replace function public.instant_quote(p_size text, p_distance_km numeric)
returns bigint
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  cfg jsonb;
  s jsonb;
  price numeric;
begin
  select value into cfg from public.app_settings where key = 'instant_pricing';
  if cfg is null then
    raise exception 'SETTINGS_MISSING';
  end if;
  s := cfg->p_size;
  if s is null then
    raise exception 'BAD_SIZE';
  end if;
  price := (s->>'base')::numeric + (s->>'per_km')::numeric * greatest(p_distance_km, 0);
  price := greatest(price, (s->>'min')::numeric);
  return (round(price / 100) * 100)::bigint;  -- 100 теңгеге дейін дөңгелектеу
end;
$$;

-- ---------- auth trigger: жаңа қолданушыға профиль ----------

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_role public.user_role := 'client';
begin
  if new.raw_user_meta_data->>'role' = 'executor' then
    v_role := 'executor';
  end if;
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    v_role,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- column guards (клиенттік тікелей UPDATE-тен қорғау) ----------
-- security definer RPC-лар postgres ретінде жүреді — оларға рұқсат.

create or replace function public.guard_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    return new;
  end if;
  if new.role is distinct from old.role
     or new.rating is distinct from old.rating
     or new.rating_count is distinct from old.rating_count then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_profiles on public.profiles;
create trigger trg_guard_profiles
  before update on public.profiles
  for each row execute function public.guard_profiles();

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
     or new.moderation_comment is distinct from old.moderation_comment then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  -- орындаушы статусты тек rejected -> pending бағытында өзгерте алады (қайта өтінім)
  if new.status is distinct from old.status
     and not (old.status = 'rejected' and new.status = 'pending') then
    raise exception 'FORBIDDEN_STATUS';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_guard_executor_profiles on public.executor_profiles;
create trigger trg_guard_executor_profiles
  before update on public.executor_profiles
  for each row execute function public.guard_executor_profiles();
