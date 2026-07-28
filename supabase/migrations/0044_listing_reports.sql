-- Tasu · 0044_listing_reports.sql
-- «Хабарландыруға шағым» — БӨЛЕК механизм.
--
-- 0043-те шағым қолдау чатына жай МӘТІН болып түсетін: модератор оны оқыды,
-- бірақ ары қарай ЕШТЕҢЕ істей алмайтын (хабарландыруды сол жерден таба да,
-- өшіре де алмайтын). Енді әр шағым — кесте жазбасы:
--
--   * шағымның ішінде хабарландырудың СНИМОГІ сақталады (мәтін, қала, көлік
--     түрі, фотолары) — хабарландыру өшіп кетсе де модератор нені өшіргенін
--     көреді;
--   * модератор бір батырмамен «Хабарландыруды өшіру» немесе «Елеусіз
--     қалдыру» дейді, әрекеті жазбада қалады (кім, қашан);
--   * бір хабарландыруды өшіргенде сол хабарландыруға түскен БАРЛЫҚ ашық
--     шағым бірден жабылады.
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындаңыз
-- (0043-тен КЕЙІН).

-- ============================================================
-- 1) Кесте
-- ============================================================
create table if not exists public.listing_reports (
  id            uuid primary key default gen_random_uuid(),
  -- Хабарландыру өшсе де шағым жазбасы ҚАЛАДЫ (тарих үшін) — сол себепті
  -- cascade емес, `set null`. listing_id = null → «өшірілген».
  listing_id    uuid references public.listings(id) on delete set null,
  reporter_id   uuid not null references public.profiles(id) on delete cascade,
  author_id     uuid references public.profiles(id) on delete set null,
  reason        text not null default '',

  -- ---- хабарландырудың снимогі (шағым берілген сәттегі күйі) ----
  listing_body         text   not null default '',
  listing_city         text   not null default '',
  listing_vehicle_type text   not null default '',
  listing_kind         text   not null default '',
  listing_photos       text[] not null default '{}',

  status        text not null default 'open'
                  check (status in ('open', 'resolved', 'dismissed')),
  -- 'deleted' = хабарландыру өшірілді, 'kept' = ережені бұзбаған
  action        text,
  moderator_id  uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz
);

create index if not exists idx_listing_reports_open
  on public.listing_reports (status, created_at desc);
create index if not exists idx_listing_reports_listing
  on public.listing_reports (listing_id);

-- Бір адам бір хабарландыруға бір ғана АШЫҚ шағым бере алады (спамға тосқауыл).
create unique index if not exists uq_listing_reports_open
  on public.listing_reports (listing_id, reporter_id) where status = 'open';

-- listings/listing_views тәртібіндей: RLS қосулы, САЯСАТ ӘДЕЙІ ЖОҚ —
-- бүкіл қатынас төмендегі security definer RPC-лер арқылы ғана.
alter table public.listing_reports enable row level security;

-- ============================================================
-- 2) Қолданушы: шағым жіберу
-- ============================================================
create or replace function public.report_listing(
  p_listing uuid,
  p_reason text default ''
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_row   public.listings;
  v_today int;
  v_id    uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.board_enabled() then raise exception 'BOARD_OFF'; end if;

  select * into v_row from public.listings where id = p_listing;
  if v_row.id is null then raise exception 'NOT_FOUND'; end if;
  -- өз хабарландыруыңа шағымданудың мәні жоқ (өзің өшіре аласың)
  if v_row.author_id = v_uid then raise exception 'FORBIDDEN'; end if;

  -- тәулігіне 10 шағым — жалған шағым «бомбалауына» тосқауыл
  select count(*) into v_today from public.listing_reports
   where reporter_id = v_uid and created_at > now() - interval '1 day';
  if v_today >= 10 then raise exception 'RATE_LIMITED'; end if;

  insert into public.listing_reports (
    listing_id, reporter_id, author_id, reason,
    listing_body, listing_city, listing_vehicle_type, listing_kind,
    listing_photos
  ) values (
    p_listing, v_uid, v_row.author_id, btrim(coalesce(p_reason, '')),
    v_row.body, v_row.city, v_row.vehicle_type, v_row.kind, v_row.photos
  )
  on conflict (listing_id, reporter_id) where status = 'open' do nothing
  returning id into v_id;

  -- ештеңе қосылмады → бұл адамның осы хабарландыруға ашық шағымы бар
  if v_id is null then raise exception 'ALREADY_REPORTED'; end if;
  return v_id;
end;
$$;

-- ============================================================
-- 3) Модератор: тізім + шешім
-- ============================================================
-- p_status: 'open' (әдепкі) | 'closed' (қаралғандар) | '' (барлығы).
create or replace function public.mod_listing_reports(p_status text default 'open')
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_res jsonb;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb)
    into v_res
    from (
      select jsonb_build_object(
               'id',            r.id,
               'listing_id',    r.listing_id,
               -- хабарландыру әлі бар ма (жоқ болса — өшірілген)
               'listing_alive', (r.listing_id is not null),
               'reason',        r.reason,
               'status',        r.status,
               'action',        r.action,
               'created_at',    r.created_at,
               'resolved_at',   r.resolved_at,
               'reporter_id',   r.reporter_id,
               'reporter_name', coalesce(pr.full_name, '—'),
               'reporter_role', coalesce(pr.role::text, 'client'),
               'author_id',     r.author_id,
               'author_name',   coalesce(pa.full_name, '—'),
               'author_role',   coalesce(pa.role::text, 'client'),
               'author_blocked',(pa.blocked_at is not null),
               'body',          r.listing_body,
               'city',          r.listing_city,
               'vehicle_type',  r.listing_vehicle_type,
               'kind',          r.listing_kind,
               'photos',        to_jsonb(r.listing_photos),
               -- сол хабарландыруға түскен ЖАЛПЫ шағым саны (қайталанса —
               -- модератор оның шынымен проблемалы екенін бірден көреді)
               'reports_total', (select count(*) from public.listing_reports r2
                                  where r2.listing_id is not null
                                    and r2.listing_id = r.listing_id)
             ) as j,
             r.created_at
        from public.listing_reports r
        left join public.profiles pr on pr.id = r.reporter_id
        left join public.profiles pa on pa.id = r.author_id
       where (p_status is null or p_status = ''
              or (p_status = 'open'   and r.status = 'open')
              or (p_status = 'closed' and r.status <> 'open'))
       order by r.created_at desc
       limit 200) x;

  return v_res;
end;
$$;

-- Модератордың шешімі.
--   p_action = 'delete' → хабарландыру біржола өшіріледі (фотолары тазалау
--              кезегіне қосылады), сол хабарландыруға түскен БАРЛЫҚ ашық
--              шағым бірден жабылады;
--   p_action = 'keep'   → шағым негізсіз, тек осы жазба жабылады.
create or replace function public.mod_resolve_listing_report(
  p_id uuid,
  p_action text
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.listing_reports;
  v_listing public.listings;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  if p_action not in ('delete', 'keep') then raise exception 'BAD_INPUT'; end if;

  select * into v_row from public.listing_reports where id = p_id;
  if v_row.id is null then raise exception 'NOT_FOUND'; end if;

  if p_action = 'keep' then
    update public.listing_reports
       set status = 'dismissed', action = 'kept',
           moderator_id = v_uid, resolved_at = now()
     where id = p_id;
    return;
  end if;

  -- ---- delete ----
  if v_row.listing_id is not null then
    select * into v_listing from public.listings where id = v_row.listing_id;

    -- FK `on delete set null` жазбадағы listing_id-ді нөлдейді, сол себепті
    -- шағымдарды хабарландыруды өшірер АЛДЫНДА жабамыз.
    update public.listing_reports
       set status = 'resolved', action = 'deleted',
           moderator_id = v_uid, resolved_at = now()
     where status = 'open' and listing_id = v_row.listing_id;

    if v_listing.id is not null then
      insert into public.storage_purge_queue (bucket, path, purge_after)
      select 'listings', unnest(v_listing.photos), now()
       where array_length(v_listing.photos, 1) > 0;

      delete from public.listings where id = v_listing.id;
    end if;
  else
    -- хабарландыру бұрын өшіп кеткен — жазбаны жай ғана жабамыз
    update public.listing_reports
       set status = 'resolved', action = 'deleted',
           moderator_id = v_uid, resolved_at = now()
     where id = p_id;
  end if;
end;
$$;

-- ============================================================
-- 4) Шолу статистикасы: ашық хабарландыру шағымдарының саны
-- ============================================================
-- 0043-тегі функцияны қайта жазамыз — жалғыз өзгеріс:
-- жаңа 'listing_reports_open' кілті қосылды.
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
    'executors_on_tariff', (select count(distinct ts.executor_id) from public.tariff_sessions ts
                             where ts.expires_at > now()),
    'executors_on_line',   (select count(*) from public.executor_profiles ep
                             where ep.status = 'approved' and coalesce(ep.on_line, true)
                               and exists (select 1 from public.tariff_sessions ts
                                            where ts.executor_id = ep.user_id
                                              and ts.expires_at > now())),
    'executors_busy',      (select count(*) from public.executor_profiles
                             where busy_order_id is not null),

    -- ---- заказдар ----
    'orders_online',       (select count(*) from public.orders
                             where status in ('searching','accepted','arrived','loading','in_transit')),
    'orders_waiting',      (select count(*) from public.orders where status = 'searching'),
    'orders_in_progress',  (select count(*) from public.orders
                             where status in ('accepted','arrived','loading','in_transit')),
    'orders_today',        (select count(*) from public.orders
                             where created_at > date_trunc('day', now())),
    'orders_completed_today', (select count(*) from public.orders
                             where status = 'completed' and completed_at > date_trunc('day', now())),
    'orders_cancelled_today', (select count(*) from public.orders
                             where status = 'cancelled' and created_at > date_trunc('day', now())),
    'orders_total',        (select count(*) from public.orders),
    'waiting_by_vehicle',  (select coalesce(jsonb_agg(jsonb_build_object(
                                   'vehicle_type', v.vehicle_type, 'count', v.c)
                                 order by v.c desc), '[]'::jsonb)
                             from (select vehicle_type, count(*) c from public.orders
                                    where status = 'searching' group by vehicle_type) v),
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
    -- ЖАҢА (0044): хабарландыруға түскен ашық шағымдар
    'listing_reports_open',(select count(*) from public.listing_reports where status = 'open'),
    'support_open',        (select count(*) from public.support_threads where status = 'open')
  );
end;
$$;

grant execute on function public.report_listing(uuid, text)               to authenticated;
grant execute on function public.mod_listing_reports(text)                to authenticated;
grant execute on function public.mod_resolve_listing_report(uuid, text)   to authenticated;
grant execute on function public.mod_overview_stats()                     to authenticated;
