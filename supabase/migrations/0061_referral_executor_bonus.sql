-- ============================================================
-- Tasu · 0061_referral_executor_bonus.sql
-- ============================================================
-- 0060-да referral «тек ұпай/санақ» деп жасалған еді. Пайдаланушы
-- (2026-08-07, кейінгі сессия) нақтылады: ШАҚЫРУШЫ ОРЫНДАУШЫ болса —
-- балансына НАҚТЫ бонус түссін (модератор сомасын баптайды); шақырушы
-- КЛИЕНТ болса — бұрынғыдай тек санақ (клиентте wallet жоқ).
--
-- ЕСКЕРТУ: 0060 бұрын қолданылған болуы мүмкін — сол жағдайда
-- app_settings.referral жолы бар болып, `insert ... on conflict do
-- nothing` оны түртпес еді, сол себепті мұнда МЕРЖ (update ... value ||
-- jsonb_build_object(...)) арқылы жетпейтін кілтті қосамыз. Идемпотентті,
-- 0060 қолданылған/қолданылмаған екі жағдайда да қауіпсіз.
-- ============================================================

update public.app_settings
   set value = value || jsonb_build_object(
     'executor_bonus_amount',
     coalesce((value->>'executor_bonus_amount')::int, 200)
   )
 where key = 'referral';

insert into public.app_settings (key, value)
values ('referral', jsonb_build_object(
  'enabled', false, 'executor_bonus_amount', 200
))
on conflict (key) do nothing;

create or replace function public.redeem_referral_code(p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_referrer uuid;
  v_enabled boolean;
  v_bonus_amount bigint;
  v_referrer_is_exec boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select coalesce((value->>'enabled')::boolean, false),
         coalesce((value->>'executor_bonus_amount')::bigint, 200)
    into v_enabled, v_bonus_amount
    from public.app_settings where key = 'referral';
  if not coalesce(v_enabled, false) then raise exception 'DISABLED'; end if;

  if v_code = '' then raise exception 'BAD_CODE'; end if;

  if exists (
    select 1 from public.profiles where id = v_uid and referred_by is not null
  ) then
    raise exception 'ALREADY_REFERRED';
  end if;

  select id into v_referrer from public.profiles where referral_code = v_code;
  if v_referrer is null then raise exception 'BAD_CODE'; end if;
  if v_referrer = v_uid then raise exception 'SELF_REFERRAL'; end if;

  update public.profiles set referred_by = v_referrer where id = v_uid;
  update public.profiles set referral_count = referral_count + 1 where id = v_referrer;

  -- ШАҚЫРУШЫ ОРЫНДАУШЫ БОЛСА — БАЛАНСЫНА НАҚТЫ БОНУС (0061). Шақырушы
  -- клиент болса wallet жоқ болғандықтан тек referral_count қалады.
  select exists(
    select 1 from public.executor_profiles where user_id = v_referrer
  ) into v_referrer_is_exec;

  if v_referrer_is_exec and v_bonus_amount > 0 then
    update public.executor_profiles
       set balance = balance + v_bonus_amount
     where user_id = v_referrer;

    insert into public.balance_txns (executor_id, amount, type, note)
    values (v_referrer, v_bonus_amount, 'adjustment', 'Жаттыққа шақыру бонусы');

    perform public.send_push(
      'Шақыру бонусы! 🎁',
      'Досыңыз тіркелді. Балансыңызға ' || v_bonus_amount || ' ₸ қосылды.',
      jsonb_build_object('type', 'bonus'),
      array[v_referrer],
      'Бонус за приглашение! 🎁',
      'Ваш друг зарегистрировался. На баланс добавлено ' || v_bonus_amount || ' ₸.'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'executor_bonus', v_referrer_is_exec and v_bonus_amount > 0
  );
end;
$$;

grant execute on function public.redeem_referral_code(text) to authenticated;

-- Тіркелу экраны (0061) — қолданушы әлі КІРМЕГЕН (анон), сол себепті
-- app_settings кестесін тікелей оқи алмайды (RLS тек `authenticated`-ке
-- ашық). `board_enabled()`/`taxi_enabled()` үлгісімен бірдей: SECURITY
-- DEFINER арқылы RLS-ті айналып өтеді, тек ОСЫ БІР жалаушаны қайтарады.
create or replace function public.referral_enabled()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select (value->>'enabled')::boolean from public.app_settings where key = 'referral'),
    false);
$$;

grant execute on function public.referral_enabled() to anon, authenticated;
