-- ============================================================
-- Tasu · 0058_support_autoclose_and_new_badges.sql
-- ============================================================
-- ҮШ ӨЗГЕРІС (0057-ден КЕЙІН орындаңыз, идемпотентті):
--
-- A) ҚОЛДАУ ЧАТЫ 20 МИНУТТАН СОҢ АВТОМАТТЫ ЖАБЫЛАДЫ.
--    Бұрын `auto_close_support()` (0006) чатты тек МОДЕРАТОР соңғы жазып,
--    пайдаланушы 24 САҒАТ үнсіз болғанда ғана жабатын — сол себепті
--    пайдаланушы соңғы жазған тредтер (яғни жауап күтіп тұрғандардың бәрі)
--    ЕШҚАШАН жабылмай, «ашық сессия» болып мәңгі жиналып қалатын.
--    Енді: ЕКІ ТАРАПТЫҢ БІРІ де N минут (әдепкі 20) жазбаса — чат жабылады,
--    кім соңғы жазғанына қарамай. Пайдаланушы қайта жазса, чат өзі қайта
--    ашылады (`support_send`/`support_reply` `status = 'open'` қояды), яғни
--    ештеңе жоғалмайды.
--    Мерзімі — `app_settings.support.auto_close_minutes` арқылы бапталады.
--
-- B) «ЖАҢА» БЕЛГІЛЕРІН МОДЕРАТОР БАСҚАРАДЫ.
--    Клиенттің басты бетіндегі «Такси (ЖАҢА)» плиткасы мен sidebar-дағы
--    «Хабарландырулар (Жаңа)» картасындағы белгі бұрын КОДТА қатып тұрған
--    еді — фича ескіргенде де «жаңа» болып қала беретін. Енді екеуі де
--    `app_settings.<key>.new_badge` арқылы Модератор → Баптаулардан
--    бөлек-бөлек өшіріледі/қосылады. Әдепкі — көрінеді (баяғы қалып).
--
-- C) `mod_update_setting` жаңа `support` кілтін қабылдайды.
-- ============================================================


-- ============================================================
-- 1) Жаңа/толықтырылған баптаулар
-- ============================================================
insert into public.app_settings (key, value) values (
  'support',
  '{"auto_close_minutes": 20}'::jsonb
) on conflict (key) do nothing;

-- Бар жазбаларға `new_badge` кілтін ҚОСАМЫЗ, бірақ ҮСТІНЕН ЖАЗБАЙМЫЗ:
-- `||`-де ОҢ жақ басым, сол себепті модератор бұрын өшіріп қойған болса
-- (миграция қайта орындалса да) ол мән сол күйінде қалады.
update public.app_settings
   set value = jsonb_build_object('new_badge', true) || value
 where key in ('listings', 'taxi');


-- ============================================================
-- 2) mod_update_setting — `support` кілті қосылды
-- ============================================================
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
                   'support_bot', 'support') then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;


-- ============================================================
-- 3) «ЖАҢА» белгілері — қосымша оқитын жалғыз RPC
-- ============================================================
-- Екеуі БІР сұраныспен келеді (әр белгі үшін бөлек RPC артық трафик еді).
-- Кілт/мән жоқ болса — `true`, яғни ЕШТЕҢЕ БАПТАЛМАҒАН серверде белгілер
-- баяғыдай көрінеді (fail-open: жаңа фичаны байқаусыз жасырып алмаймыз).
create or replace function public.new_badges()
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'board', coalesce(
      (select (value->>'new_badge')::boolean from public.app_settings
        where key = 'listings'), true),
    'taxi', coalesce(
      (select (value->>'new_badge')::boolean from public.app_settings
        where key = 'taxi'), true)
  );
$$;

grant execute on function public.new_badges() to anon, authenticated;


-- ============================================================
-- 4) Қолдау чатының автоматты жабылуы (ЕКІ ТАРАП ТА үнсіз болса)
-- ============================================================
create or replace function public.auto_close_support()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_minutes int;
begin
  select (value->>'auto_close_minutes')::int into v_minutes
    from public.app_settings where key = 'support';
  -- Баптау жоқ/бүлінген болса да чат ілініп қалмауы керек → әдепкі 20.
  -- Төменгі шек 1 минут: 0 не теріс мән қойылса, ЖАҢА ҒАНА жазылған чат
  -- бірден жабылып, пайдаланушы жауап ала алмай қалар еді.
  v_minutes := greatest(1, coalesce(v_minutes, 20));

  -- `last_msg_at`-ты екі тарап та (пайдаланушы да, модератор да, бот та)
  -- жазғанда жаңартады — демек бұл «соңғы қимылдан бері» деген уақыт.
  -- `closed_by` ӘДЕЙІ null: чатты адам емес, жүйе жапқанын білдіреді.
  update public.support_threads
     set status = 'closed', closed_at = now()
   where status = 'open'
     and last_msg_at < now() - make_interval(mins => v_minutes);
end;
$$;

revoke execute on function public.auto_close_support() from public, anon, authenticated;


-- ============================================================
-- 5) Cron — 5 минут сайын (бұрын 30)
-- ============================================================
-- 20 минуттық мерзімді 30 минуттық cron тексерсе, чат нақтысында 20-50
-- минут аралығында жабылатын еді. 5 минутта — қателік ең көбі 5 минут.
do $$
begin
  perform cron.unschedule('gazelgo-auto-close-support');
exception when others then null;
end $$;

select cron.schedule('gazelgo-auto-close-support', '*/5 * * * *',
  $$select public.auto_close_support()$$);

-- Қазір ілініп қалған ескі «ашық» тредтерді бірден жабады.
select public.auto_close_support();
