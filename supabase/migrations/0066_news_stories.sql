-- ============================================================
-- Tasu · 0066_news_stories.sql
-- ============================================================
-- «ЖАҢАЛЫҚТАР» — sidebar-дағы «Хабарландырулардың» ҮСТІНДЕ тұратын жаңа
-- бөлім. Instagram Stories / WhatsApp Status үлгісі: толық экранмен,
-- жоғарыда прогресс жолақтары, түртсең келесіге өтеді, ұстап тұрсаң
-- тоқтайды.
--
-- НЕГЕ КЕСТЕ, `app_settings` ЕМЕС: жаңалық — БІР баптау емес, саны
-- өзгеріп отыратын ЖАЗБАЛАР тізімі (әрқайсысының өз медиасы, өз мерзімі,
-- өз аудиториясы). `app_settings` бір JSON-ды бүтіндей ауыстырады —
-- екі модератор қатар өңдесе, бірінікі жоғалып кетер еді.
--
-- МОДЕРАТОР ӘР ЖАҢАЛЫҚҚА ҚОЯ АЛАДЫ:
--   · media_type = image | video | text — сурет, ҚЫСҚА видео немесе таза мәтін;
--   · music_path — фонда ойнайтын әуен (видеода да, суретте де);
--   · title / body — жазу (мәтін жаңалығында негізгі мазмұн);
--   · link_url + link_label — міндетті емес «Толығырақ» түймесі;
--   · duration_sec — сторис ЭКРАНДА неше секунд тұрады (видеода видеоның
--     өз ұзақтығы басым);
--   · starts_at / expires_at — қашан ШЫҒАДЫ және қашан ЖОҒАЛАДЫ
--     («неше уақыт тұратыны»); expires_at null — мерзімсіз;
--   · audiences — КІМГЕ көрінеді: {client}, {executor}, {client,executor},
--     {guest} немесе кез келген комбинациясы;
--   · active — қолмен қосу/өшіру;
--   · sort_order — стористердің реті.
--
-- БӨЛІМНІҢ ӨЗІН модератор `app_settings.news.enabled` арқылы қосады, ал
-- картадағы «Жаңа» жапсырмасын `app_settings.news.new_badge` арқылы
-- бөлек алады (0058-дегі «Такси»/«Хабарландырулар» тәртібімен бірдей).
--
-- ҚАУІПСІЗДІК: `news_stories` мен `news_views` RLS қосулы, САЯСАТ ӘДЕЙІ
-- ЖОҚ — бүкіл қатынас төмендегі security definer RPC-лер арқылы ғана
-- (0043 `listings` тәртібіндей). Жазуға тек модератор жетеді.
--
-- ЕСКЕРТУ: идемпотентті, SQL Editor-да ҚОЛМЕН қолданылады (Supabase MCP
-- бұл сессияда авторизацияланбаған). 0065-тен КЕЙІН орындаңыз.
-- ============================================================


-- ============================================================
-- 1) Модератордың қосқыш баптауы
-- ============================================================
-- Әдепкі — ӨШУЛІ: модератор бірінші жаңалығын дайындап болғанда қосады.
insert into public.app_settings (key, value)
values ('news', jsonb_build_object('enabled', false, 'new_badge', true))
on conflict (key) do nothing;

-- 0060-тағы функцияны кеңейтеміз. Тізімге 'news' қосылды, әрі 0058-де
-- қосылып, 0060-та БАЙҚАУСЫЗ түсіп қалған 'support' кілті қайтарылды
-- (онсыз модератор қолдау чатының авто-жабылу мерзімін сақтай алмайтын).
create or replace function public.mod_update_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer
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
    'share_trip', 'referral', 'news'
  ) then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

-- Бөлім қосулы ма — қосымша sidebar ашылған сайын сұрайды (жеңіл, құпиясыз).
-- ГЕСТ те шақырады, сол себепті `anon`-ға да рұқсат.
create or replace function public.news_enabled()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select (value->>'enabled')::boolean from public.app_settings
      where key = 'news'),
    false);
$$;

grant execute on function public.news_enabled() to anon, authenticated;

-- «ЖАҢА» белгілері (0058) — үшінші кілт ('news') қосылды. Кілт жоқ болса
-- `true` (fail-open: жаңа фичаны байқаусыз жасырып алмаймыз).
create or replace function public.new_badges()
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'board', coalesce(
      (select (value->>'new_badge')::boolean from public.app_settings
        where key = 'listings'), true),
    'taxi', coalesce(
      (select (value->>'new_badge')::boolean from public.app_settings
        where key = 'taxi'), true),
    'news', coalesce(
      (select (value->>'new_badge')::boolean from public.app_settings
        where key = 'news'), true)
  );
$$;

grant execute on function public.new_badges() to anon, authenticated;


-- ============================================================
-- 2) Кестелер
-- ============================================================
create table if not exists public.news_stories (
  id           uuid primary key default gen_random_uuid(),
  title        text not null default '',
  body         text not null default '',
  -- image = сурет, video = қысқа видео, text = тек жазу (медиасыз)
  media_type   text not null default 'text'
                 check (media_type in ('image', 'video', 'text')),
  -- 'news' бакетіндегі жол (media_type = 'text' болса null)
  media_path   text,
  -- фонда ойнайтын әуен, 'news' бакетінде (міндетті емес)
  music_path   text,
  music_title  text not null default '',
  -- міндетті емес «Толығырақ» түймесі
  link_url     text not null default '',
  link_label   text not null default '',
  -- КІМГЕ көрінеді: client · executor · guest (бірнешеуі бірге болуы мүмкін)
  audiences    text[] not null default array['client', 'executor'],
  -- сторис экранда неше секунд тұрады (видеода видеоның ұзақтығы басым)
  duration_sec int not null default 6 check (duration_sec between 2 and 60),
  active       boolean not null default true,
  sort_order   int not null default 0,
  starts_at    timestamptz not null default now(),
  -- null = мерзімсіз (модератор өзі өшіргенше тұра береді)
  expires_at   timestamptz,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- Аудитория БОС болмауы шарт әрі тек белгілі үш мәннен тұруы керек:
  -- бос массив «ешкімге көрінбейді» дегенді білдіріп, модератор жаңалығын
  -- «жарияладым» деп ойлап, ол ешкімге жетпей қалар еді.
  constraint news_audiences_valid check (
    array_length(audiences, 1) >= 1
    and audiences <@ array['client', 'executor', 'guest']
  ),
  -- Медиа түрі 'text' болмаса — файлы болуы шарт.
  constraint news_media_present check (
    media_type = 'text' or coalesce(media_path, '') <> ''
  )
);

create index if not exists idx_news_live
  on public.news_stories (sort_order, created_at desc)
  where active;

-- Кім қай стористі КӨРДІ (Instagram-дағыдай «оқылмаған» сақинасы үшін).
-- Гесте uid жоқ — оның көргені құрылғыда (SharedPreferences) сақталады.
create table if not exists public.news_views (
  story_id   uuid not null references public.news_stories(id) on delete cascade,
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

-- Екеуінде де RLS қосулы, САЯСАТ ӘДЕЙІ ЖОҚ: барлық қатынас төмендегі
-- security definer RPC-лер арқылы ғана (0043 `listings` тәртібіндей).
alter table public.news_stories enable row level security;
alter table public.news_views  enable row level security;


-- ============================================================
-- 3) Ішкі көмекші: шақырушының аудиториясы
-- ============================================================
-- Кірмеген адам — 'guest'. Кіргеннің БЕЛСЕНДІ рөлі 'client' не 'executor'.
-- Модератордың рөлі 'moderator' — ол алдын ала қарау үшін БӘРІН көреді
-- (төмендегі `news_feed` сүзгісінде бөлек ескерілген).
--
-- `p.role` — МӘТІН ЕМЕС, `user_role` ENUM түрі (0001). Сол себепті `::text`
-- КАСТЫ МІНДЕТТІ: онсыз `coalesce` екінші аргументті де сол enum-ға
-- келтіруге тырысады да, «invalid input value for enum user_role: "guest"»
-- деген қатемен құлайды (enum-да 'guest' деген мән ЖОҚ — гест дегеніміз
-- аккаунты жоқ адам, оның `profiles` жазбасы да болмайды).
create or replace function public.news_audience()
returns text
language sql stable
set search_path = public, pg_temp
as $$
  select coalesce(
    (select p.role::text from public.profiles p where p.id = auth.uid()),
    'guest');
$$;

revoke all on function public.news_audience() from public, anon, authenticated;


-- ============================================================
-- 4) Қосымша оқитын лента
-- ============================================================
-- Бөлім өшірулі болса — БОС тізім (қосымша картаны да көрсетпейді).
-- `seen` тек кірген адамға мәнді; гесте әрқашан false болады да,
-- «көрдім» белгісін қосымша өз құрылғысында сақтайды.
create or replace function public.news_feed()
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(x order by x.sort_order, x.created_at), '[]'::jsonb)
    from (
      select
        n.id,
        n.title,
        n.body,
        n.media_type,
        n.media_path,
        n.music_path,
        n.music_title,
        n.link_url,
        n.link_label,
        n.duration_sec,
        n.sort_order,
        n.created_at,
        exists (
          select 1 from public.news_views v
           where v.story_id = n.id and v.viewer_id = auth.uid()
        ) as seen
        from public.news_stories n
       where public.news_enabled()
         and n.active
         and n.starts_at <= now()
         and (n.expires_at is null or n.expires_at > now())
         and (
           public.news_audience() = 'moderator'
           or n.audiences @> array[public.news_audience()]
         )
    ) x;
$$;

grant execute on function public.news_feed() to anon, authenticated;

-- Стористі «көрдім» деп белгілеу. Гесте (auth.uid() is null) үнсіз өтеді —
-- қате лақтырмайды, себебі қосымша гест үшін де дәл сол кодты шақырады.
create or replace function public.news_mark_seen(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.news_views (story_id, viewer_id)
  values (p_id, auth.uid())
  on conflict (story_id, viewer_id) do nothing;
end;
$$;

grant execute on function public.news_mark_seen(uuid) to authenticated;


-- ============================================================
-- 5) Модератордың CRUD функциялары
-- ============================================================
-- Толық тізім — мерзімі өткені мен өшірулісін ҚОСА (модератор оларды
-- қайта қосып, мерзімін ұзарта алуы керек).
create or replace function public.mod_news_list()
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select case
    when not public.is_moderator() then '[]'::jsonb
    else coalesce(
      (select jsonb_agg(to_jsonb(n) || jsonb_build_object(
                'views', (select count(*) from public.news_views v
                           where v.story_id = n.id))
              order by n.sort_order, n.created_at desc)
         from public.news_stories n),
      '[]'::jsonb)
  end;
$$;

grant execute on function public.mod_news_list() to authenticated;

-- Қосу ДА, өңдеу ДЕ осы функция арқылы: `p_id` null болса — жаңа жазба.
-- Жаңасының `sort_order`-і тізімнің басына қойылады (соңғы жаңалық
-- бірінші көрінеді — стористердің әдеттегі тәртібі).
create or replace function public.mod_news_save(
  p_id           uuid,
  p_title        text,
  p_body         text,
  p_media_type   text,
  p_media_path   text,
  p_music_path   text,
  p_music_title  text,
  p_link_url     text,
  p_link_label   text,
  p_audiences    text[],
  p_duration_sec int,
  p_active       boolean,
  p_starts_at    timestamptz,
  p_expires_at   timestamptz
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_id  uuid;
  v_old public.news_stories;
  v_dur int;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if p_media_type not in ('image', 'video', 'text') then
    raise exception 'BAD_MEDIA_TYPE';
  end if;
  if p_media_type <> 'text' and coalesce(p_media_path, '') = '' then
    raise exception 'MEDIA_REQUIRED';
  end if;
  if coalesce(array_length(p_audiences, 1), 0) = 0
     or not (p_audiences <@ array['client', 'executor', 'guest']) then
    raise exception 'BAD_AUDIENCE';
  end if;
  -- Ұзақтықты ҚЫСАМЫЗ (қате санмен `check` бұзылып, түсініксіз қате
  -- шықпауы үшін): 2..60 сек.
  v_dur := least(60, greatest(2, coalesce(p_duration_sec, 6)));

  if p_id is null then
    insert into public.news_stories (
      title, body, media_type, media_path, music_path, music_title,
      link_url, link_label, audiences, duration_sec, active,
      sort_order, starts_at, expires_at, created_by
    ) values (
      coalesce(p_title, ''), coalesce(p_body, ''), p_media_type,
      nullif(coalesce(p_media_path, ''), ''),
      nullif(coalesce(p_music_path, ''), ''), coalesce(p_music_title, ''),
      coalesce(p_link_url, ''), coalesce(p_link_label, ''),
      p_audiences, v_dur, coalesce(p_active, true),
      coalesce((select min(sort_order) - 1 from public.news_stories), 0),
      coalesce(p_starts_at, now()), p_expires_at, auth.uid()
    ) returning id into v_id;
    return v_id;
  end if;

  select * into v_old from public.news_stories where id = p_id;
  if not found then raise exception 'NOT_FOUND'; end if;

  -- Файл АУЫСТЫРЫЛСА — ескісі Storage-та қалып қоймауы керек. Дереу
  -- өшірмейміз: сол сәтте сторисі ашық тұрған адамда сурет үзіліп
  -- қалар еді, сол себепті 1 сағаттан соң `cleanup-storage` (0032)
  -- өшіретін кезекке саламыз.
  if coalesce(v_old.media_path, '') <> coalesce(p_media_path, '')
     and coalesce(v_old.media_path, '') <> '' then
    insert into public.storage_purge_queue (bucket, path, purge_after)
    values ('news', v_old.media_path, now() + interval '1 hour');
  end if;
  if coalesce(v_old.music_path, '') <> coalesce(p_music_path, '')
     and coalesce(v_old.music_path, '') <> '' then
    insert into public.storage_purge_queue (bucket, path, purge_after)
    values ('news', v_old.music_path, now() + interval '1 hour');
  end if;

  update public.news_stories
     set title        = coalesce(p_title, ''),
         body         = coalesce(p_body, ''),
         media_type   = p_media_type,
         media_path   = nullif(coalesce(p_media_path, ''), ''),
         music_path   = nullif(coalesce(p_music_path, ''), ''),
         music_title  = coalesce(p_music_title, ''),
         link_url     = coalesce(p_link_url, ''),
         link_label   = coalesce(p_link_label, ''),
         audiences    = p_audiences,
         duration_sec = v_dur,
         active       = coalesce(p_active, true),
         starts_at    = coalesce(p_starts_at, v_old.starts_at),
         expires_at   = p_expires_at,
         updated_at   = now()
   where id = p_id;
  return p_id;
end;
$$;

grant execute on function public.mod_news_save(
  uuid, text, text, text, text, text, text, text, text, text[],
  int, boolean, timestamptz, timestamptz) to authenticated;

create or replace function public.mod_news_delete(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.news_stories;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  select * into v_old from public.news_stories where id = p_id;
  if not found then return; end if;

  -- Медиасын өшіру кезегіне (0037) саламыз — Storage-та қоқыс қалмайды.
  insert into public.storage_purge_queue (bucket, path, purge_after)
  select 'news', x, now() + interval '1 hour'
    from unnest(array[v_old.media_path, v_old.music_path]) as x
   where coalesce(x, '') <> '';

  delete from public.news_stories where id = p_id;
end;
$$;

grant execute on function public.mod_news_delete(uuid) to authenticated;

-- Сүйреп ретін ауыстыру: массивтегі орны = жаңа `sort_order`.
create or replace function public.mod_news_reorder(p_ids uuid[])
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  update public.news_stories n
     set sort_order = i.ord, updated_at = now()
    from (select unnest(p_ids) as id,
                 generate_subscripts(p_ids, 1) as ord) i
   where n.id = i.id;
end;
$$;

grant execute on function public.mod_news_reorder(uuid[]) to authenticated;


-- ============================================================
-- 6) Мерзімі өткендерін өшіру (cron)
-- ============================================================
-- Сторис `expires_at` өткенде лентадан `news_feed` сүзгісі арқылы БІРДЕН
-- жоғалады — бұл cron жазбаның ӨЗІН тазалайды (медиасын өшіру кезегіне
-- қоя отырып), әйтпесе кесте ескі стористермен толып кетер еді.
-- Мерзімі 30 күн бұрын өткендер ғана өшеді: модератор жақындағы
-- жаңалығын ұзартып, қайта жариялай алады.
create or replace function public.purge_expired_news()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.storage_purge_queue (bucket, path, purge_after)
  select 'news', x, now() + interval '1 hour'
    from public.news_stories n,
         unnest(array[n.media_path, n.music_path]) as x
   where n.expires_at is not null
     and n.expires_at < now() - interval '30 days'
     and coalesce(x, '') <> '';

  delete from public.news_stories
   where expires_at is not null
     and expires_at < now() - interval '30 days';
end;
$$;

revoke execute on function public.purge_expired_news() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('tasu-news-purge');
exception when others then null; end $$;

select cron.schedule(
  'tasu-news-purge',
  '23 3 * * *',   -- күн сайын 03:23 UTC
  $$select public.purge_expired_news()$$);


-- ============================================================
-- 7) Storage: 'news' бакеті (public оқу, ЖАЗУ ТЕК МОДЕРАТОРҒА)
-- ============================================================
-- Оқу `anon`-ға да ашық: жаңалық ГЕСТКЕ де көрінуі мүмкін (audiences-те
-- 'guest' болса), ал гест — кірмеген қолданушы.
insert into storage.buckets (id, name, public)
values ('news', 'news', true)
on conflict (id) do nothing;

drop policy if exists "news_read_all" on storage.objects;
create policy "news_read_all" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'news');

drop policy if exists "news_write_mod" on storage.objects;
create policy "news_write_mod" on storage.objects
  for all to authenticated
  using (bucket_id = 'news' and public.is_moderator())
  with check (bucket_id = 'news' and public.is_moderator());


-- ============================================================
-- ТЕКСЕРУ (қолмен қосып көруге болады, міндетті емес):
--   select public.news_enabled();            -- false (әлі қосылмаған)
--   select public.new_badges();               -- {board, taxi, news}
--   select public.news_feed();                -- [] (бөлім өшулі)
--   select public.mod_news_list();            -- [] (модератор емеспін)
-- ============================================================
