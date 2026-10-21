-- GazelGo · 0085_tg_login_lang.sql
-- Telegram арқылы бір қадамдық «Кіру» (құпиясөзсіз) + боттың тілі.
--
-- 1) telegram_verifications.lang — растауды қосымшаның қай тілінен
--    бастағаны ('kk' | 'ru'). Бот пен Mini App жауапты СОЛ тілде береді:
--    орысша нұсқадан келгенге — орысша, қазақшадан — қазақша.
-- 2) tg_start_verification(p_lang) — тілді қабылдайды. Ескі нұсқа
--    (аргументсіз) ӨШІРІЛЕДІ: әйтпесе екеуі қатар тұрып, аргументсіз
--    шақыру екіұшты болар еді. Әдепкі мәні бар жаңа функция ескі
--    қосымшалардың аргументсіз шақыруын да қабылдайды.

alter table public.telegram_verifications
  add column if not exists lang text not null default 'kk';

drop function if exists public.tg_start_verification();

create or replace function public.tg_start_verification(p_lang text default 'kk')
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
  insert into public.telegram_verifications (token, lang)
  values (v_token, case when p_lang = 'ru' then 'ru' else 'kk' end);
  return v_token;
end;
$$;
revoke all on function public.tg_start_verification(text) from public;
grant execute on function public.tg_start_verification(text) to anon, authenticated;
