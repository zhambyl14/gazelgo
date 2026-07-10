-- GazelGo · 0026_telegram_verification.sql
-- Тіркелуде телефонды Telegram арқылы растау (SMS-сіз, ТЕГІН).
--
-- Ағын: қосымша `tg_start_verification()` шақырып, кездейсоқ токен алады →
-- пайдаланушыны `t.me/<bot>?start=<токен>`-ке жібереді → бот «Нөмірімді
-- бөлісу» түймесін көрсетеді → пайдаланушы басқанда Telegram НӨМІРДІ ӨЗІ
-- РАСТАП ботқа береді (жалған нөмір беру мүмкін емес) → `telegram-webhook`
-- edge функциясы (service_role) осы жолды `verified=true`, phone-мен
-- толтырады → қосымша `tg_check_verification()`-пен статусты сұрап отырады →
-- расталған соң тіркелу жалғасады. Код (сан) қажет емес — контакт бөлісудің
-- өзі растау.
--
-- Кесте RLS-пен ҚҰЛЫПТАЛҒАН (саясат жоқ) — жазуды тек webhook (service_role,
-- RLS-ті айналып өтеді), оқуды тек төмендегі SECURITY DEFINER RPC-лар
-- жасайды. Тіркелу авторизациядан БҰРЫН жүретіндіктен, RPC-лар `anon`-ға
-- ашық (токен кездейсоқ, phone тек webhook арқылы келеді).

create table if not exists public.telegram_verifications (
  token            text primary key,
  telegram_chat_id bigint,
  telegram_user_id bigint,
  phone            text,               -- 7XXXXXXXXXX (расталған соң)
  verified         boolean not null default false,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default now() + interval '15 minutes'
);
create index if not exists idx_tgverif_chat
  on public.telegram_verifications (telegram_chat_id)
  where telegram_chat_id is not null;
create index if not exists idx_tgverif_expires
  on public.telegram_verifications (expires_at);

alter table public.telegram_verifications enable row level security;
-- Саясат ӘДЕЙІ жоқ — тек service_role (webhook) мен SECURITY DEFINER RPC.

-- ---------- жаңа верификация сессиясын бастау ----------
create or replace function public.tg_start_verification()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_token text;
begin
  -- ескі/біткен жазбаларды тазалау (кесте өспес үшін)
  delete from public.telegram_verifications where expires_at < now();

  v_token := replace(gen_random_uuid()::text, '-', '')
             || replace(gen_random_uuid()::text, '-', '');
  insert into public.telegram_verifications (token) values (v_token);
  return v_token;
end;
$$;
revoke all on function public.tg_start_verification() from public;
grant execute on function public.tg_start_verification() to anon, authenticated;

-- ---------- статусты сұрау (қосымша polling жасайды) ----------
create or replace function public.tg_check_verification(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
begin
  select * into r from public.telegram_verifications
   where token = p_token and expires_at > now();
  if not found then
    return jsonb_build_object('verified', false, 'phone', null);
  end if;
  return jsonb_build_object(
    'verified', r.verified,
    'phone', case when r.verified then r.phone else null end
  );
end;
$$;
revoke all on function public.tg_check_verification(text) from public;
grant execute on function public.tg_check_verification(text) to anon, authenticated;
