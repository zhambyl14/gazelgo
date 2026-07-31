-- ============================================================
-- Tasu · 0054_support_bot.sql
-- ============================================================
-- ҚОЛДАУ ЧАТЫНЫҢ АВТОМАТТЫ БОТЫ.
--
-- Модератор app_settings-тен қосып/өшіре алатын бот: пайдаланушы (клиент/
-- орындаушы) қолдау чатына жазса, `support-bot` edge функциясы Gemini-мен
-- жауап жобасын құрастырып, ТІКЕЛЕЙ ЧАТҚА ЖАЗАДЫ — модератор жазғандай
-- көрінеді (пайдаланушыға бот екені білінбейді, СІЗДІҢ таңдауыңыз бойынша).
--
-- БОТ ШЕШІМ ҚАБЫЛДАМАЙДЫ, ТЕК ЖАУАП ЖАЗАДЫ. Егер хабарлама:
--   · заказ статусын өзгертуге/бас тартуға/қайтаруға қатысты болса, НЕМЕСЕ
--   · пайдаланушы АНЫҚ адам (оператор) сұраса, НЕМЕСЕ
--   · осы тредте бот жауабы 5-тен асып кетсе (`max_auto_replies_per_thread`),
-- бот ЕШТЕҢЕ ЖАЗБАЙДЫ — Telegram-дағы @imagcheckerbot чатына («толтыру
-- ботымен» ОРТАҚ инфрақұрылым) ескерту жіберіледі, модератор қосымшадан
-- өзі жалғастырады. Пайдаланушы үшін бұл әдеттегі «жауап күту» сияқты
-- көрінеді — ешқандай «боттан адамға ауыстырылды» деген белгі шықпайды.
--
-- ЕСКЕРТУ: 0053-тен КЕЙІН орындаңыз. Идемпотентті. Әдепкіде ӨШІРУЛІ
-- (`enabled: false`) — модератор саналы түрде қосуы керек.
-- ============================================================


-- ============================================================
-- 1) Бот баптауы
-- ============================================================
insert into public.app_settings (key, value) values (
  'support_bot',
  '{"enabled": false, "max_auto_replies_per_thread": 5}'::jsonb
) on conflict (key) do nothing;

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
                   'vehicle_rules', 'listings', 'taxi', 'topup_bot',
                   'support_bot') then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;


-- ============================================================
-- 2) Боттың профилі — chat хабарламасының sender_id-і осыны нұсқайды
-- ============================================================
-- `support_messages.sender_id` НЕГІЗГІ `auth.users`-ке сілтейді, сондықтан
-- дайын профиль жоқ, ЖАЛҒАН auth.users жазбасын SQL-мен жасау ҚАУІПТІ
-- (Supabase-тің auth ішкі инварианттарын бұзуы мүмкін). Сол себепті боттың
-- auth пайдаланушысын edge функция өзі, Admin API арқылы, БІР РЕТ жасайды
-- (`getOrCreateBotProfileId`, support-bot/index.ts) және id-ін осында
-- сақтайды — келесі шақыруларда қайта жасамайды.
insert into public.app_secrets (key, value) values ('support_bot_profile_id', '')
on conflict (key) do nothing;


-- ============================================================
-- 3) notify_support_message — bot рөлін де тани бастайды
-- ============================================================
-- Бұрын: 'moderator' → пайдаланушыға push, басқасы → барлық модераторға.
-- Енді: 'moderator' ЖӘНЕ 'bot' → пайдаланушыға push (екеуі де «қолдау
-- жауап берді» дегенді білдіреді, пайдаланушы үшін айырмашылығы жоқ);
-- тек 'user' ғана модераторларға broadcast жасайды (боттың ӨЗ жауабы
-- модераторларды бекерге шулатпайды).
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

  if new.sender_role in ('moderator', 'bot') then
    perform public.send_push(
      'Tasu қолдау қызметі',
      v_snippet,
      jsonb_build_object('type', 'support_reply', 'thread_id', t.id::text),
      array[t.user_id]
    );
  else
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

-- Триггер функциясы сол атпен қалады, тек денесі жаңарды — қайта
-- create trigger жасаудың қажеті жоқ.


-- ============================================================
-- 4) Жаңа хабарлама → `support-bot` функциясын шақыру
-- ============================================================
-- Тек `sender_role = 'user'` кезінде (клиент/орындаушы жазғанда) және
-- бот қосулы болғанда ғана дисп etch жасалады.
create or replace function public.dispatch_support_bot()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
  v_cfg    jsonb;
begin
  if new.sender_role <> 'user' then return new; end if;

  select value into v_cfg from public.app_settings where key = 'support_bot';
  if coalesce((v_cfg->>'enabled')::boolean, false) is not true then return new; end if;

  select value into v_secret from public.app_secrets where key = 'support_bot_secret';
  if v_secret is null or v_secret = '' then return new; end if;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/support-bot',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-support-secret', v_secret
    ),
    body := jsonb_build_object(
      'thread_id', new.thread_id::text,
      'message_id', new.id::text
    ),
    timeout_milliseconds := 30000
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_dispatch_support_bot on public.support_messages;
create trigger trg_dispatch_support_bot
  after insert on public.support_messages
  for each row execute function public.dispatch_support_bot();


-- ============================================================
-- 5) Боттың атынан жазу RPC-і (service_role)
-- ============================================================
-- `support_reply` тек `is_moderator()`-ды талап етеді, ал бот
-- `auth.uid()`-сіз (service-role кілтпен) шақырады. Сол себепті бөлек
-- жол — құпия сөзбен қорғалған, тек service_role шақыра алады.
create or replace function public.bot_support_reply(
  p_secret  text,
  p_thread  uuid,
  p_body    text,
  p_sender  uuid
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(p_secret, '') = '' or not exists (
    select 1 from public.app_secrets
     where key = 'support_bot_secret' and value = p_secret
  ) then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'EMPTY'; end if;

  update public.support_threads
     set status = 'open', last_sender_role = 'bot', last_msg_at = now()
   where id = p_thread;

  insert into public.support_messages (thread_id, sender_id, sender_role, body)
  values (p_thread, p_sender, 'bot', trim(p_body));
end;
$$;

revoke all on function public.bot_support_reply(text, uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.bot_support_reply(text, uuid, text, uuid) to service_role;
