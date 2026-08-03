-- ============================================================
-- Tasu · 0055_configurable_tariff_duration.sql
-- ============================================================
-- Тариф АУЫСЫМЫНЫҢ ҰЗАҚТЫҒЫН модератор өзі баптай алатын етеміз.
--
-- Бұрын: ауысым қатаң 12 сағат, сағат бойынша 08:00/20:00-ге тіркелген
-- (current_window_end() ішінде хардкод). Енді `app_settings.tariffs`
-- ішінде екі жаңа кілт:
--   duration_hours (int, әдепкі 12)  — ауысымның ұзақтығы (1..24 сағат)
--   duration_mode  (text, әдепкі 'fixed')
--     'fixed'   — САҒАТҚА ТІРКЕЛГЕН терезелер, 08:00-ден бастап циклмен
--                 қайталанады (duration_hours=12 → ескі 08:00–20:00 /
--                 20:00–08:00 қалпы өзгеріссіз; 24 → тәулігіне бір терезе,
--                 08:00–08:00).
--     'rolling' — сатып алған СӘТТЕН бастап +duration_hours (мыс. 24 сағ —
--                 «қосқан уақыттан 24 сағат»).
--
-- `mod_update_setting('tariffs', ...)` арқылы модератор бұл екеуін де
-- ЖАЛПЫ баға баптауымен бірге сақтай алады (кілт тізіміне өзгеріс керек
-- емес — 'tariffs' 0030-дан бері рұқсат етілген).
-- ============================================================

-- 1) Бар тарифке әдепкі мәндерді ҚОСАМЫЗ (бағаны сақтап, тек жетпейтін
--    кілттерді толтырамыз — merge, overwrite емес).
update public.app_settings
set value = value || '{"duration_hours": 12, "duration_mode": "fixed"}'::jsonb
where key = 'tariffs'
  and not (value ? 'duration_hours');

-- 2) current_window_end() — енді app_settings.tariffs-тен оқиды.
create or replace function public.current_window_end()
returns timestamptz
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  cfg      jsonb;
  mode     text;
  hours    numeric;
  loc      timestamp;
  anchor   timestamp;
  elapsed  numeric;
  windows_passed numeric;
  end_loc  timestamp;
begin
  select value into cfg from public.app_settings where key = 'tariffs';
  mode  := coalesce(cfg->>'duration_mode', 'fixed');
  hours := (cfg->>'duration_hours')::numeric;
  if hours is null or hours <= 0 or hours > 24 then hours := 12; end if;

  -- Сатып алған СӘТТЕН бастап +hours (клок торларына тәуелсіз).
  if mode = 'rolling' then
    return now() + (hours || ' hours')::interval;
  end if;

  -- САҒАТҚА ТІРКЕЛГЕН, ұзындығы `hours` циклдік терезелер, 08:00-ден
  -- бастап (hours=12 болғанда ескі 08:00–20:00 / 20:00–08:00 қалпы дәл
  -- сақталады).
  loc := now() at time zone 'Asia/Almaty';
  anchor := loc::date + time '08:00';
  if anchor > loc then anchor := anchor - interval '1 day'; end if;
  elapsed := extract(epoch from (loc - anchor)) / 3600;
  windows_passed := floor(elapsed / hours);
  end_loc := anchor + ((windows_passed + 1) * hours || ' hours')::interval;
  return end_loc at time zone 'Asia/Almaty';
end;
$$;
