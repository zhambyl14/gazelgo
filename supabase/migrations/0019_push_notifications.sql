-- GazelGo · 0019_push_notifications.sql
-- Push-хабарландырулар (FCM): модератор жаңа/қайта жіберілген газелист
-- өтінімі туралы қосымша ЖАБЫҚ болса да хабарланады.
--
-- Ағын: клиент FCM токенін save_push_token арқылы сақтайды → executor_profiles
-- кестесіне жаңа/қайта өтінім түскенде (INSERT не rejected→pending UPDATE)
-- триггер pg_net арқылы push-notify edge function-ды шақырады → функция
-- барлық модератордың токеніне FCM v1 API арқылы жібереді.
--
-- Толық баптау нұсқауы: supabase/APPLY.md → «Push-хабарландырулар».

create extension if not exists pg_net;

-- ---------- push_tokens ----------
create table if not exists public.push_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  token      text not null unique,
  platform   text not null default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_push_tokens_user on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;

drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Клиент FCM токенін осы арқылы сақтайды (upsert — бір құрылғыда пайдаланушы
-- ауысса, токен автоматты жаңа иесіне ауысады).
create or replace function public.save_push_token(p_token text, p_platform text default 'unknown')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  if trim(coalesce(p_token,'')) = '' then raise exception 'BAD_INPUT'; end if;
  insert into public.push_tokens (user_id, token, platform)
  values (auth.uid(), trim(p_token), coalesce(nullif(trim(p_platform),''),'unknown'))
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;
revoke all on function public.save_push_token(text,text) from public, anon;
grant execute on function public.save_push_token(text,text) to authenticated;

-- ---------- модераторға автоматты push (жаңа/қайта газелист өтінімі) ----------
create or replace function public.notify_moderators_new_application()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_secret text;
begin
  v_secret := current_setting('app.settings.push_trigger_secret', true);
  -- Push әлі бапталмаса (құпия сөз орнатылмаса) — үнсіз өтеді, өтінімнің
  -- өзі сақталуын бұзбайды.
  if v_secret is null or v_secret = '' then
    return new;
  end if;

  select full_name into v_name from public.profiles where id = new.user_id;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/push-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'applicant_name', coalesce(v_name, ''),
      'is_resubmit', (tg_op = 'UPDATE')
    )
  );
  return new;
exception when others then
  -- push шақыруы сәтсіз болса да, негізгі INSERT/UPDATE үзілмеуі керек
  return new;
end;
$$;

drop trigger if exists trg_notify_new_application on public.executor_profiles;
create trigger trg_notify_new_application
  after insert on public.executor_profiles
  for each row execute function public.notify_moderators_new_application();

-- Тек rejected→pending (қайта өтінім) кезінде — guard_executor_profiles
-- триггері басқа ешбір status ауысуына жол бермейді, сондықтан бұл шарт
-- нақты «жаңа өтінім модерацияға түсті» дегенді білдіреді.
drop trigger if exists trg_notify_resubmit_application on public.executor_profiles;
create trigger trg_notify_resubmit_application
  after update on public.executor_profiles
  for each row
  when (new.status = 'pending' and old.status is distinct from new.status)
  execute function public.notify_moderators_new_application();
