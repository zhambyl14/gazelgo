-- Tasu · 0074_push_token_cleanup.sql
-- ЕСКІ push-токендерді тазалау.
--
-- Табылған жағдай (2026-10-16): бір орындаушы аккаунтта 10 токен жиналған
-- (шілде–тамыздағы ескі Android/iPhone орнатулары), ал басқа телефонда
-- бұрын кірген такси аккаунтының iPhone токені қалып қойған. Нәтижесі:
--   * сол телефонға ТАКСИ заказының push-ы келе береді — телефондағы ескі
--     қосымша (жаңартылмаған/жойылмаған) бұрынғы аккаунттың атынан
--     тіркелген, ал web-тен шығу оған әсер етпейді;
--   * газель заказының push-ы орындаушының ЕСКІ құрылғыларына кетеді,
--     қазір қолданып жүрген құрылғысына емес.
--
-- Қосымша әр ашылғанда (кемінде 10 минут сайын, `Push.onAppResumed`)
-- токенін `save_push_token` арқылы қайта бекітеді — `updated_at` жаңарады.
-- Демек 45 күн бойы жаңармаған токен — қолданылмайтын құрылғы. Оларды
-- күн сайын өшіреміз. Белсенді пайдаланушы қосымшаны ашқан сәтте токені
-- қайта тіркеледі, ештеңе жоғалмайды.

create or replace function public.purge_stale_push_tokens()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.push_tokens
   where coalesce(updated_at, created_at) < now() - interval '45 days';
$$;

revoke execute on function public.purge_stale_push_tokens()
  from public, anon, authenticated;

select public.purge_stale_push_tokens();

do $$ begin perform cron.unschedule('tasu-purge-stale-push-tokens');
exception when others then null; end $$;
select cron.schedule(
  'tasu-purge-stale-push-tokens',
  '41 3 * * *',
  'select public.purge_stale_push_tokens()'
);
