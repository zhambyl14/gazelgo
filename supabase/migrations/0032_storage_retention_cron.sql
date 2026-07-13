-- Tasu · 0032_storage_retention_cron.sql
-- Storage-ты фондық автоматты тазалау: экранды біреу ашуына тәуелді
-- client-side тазалау (0010, order_detail_screen.dart) жеткіліксіз —
-- ешкім ашпаса, файлдар мәңгі қалып, Storage толып кетуі мүмкін.
--
-- pg_cron күн сайын `cleanup-storage` edge function-ды шақырады
-- (supabase/functions/cleanup-storage/index.ts):
--   (1) 5+ күн бұрын ЖАБЫЛҒАН қолдау тредтерін — хабарламаларымен және
--       Storage суреттерімен қоса — толық өшіреді.
--   (2) 5+ күн бұрын аяқталған/бас тартылған/мерзімі өткен заказдардың
--       Storage-тағы жүк фотоларын өшіреді (заказдың өзі — тарих/дау
--       үшін — қалады, тек `photos` бос массивке ауыстырылады).
--
-- Секрет `push_trigger_secret`-пен бірдей тәртіппен (0025) `app_secrets`
-- кестесінде сақталады — database GUC Supabase хостингте рұқсат етілмейді.
-- Толық баптау: supabase/APPLY.md → «Storage тазалау (cron)».

create or replace function public.trigger_storage_cleanup()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
begin
  select value into v_secret from public.app_secrets where key = 'cron_cleanup_secret';
  if v_secret is null or v_secret = '' then
    return; -- әлі бапталмаса (секрет орнатылмаса) — үнсіз өтеді
  end if;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/cleanup-storage',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    body := '{}'::jsonb
  );
exception when others then
  -- cron шақыруы сәтсіз болса да дерекқорды бұзбауы керек
  null;
end;
$$;

do $$ begin
  perform cron.unschedule('tasu-storage-cleanup');
exception when others then null; end $$;
select cron.schedule(
  'tasu-storage-cleanup',
  '30 2 * * *',   -- күн сайын 02:30 (UTC) — түнде, жүктеме аз кезде
  $$select public.trigger_storage_cleanup();$$
);
