-- GazelGo · 0025_push_message_notifications.sql
-- Push (FCM) енді хабарламаға да жұмыс істейді: бұрын тек модератор жаңа
-- газелист өтінімі туралы алатын (0019), ал қолдау чатының хабарламалары
-- қосымша толық жабық тұрғанда МҮЛДЕМ жетпейтін (тек Notify.show — ол
-- қосымша тірі/фонда тұрғанда ғана жұмыс істейді).
--
-- Ортақ `send_push()` көмекші функциясы қосылды (pg_net арқылы push-notify
-- edge function-ды шақырады, target_user_ids болмаса — барлық модераторға
-- broadcast, ЕСКІ тәртіппен үйлесімді). Соған сай push-notify функциясы
-- ЖАЛПЫ форматқа көшірілуі керек (деплой қажет, supabase/APPLY.md-де).
--
-- ЕСКЕРТУ: `alter database postgres set app.settings.push_trigger_secret=...`
-- Supabase хостингте ЕНДІ РҰҚСАТ ЕТІЛМЕЙДІ («permission denied to set
-- parameter»). Сол себепті құпия сөз енді database GUC емес, RLS-пен
-- құлыпталған кестеде сақталады — `auth_events`-пен (0018) бірдей тәртіп:
-- саясат жоқ, тек SECURITY DEFINER функция (postgres иесі ретінде RLS-ті
-- айналып өтеді) оқи алады, `authenticated`/`anon` мүлдем оқи алмайды.

create table if not exists public.app_secrets (
  key   text primary key,
  value text not null
);
alter table public.app_secrets enable row level security;
-- Саясат ӘДЕЙІ жоқ — тек postgres/service_role (кесте иесі) оқи/жаза алады.

create or replace function public.send_push(
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_target_user_ids uuid[] default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
begin
  select value into v_secret from public.app_secrets where key = 'push_trigger_secret';
  -- Push әлі бапталмаса (құпия сөз орнатылмаса) — үнсіз өтеді.
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
      'data', coalesce(p_data, '{}'::jsonb),
      'target_user_ids', to_jsonb(p_target_user_ids)
    )
  );
exception when others then
  -- push шақыруы сәтсіз болса да, негізгі INSERT/UPDATE үзілмеуі керек
  null;
end;
$$;

-- ---------- модераторға жаңа/қайта өтінім: ЖАЛПЫ форматқа көшірілді ----------
create or replace function public.notify_moderators_new_application()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  select full_name into v_name from public.profiles where id = new.user_id;
  perform public.send_push(
    case when tg_op = 'UPDATE' then 'Қайта жіберілген өтінім'
         else 'Жаңа газелист өтінімі' end,
    case when coalesce(v_name, '') <> ''
         then v_name || ' тіркелу өтінімін жіберді — модерация күтуде.'
         else 'Жаңа өтінім модерация күтуде.' end,
    jsonb_build_object('type', 'new_application')
  );
  return new;
exception when others then
  return new;
end;
$$;

-- ---------- қолдау чатының хабарламасы: нақты алушыға push ----------
create or replace function public.notify_support_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t record;
  v_snippet text;
begin
  select * into t from public.support_threads where id = new.thread_id;
  if not found then return new; end if;

  v_snippet := left(coalesce(new.body, ''), 120);
  if v_snippet = '' and new.image_path is not null then
    v_snippet := '📷 Сурет жіберілді';
  end if;
  if v_snippet = '' then v_snippet := 'Жаңа хабарлама'; end if;

  if new.sender_role = 'moderator' then
    -- модератор жауап берді — нақты сол пайдаланушыға ғана
    perform public.send_push(
      'GazelGo қолдау қызметі',
      v_snippet,
      jsonb_build_object('type', 'support_reply', 'thread_id', t.id::text),
      array[t.user_id]
    );
  else
    -- пайдаланушы жазды — барлық модераторға (target_user_ids жоқ = broadcast)
    perform public.send_push(
      'Жаңа хабарлама — қолдау чаты',
      v_snippet,
      jsonb_build_object('type', 'support_message', 'thread_id', t.id::text)
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_support_message on public.support_messages;
create trigger trg_notify_support_message
  after insert on public.support_messages
  for each row execute function public.notify_support_message();
