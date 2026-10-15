-- Tasu · 0072_support_contact.sql
-- Кіру/тіркелу беттеріндегі «Көмек» батырмасы (WhatsApp) нөмірін модератор
-- «Баптаулар» бетінен өзгертеді. Бұрын нөмір кодқа қатаң жазылған еді
-- (lib/core/env.dart → supportWhatsApp), ауыстыру үшін жаңа build керек
-- болатын.
--
-- Батырма КІРМЕГЕН адамға көрінеді (кіру/тіркелу), ал `app_settings`
-- кестесі тек authenticated-ке ашық — сондықтан нөмірді anon-ға беретін
-- жеке SECURITY DEFINER функция (`app_version_gate` сияқты). Ол ТЕК осы
-- бір кілтті қайтарады, басқа баптаулар (Kaspi, тариф т.б.) ашылмайды.

insert into public.app_settings (key, value)
values ('support_contact', jsonb_build_object('whatsapp', '77474005347'))
on conflict (key) do nothing;

create or replace function public.support_contact()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select value from public.app_settings where key = 'support_contact'),
    '{}'::jsonb
  );
$$;
revoke all on function public.support_contact() from public;
grant execute on function public.support_contact() to anon, authenticated;

create or replace function public.mod_update_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if p_key not in (
    'tariffs', 'payment', 'version_gate', 'order_min', 'vehicle_rules',
    'listings', 'taxi', 'topup_bot', 'support_bot', 'support', 'bonus',
    'repeat_order', 'pricing_hint', 'scheduled_orders', 'live_tracking',
    'share_trip', 'referral', 'news', 'support_contact'
  ) then
    raise exception 'BAD_KEY';
  end if;
  -- WhatsApp нөмірі: тек цифрлар, елдік кодпен (7XXXXXXXXXX). Қате нөмір
  -- сақталса, батырма бос/бөтен чатқа апарар еді.
  if p_key = 'support_contact'
     and coalesce(p_value->>'whatsapp', '') !~ '^[0-9]{10,15}$' then
    raise exception 'BAD_PHONE';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;
