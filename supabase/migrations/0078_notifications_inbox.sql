-- ============================================================
-- Tasu · 0078_notifications_inbox.sql
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
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0077-ден кейін).
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
