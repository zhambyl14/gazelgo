-- Tasu · 0043_listings_board.sql
-- «Хабарландырулар тақтасы» — қосымшадағы жаңа бөлім (логотип → sidebar →
-- «Хабарландырулар»). Екі бағыт бар, рөл бойынша автоматты анықталады:
--
--   kind = 'service'  — ОРЫНДАУШЫ жариялайды («Менің қызметтерім»).
--                       Клиент оны «Қызметтер» табынан көреді.
--   kind = 'job'      — КЛИЕНТ жариялайды («Менің жұмыстарым»).
--                       Орындаушы оны «Жұмыстар» табынан көреді.
--
-- Яғни әркім өз рөліне сай ЖАРИЯЛАЙДЫ, ал ҚАРСЫ рөлдің хабарландыруларын
-- КӨРЕДІ. Көру саны (views) тек хабарландыру АВТОРЫНА көрсетіледі.
--
-- Өмір мерзімі: 7 күн (kListingDays). Мерзімі өткенде хабарландыру
-- «архивке» кетеді, ал Storage-тағы фотолары `storage_purge_queue`-ге
-- (0037) қосылып, күнделікті `cleanup-storage` cron арқылы ӨШІРІЛЕДІ —
-- сол себепті архивтен қайта жариялағанда фотоларды ҚАЙТА салу керек.
--
-- Бүкіл фича модератордың қолында: `app_settings.listings.enabled` = false
-- болса, клиент те, орындаушы да тақтаны аша алмайды («әлі қосылмады»).
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындаңыз
-- (0042-ден КЕЙІН).

-- ============================================================
-- 1) Модератордың қосқыш баптауы
-- ============================================================
-- Әдепкі — ӨШУЛІ: модератор дайын болғанда Баптаулар табынан қосады.
insert into public.app_settings (key, value)
values ('listings', jsonb_build_object('enabled', false))
on conflict (key) do nothing;

-- 0030-дағы функцияны кеңейтеміз — жаңа 'listings' кілті қосылды.
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
                   'vehicle_rules', 'listings') then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

-- Тақта қосулы ма — қосымша әр ашылғанда осыны сұрайды (жеңіл, құпиясыз).
create or replace function public.board_enabled()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select (value->>'enabled')::boolean from public.app_settings where key = 'listings'),
    false);
$$;

grant execute on function public.board_enabled() to anon, authenticated;

-- ============================================================
-- 2) Кестелер
-- ============================================================
create table if not exists public.listings (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references public.profiles(id) on delete cascade,
  author_role   text not null check (author_role in ('client', 'executor')),
  -- job = клиенттің жұмысы, service = орындаушының қызметі
  kind          text not null check (kind in ('job', 'service')),
  vehicle_type  text not null,
  city          text not null,
  body          text not null,
  price_text    text not null default '',
  -- 0 = көрсетілмеген; >0 болса «N күндік жұмыс» деген белгі (тек job)
  duration_days int  not null default 0,
  photos        text[] not null default '{}',
  views         int  not null default 0,
  status        text not null default 'active'
                  check (status in ('active', 'expired', 'archived')),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '7 days'),
  archived_at   timestamptz
);

create index if not exists idx_listings_feed
  on public.listings (kind, status, created_at desc);
create index if not exists idx_listings_author
  on public.listings (author_id, created_at desc);
create index if not exists idx_listings_expiry
  on public.listings (expires_at) where status = 'active';

-- Көру саны: бір адам бір хабарландыруды қанша ашса да — 1 рет саналады.
create table if not exists public.listing_views (
  listing_id uuid not null references public.listings(id) on delete cascade,
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (listing_id, viewer_id)
);

-- Екеуіне де RLS қосулы, САЯСАТ ӘДЕЙІ ЖОҚ: барлық қатынас төмендегі
-- security definer RPC-лер арқылы ғана (app_secrets/0025 тәртібіндей).
alter table public.listings enable row level security;
alter table public.listing_views enable row level security;

-- ============================================================
-- 3) Ішкі көмекшілер
-- ============================================================
-- Автордың көрінетін деректері (аты, аватар, рейтинг) — фидте қайталанады.
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
    'author_rating',  p.rating,
    'author_rating_count', p.rating_count,
    'author_trips',   p.trips
  )
  from public.profiles p where p.id = l.author_id;
$$;

-- Мерзімі өткен хабарландыруды архивке шығарып, фотоларын өшіру кезегіне
-- қосу. `create_listing`/`board_feed` шақырылған сайын да жүреді — cron
-- кешіксе де қолданушы ешқашан «өлі» хабарландыруды көрмейді.
create or replace function public.expire_listings()
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_count int := 0;
begin
  -- 1) фотоларды өшіру кезегіне (0037 storage_purge_queue) қосамыз
  insert into public.storage_purge_queue (bucket, path, purge_after)
  select 'listings', unnest(l.photos), now()
    from public.listings l
   where l.status = 'active' and l.expires_at <= now()
     and array_length(l.photos, 1) > 0;

  -- 2) хабарландырудың өзін архивке шығарамыз (мәтіні қалады — қайта
  --    жариялағанда толтырып беру үшін), фото жолдары тазаланады
  update public.listings
     set status = 'expired', photos = '{}', archived_at = now()
   where status = 'active' and expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ============================================================
-- 4) Оқу RPC-лері
-- ============================================================
-- Тақта лентасы: ҚАРСЫ рөлдің хабарландырулары.
--   клиент  → орындаушылардың қызметтері (service)
--   орындаушы → клиенттердің жұмыстары (job)
-- p_city = null/'' → барлық қала; p_vehicle = null/'all' → барлық түр.
create or replace function public.board_feed(
  p_city text default null,
  p_vehicle text default null
)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_role text;
  v_kind text;
  v_res  jsonb;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.board_enabled() then raise exception 'BOARD_OFF'; end if;

  -- role — enum (public.user_role), сол себепті text-ке АЙҚЫН түрлендіреміз.
  select role::text into v_role from public.profiles where id = v_uid;
  v_kind := case when v_role = 'executor' then 'job' else 'service' end;

  select coalesce(jsonb_agg(public.listing_json(l, false) order by l.created_at desc), '[]'::jsonb)
    into v_res
    from public.listings l
   where l.kind = v_kind
     and l.status = 'active'
     and l.expires_at > now()
     and l.author_id <> v_uid
     and (p_city is null or p_city = '' or l.city = p_city)
     and (p_vehicle is null or p_vehicle = '' or p_vehicle = 'all'
          or l.vehicle_type = p_vehicle);

  return v_res;
end;
$$;

-- Өз хабарландыруларым (барлық күйі: белсенді + архив), көру санымен.
create or replace function public.my_listings()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_res jsonb;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select coalesce(jsonb_agg(public.listing_json(l, true) order by l.created_at desc), '[]'::jsonb)
    into v_res
    from public.listings l
   where l.author_id = v_uid
     and l.status <> 'archived';

  return v_res;
end;
$$;

-- Хабарландыруды ашу: көруді тіркейді (өзінікі болмаса, бір рет санайды)
-- және байланыс телефонын қоса қайтарады.
create or replace function public.open_listing(p_id uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_row  public.listings;
  v_mine boolean;
  v_new  int := 0;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.board_enabled() then raise exception 'BOARD_OFF'; end if;

  select * into v_row from public.listings where id = p_id;
  if v_row.id is null then raise exception 'NOT_FOUND'; end if;

  v_mine := (v_row.author_id = v_uid);

  -- Көру санағышы: тек бөгде адам, тек белсенді хабарландыру, тек 1 рет.
  if not v_mine and v_row.status = 'active' then
    insert into public.listing_views (listing_id, viewer_id)
    values (p_id, v_uid)
    on conflict do nothing;
    get diagnostics v_new = row_count;
    if v_new > 0 then
      update public.listings set views = views + 1 where id = p_id;
      v_row.views := v_row.views + 1;
    end if;
  end if;

  return public.listing_json(v_row, v_mine)
         || jsonb_build_object(
              'author_phone',
              case when v_mine or v_row.status = 'active'
                   then (select phone from public.profiles where id = v_row.author_id)
                   else null end);
end;
$$;

-- ============================================================
-- 5) Жазу RPC-лері
-- ============================================================
-- Хабарландыру жариялау. Түрі (job/service) РӨЛДЕН автоматты анықталады —
-- клиент қызмет, орындаушы жұмыс жариялай алмайды.
create or replace function public.create_listing(
  p_vehicle_type text,
  p_city text,
  p_body text,
  p_price_text text default '',
  p_duration_days int default 0,
  p_photos text[] default '{}'
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_role   text;
  v_kind   text;
  v_blocked timestamptz;
  v_active int;
  v_id     uuid;
  v_photos text[] := coalesce(p_photos, '{}');
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.board_enabled() then raise exception 'BOARD_OFF'; end if;

  select role::text, blocked_at into v_role, v_blocked
    from public.profiles where id = v_uid;
  if v_blocked is not null then raise exception 'ACCOUNT_BLOCKED'; end if;
  if v_role not in ('client', 'executor') then raise exception 'FORBIDDEN'; end if;

  v_kind := case when v_role = 'executor' then 'service' else 'job' end;

  -- Орындаушы тек РАСТАЛҒАН соң қызмет жариялай алады (клиенттер расталмаған
  -- көлікке тапсырыс бермеуі керек).
  if v_role = 'executor' and not exists (
       select 1 from public.executor_profiles
        where user_id = v_uid and status = 'approved') then
    raise exception 'NOT_APPROVED';
  end if;

  if coalesce(length(btrim(p_body)), 0) < 10 then raise exception 'EMPTY'; end if;
  if coalesce(length(btrim(p_city)), 0) = 0 then raise exception 'BAD_INPUT'; end if;
  if coalesce(array_length(v_photos, 1), 0) > 4 then raise exception 'TOO_MANY_PHOTOS'; end if;
  if p_vehicle_type not in ('gazelle','furgon','minivan','kamaz','fura','manipulator',
                            'crane','loader','excavator','avtovyshka','tractor','assenizator')
  then raise exception 'BAD_VEHICLE_TYPE'; end if;

  -- Ескілерін алдымен архивке шығарамыз — лимит әділ саналуы үшін.
  perform public.expire_listings();

  select count(*) into v_active from public.listings
   where author_id = v_uid and status = 'active' and expires_at > now();
  if v_active >= 5 then raise exception 'TOO_MANY_LISTINGS'; end if;

  insert into public.listings (
    author_id, author_role, kind, vehicle_type, city, body, price_text,
    duration_days, photos, expires_at
  ) values (
    v_uid, v_role, v_kind, p_vehicle_type, btrim(p_city), btrim(p_body),
    btrim(coalesce(p_price_text, '')),
    case when v_kind = 'job' then greatest(0, least(90, coalesce(p_duration_days, 0))) else 0 end,
    v_photos, now() + interval '7 days'
  ) returning id into v_id;

  return v_id;
end;
$$;

-- Автордың өз хабарландыруын мерзімінен бұрын алып тастауы (архивке).
create or replace function public.archive_listing(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.listings;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into v_row from public.listings where id = p_id;
  if v_row.id is null then raise exception 'NOT_FOUND'; end if;
  if v_row.author_id <> v_uid then raise exception 'FORBIDDEN'; end if;

  insert into public.storage_purge_queue (bucket, path, purge_after)
  select 'listings', unnest(v_row.photos), now()
   where array_length(v_row.photos, 1) > 0;

  update public.listings
     set status = 'expired', photos = '{}', archived_at = now()
   where id = p_id;
end;
$$;

-- Архивтегі хабарландыруды ҚАЙТА жариялау: мерзімі жаңа 7 күнге ұзарады,
-- көру санағышы нөлден басталады. Фотолар БАЗАДАН ӨШІП КЕТКЕН болғандықтан
-- (мерзім бітті → Storage тазаланды) қайта жүктеп беру керек. Мәтін/баға/
-- көлік/қала параметрлері null болса — ескі мәні сақталады (қолданушы
-- қайта жариялау экранында түзете алады).
create or replace function public.repost_listing(
  p_id uuid,
  p_photos text[] default '{}',
  p_body text default null,
  p_price_text text default null,
  p_vehicle_type text default null,
  p_city text default null,
  p_duration_days int default null
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_row    public.listings;
  v_active int;
  v_photos text[] := coalesce(p_photos, '{}');
  v_body   text;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.board_enabled() then raise exception 'BOARD_OFF'; end if;

  select * into v_row from public.listings where id = p_id;
  if v_row.id is null then raise exception 'NOT_FOUND'; end if;
  if v_row.author_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  -- ЕСКЕРТУ: 'ALREADY_ACTIVE' коды ТАРИФКЕ бекітілген (theme.dart errText),
  -- сол себепті хабарландыруға бөлек код.
  if v_row.status = 'active' then raise exception 'LISTING_ACTIVE'; end if;
  if coalesce(array_length(v_photos, 1), 0) > 4 then raise exception 'TOO_MANY_PHOTOS'; end if;

  v_body := btrim(coalesce(p_body, v_row.body));
  if length(v_body) < 10 then raise exception 'EMPTY'; end if;
  if p_vehicle_type is not null and p_vehicle_type not in
     ('gazelle','furgon','minivan','kamaz','fura','manipulator',
      'crane','loader','excavator','avtovyshka','tractor','assenizator')
  then raise exception 'BAD_VEHICLE_TYPE'; end if;

  perform public.expire_listings();
  select count(*) into v_active from public.listings
   where author_id = v_uid and status = 'active' and expires_at > now();
  if v_active >= 5 then raise exception 'TOO_MANY_LISTINGS'; end if;

  delete from public.listing_views where listing_id = p_id;
  update public.listings
     set status = 'active',
         photos = v_photos,
         views = 0,
         body = v_body,
         price_text = btrim(coalesce(p_price_text, price_text)),
         vehicle_type = coalesce(p_vehicle_type, vehicle_type),
         city = btrim(coalesce(nullif(btrim(p_city), ''), city)),
         duration_days = case when kind = 'job'
                              then greatest(0, least(90, coalesce(p_duration_days, duration_days)))
                              else 0 end,
         created_at = now(),
         expires_at = now() + interval '7 days',
         archived_at = null
   where id = p_id;
end;
$$;

-- Хабарландыруды біржола өшіру (автор өзі не модератор).
create or replace function public.delete_listing(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.listings;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into v_row from public.listings where id = p_id;
  if v_row.id is null then raise exception 'NOT_FOUND'; end if;
  if v_row.author_id <> v_uid and not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.storage_purge_queue (bucket, path, purge_after)
  select 'listings', unnest(v_row.photos), now()
   where array_length(v_row.photos, 1) > 0;

  delete from public.listings where id = p_id;
end;
$$;

-- ============================================================
-- 6) Модератор: жалпы шолу статистикасы
-- ============================================================
-- «Қанша орындаушы/клиент бар, қанша заказ онлайн, нешеуін орындап жатыр,
-- нешеуі орындаушы күтіп тұр, неше хабарландыру бар» — бір сұраныста.
create or replace function public.mod_overview_stats()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  return jsonb_build_object(
    -- ---- пайдаланушылар ----
    'clients_total',       (select count(*) from public.profiles where role = 'client'),
    'clients_blocked',     (select count(*) from public.profiles
                             where role = 'client' and blocked_at is not null),
    'clients_new_7d',      (select count(*) from public.profiles
                             where role = 'client' and created_at > now() - interval '7 days'),
    'executors_total',     (select count(*) from public.profiles where role = 'executor'),
    'executors_approved',  (select count(*) from public.executor_profiles where status = 'approved'),
    'executors_pending',   (select count(*) from public.executor_profiles where status = 'pending'),
    'executors_rejected',  (select count(*) from public.executor_profiles where status = 'rejected'),
    'executors_blocked',   (select count(*) from public.executor_profiles where status = 'blocked'),
    -- тарифі белсенді (жұмысқа дайын) орындаушылар
    'executors_on_tariff', (select count(distinct ts.executor_id) from public.tariff_sessions ts
                             where ts.expires_at > now()),
    -- тарифі белсенді ЖӘНЕ линияда (демалыста емес)
    'executors_on_line',   (select count(*) from public.executor_profiles ep
                             where ep.status = 'approved' and coalesce(ep.on_line, true)
                               and exists (select 1 from public.tariff_sessions ts
                                            where ts.executor_id = ep.user_id
                                              and ts.expires_at > now())),
    'executors_busy',      (select count(*) from public.executor_profiles
                             where busy_order_id is not null),

    -- ---- заказдар ----
    -- «онлайн» = қазір жүйеде тірі заказ (іздеуде + орындалуда)
    'orders_online',       (select count(*) from public.orders
                             where status in ('searching','accepted','arrived','loading','in_transit')),
    -- орындаушы КҮТІП ТҰР (әлі ешкім алмаған)
    'orders_waiting',      (select count(*) from public.orders where status = 'searching'),
    -- орындаушылар ОРЫНДАП ЖАТЫР
    'orders_in_progress',  (select count(*) from public.orders
                             where status in ('accepted','arrived','loading','in_transit')),
    'orders_today',        (select count(*) from public.orders
                             where created_at > date_trunc('day', now())),
    'orders_completed_today', (select count(*) from public.orders
                             where status = 'completed' and completed_at > date_trunc('day', now())),
    'orders_cancelled_today', (select count(*) from public.orders
                             where status = 'cancelled' and created_at > date_trunc('day', now())),
    'orders_total',        (select count(*) from public.orders),
    -- күтіп тұрған заказдардың көлік түрі бойынша бөлінісі
    'waiting_by_vehicle',  (select coalesce(jsonb_agg(jsonb_build_object(
                                   'vehicle_type', v.vehicle_type, 'count', v.c)
                                 order by v.c desc), '[]'::jsonb)
                             from (select vehicle_type, count(*) c from public.orders
                                    where status = 'searching' group by vehicle_type) v),
    -- күтіп тұрған заказдардың қала бойынша бөлінісі
    'waiting_by_city',     (select coalesce(jsonb_agg(jsonb_build_object(
                                   'city', v.city, 'count', v.c) order by v.c desc), '[]'::jsonb)
                             from (select coalesce(from_city, '—') city, count(*) c
                                     from public.orders where status = 'searching'
                                    group by 1) v),

    -- ---- хабарландырулар ----
    'board_enabled',       public.board_enabled(),
    'listings_active',     (select count(*) from public.listings
                             where status = 'active' and expires_at > now()),
    'listings_jobs',       (select count(*) from public.listings
                             where status = 'active' and expires_at > now() and kind = 'job'),
    'listings_services',   (select count(*) from public.listings
                             where status = 'active' and expires_at > now() and kind = 'service'),
    'listings_expired',    (select count(*) from public.listings where status <> 'active'),
    'listings_today',      (select count(*) from public.listings
                             where created_at > date_trunc('day', now())),
    'listings_views',      (select count(*) from public.listing_views),

    -- ---- модератордың «жасалатын жұмысы» ----
    'applications_pending',(select count(*) from public.executor_profiles where status = 'pending'),
    'docs_review_pending', (select count(*) from public.executor_profiles
                             where coalesce(docs_review_pending, false)),
    'topups_pending',      (select count(*) from public.topup_requests where status = 'pending'),
    'reports_open',        (select count(*) from public.order_reports where status = 'open'),
    'support_open',        (select count(*) from public.support_threads where status = 'open')
  );
end;
$$;

-- Модераторға хабарландырулар тізімі (шолу бетінің «толығырақ» бөлімі).
-- p_status: 'active' | 'expired' | null (барлығы).
create or replace function public.mod_listings(p_status text default 'active')
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_res jsonb;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  -- listing_json композиттік `public.listings` типін күтеді, сол себепті
  -- ішкі сұраныста `select *` емес, НАҚТЫ кесте алиасы (l) беріледі.
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb)
    into v_res
    from (select public.listing_json(l, true) as j, l.created_at
            from public.listings l
           where (p_status is null or p_status = ''
                  or (p_status = 'active' and l.status = 'active' and l.expires_at > now())
                  or (p_status = 'expired' and (l.status <> 'active' or l.expires_at <= now())))
           order by l.created_at desc
           limit 200) x;

  return v_res;
end;
$$;

grant execute on function public.board_feed(text, text)            to authenticated;
grant execute on function public.my_listings()                     to authenticated;
grant execute on function public.open_listing(uuid)                to authenticated;
grant execute on function public.create_listing(text, text, text, text, int, text[]) to authenticated;
grant execute on function public.archive_listing(uuid)             to authenticated;
grant execute on function public.repost_listing(uuid, text[], text, text, text, text, int) to authenticated;
grant execute on function public.delete_listing(uuid)              to authenticated;
grant execute on function public.mod_overview_stats()              to authenticated;
grant execute on function public.mod_listings(text)                to authenticated;
-- expire_listings/listing_json — тек ІШКІ қолданысқа (cron + жоғарыдағы
-- RPC-лер). Postgres функцияларға әдепкіде PUBLIC-ке EXECUTE береді, сол
-- себепті оны әдейі кері аламыз: `listing_json`-ды сырттан шақырып, қолдан
-- жасалған жол арқылы бөгде профильдің деректерін сұрауға болмайды.
revoke all on function public.listing_json(public.listings, boolean) from public;
revoke all on function public.expire_listings() from public;

-- ============================================================
-- 7) Storage: 'listings' бакеті (public, orders бакетімен бірдей тәртіп)
-- ============================================================
insert into storage.buckets (id, name, public)
values ('listings', 'listings', true)
on conflict (id) do nothing;

drop policy if exists "listings_insert_own" on storage.objects;
create policy "listings_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'listings' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "listings_select_all" on storage.objects;
create policy "listings_select_all" on storage.objects
  for select using (bucket_id = 'listings');

drop policy if exists "listings_update_own" on storage.objects;
create policy "listings_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'listings' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'listings' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "listings_delete_own_or_mod" on storage.objects;
create policy "listings_delete_own_or_mod" on storage.objects
  for delete to authenticated
  using (bucket_id = 'listings'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_moderator()));

-- ============================================================
-- 8) Cron: мерзімі өткен хабарландыруларды сағат сайын архивке шығару
-- ============================================================
-- Фотоларды нақты өшіруді `cleanup-storage` (0032, күн сайын 02:30 UTC)
-- `storage_purge_queue` арқылы жасайды — бөлек deploy қажет емес.
do $$ begin
  perform cron.unschedule('tasu-listings-expire');
exception when others then null; end $$;
select cron.schedule(
  'tasu-listings-expire',
  '7 * * * *',   -- сағат сайын 7-минутта
  $$select public.expire_listings();$$
);
