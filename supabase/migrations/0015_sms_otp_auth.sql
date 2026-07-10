-- GazelGo · 0015_sms_otp_auth.sql
-- Телефон + құпиясөз аутентификациясы: SMS кодын (Mobizon) растау күйі және
-- жіберу лимиттерін сақтайтын кесте. Аккаунттар Supabase-те синтетикалық
-- email арқылы жасалады (7XXXXXXXXXX@phone.gazelgo.kz), сондықтан телефон
-- провайдерін бөлек баптау қажет емес — бар email/құпиясөз ағыны қолданылады.

create table if not exists public.sms_otps (
  phone             text primary key,          -- нормаланған 7XXXXXXXXXX
  purpose           text not null default '',  -- register | reset
  code_hash         text,                      -- SHA-256(code + secret + phone)
  expires_at        timestamptz,               -- код жарамдылығы (5 мин)
  verify_attempts   int not null default 0,    -- қате тексеру саны (5-тен соң блок)
  send_count        int not null default 0,    -- эскалация терезесіндегі жіберу саны
  window_started_at timestamptz,               -- эскалация терезесінің басы
  last_sent_at      timestamptz,
  next_allowed_at   timestamptz,               -- осы сәтке дейін қайта жіберуге болмайды
  created_at        timestamptz not null default now()
);

-- RLS қосулы, бірақ бірде-бір саясат жоқ: тек service_role (edge function)
-- қатынай алады. Anon/authenticated кодтарды не лимиттерді көре алмайды.
alter table public.sms_otps enable row level security;

-- Синтетикалық email бойынша auth пайдаланушысының id-ін табу.
-- Email санамалауды (enumeration) болдырмау үшін тек service_role шақыра алады.
create or replace function public.otp_user_id(p_email text)
returns uuid
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  select id from auth.users where email = lower(p_email) limit 1;
$$;

revoke all on function public.otp_user_id(text) from public, anon, authenticated;
grant execute on function public.otp_user_id(text) to service_role;
