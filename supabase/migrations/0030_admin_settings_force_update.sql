-- GazelGo · 0030_admin_settings_force_update.sql
-- Пайдаланушы сұрады: (1) тариф бағасы мен Kaspi деректерін модератор
-- панелінен ӨЗІ, SQL-сыз ауыстыра алсын; (2) App Store/Play Market-ке
-- жаңа нұсқа шыққанда, ескі нұсқадағы пайдаланушыларды МӘЖБҮРЛІ
-- жаңартуға шақыратын («force update») механизм.
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек.
-- 0029-дан КЕЙІН орындаңыз.

-- ============================================================
-- 1) version_gate баптауы — мәжбүрлі жаңарту
-- ============================================================
-- min_build=0 → тексеру ӨШІРУЛІ (әдепкі). Модератор Баптаулар табынан
-- сандарды толтырғанда ғана белсенді болады (PUBLISH.md → §0.2 қараңыз).
insert into public.app_settings (key, value) values
  ('version_gate', jsonb_build_object(
    'min_build', 0,
    'android_url', 'https://play.google.com/store/apps/details?id=kz.gazelgo.app',
    'ios_url', 'https://apps.apple.com/app/id0000000000',
    'message', 'Жаңа нұсқа шықты. Жалғастыру үшін қосымшаны жаңартыңыз.'
  ))
on conflict (key) do nothing;

-- Нұсқа тексеруі — АВТОРИЗАЦИЯСЫЗ да шақырылады (кіру экранында тұрған
-- ескі нұсқаны да бұғаттау үшін), сол себепті тек осы бір баптауды ғана
-- қайтарады (Kaspi/тариф сияқты құпия емес мәліметтерді ашпайды).
create or replace function public.app_version_gate()
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(value, '{}'::jsonb) from public.app_settings where key = 'version_gate';
$$;

grant execute on function public.app_version_gate() to anon, authenticated;

-- ============================================================
-- 2) Модератордың баптау экраны — тариф/Kaspi/жаңарту талабын жазуы
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
  if p_key not in ('tariffs', 'payment', 'version_gate', 'order_min', 'vehicle_rules') then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;
