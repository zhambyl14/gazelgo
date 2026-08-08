-- ============================================================
-- Tasu · 0064_referral_redeem_window.sql
-- ============================================================
-- ШАҚЫРУ КОДЫН ТІРКЕЛГЕН СОҢ ДА ЕНГІЗУГЕ БОЛАДЫ — БІРАҚ ҮЛГЕРУ КЕРЕК.
--
-- Пайдаланушы (2026-08-08) байқады: тіркелу экранында кодты жазуды ұмытқан
-- ЖАҢА адам профильдегі «Досыңыздың кодын енгізіңіз» өрісіне жаза алмай
-- жатыр. Ол ЖАҢА қолданушы — ондай адам кодты енгізе алуы КЕРЕК.
--
-- `redeem_referral_code` бұл жағдайды бұрыннан рұқсат етеді (шарты тек
-- `referred_by is null`) — сол себепті сервер жағында ТЫЙЫМ ЖОҚ, негізгі
-- ақау қосымша жағында болатын (өріс пен «Қолдану» батырмасы бір қатарда
-- қысылып тұрған әрі қате мәтіндері аударылмаған — түсініксіз
-- «PostgrestException(...)» шығатын).
--
-- ОСЫ МИГРАЦИЯДА ЖАСАЛАТЫНЫ — БІР ҒАНА НАҚТЫЛАУ: кодты БІРІНШІ ЗАКАЗЫҢ
-- АЯҚТАЛҒАНҒА ДЕЙІН енгізу керек. Себебі 0062-де сыйақы «шақырылған адам
-- 1-ші заказын аяқтағанда» беріледі (`v_done = 1` шарты). Демек бір заказды
-- бітіріп қойған адам кодты енгізсе — байланыс жасалады, бірақ сыйақы
-- ЕШҚАШАН төленбейді. Үнсіз «өлі» байланыс жасағанша, себебін АЙТҚАН
-- дұрыс: `REFERRAL_TOO_LATE`.
--
-- ЖАҢА қолданушыға (аяқталған заказы жоқ) ЕШТЕҢЕ ӨЗГЕРМЕЙДІ — ол баяғыдай
-- кодты кез келген уақытта енгізе береді.
--
-- ЕСКЕРТУ: идемпотентті, SQL Editor-да ҚОЛМЕН қолданылады. 0062-ден КЕЙІН.
-- ============================================================

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
  v_done int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select coalesce((value->>'enabled')::boolean, false) into v_enabled
    from public.app_settings where key = 'referral';
  if not coalesce(v_enabled, false) then raise exception 'DISABLED'; end if;

  if v_code = '' then raise exception 'BAD_CODE'; end if;

  if exists (
    select 1 from public.profiles where id = v_uid and referred_by is not null
  ) then
    raise exception 'ALREADY_REFERRED';
  end if;

  -- ТЕРЕЗЕ (0064): сыйақы 1-ші АЯҚТАЛҒАН заказда беріледі (0062), сондықтан
  -- заказын бітіріп қойған адамға байланыс жасаудың мәні жоқ — себебін
  -- айтамыз. Клиент те, орындаушы да есептеледі (қос рөл, 0046).
  select count(*) into v_done from public.orders
   where status = 'completed'
     and (client_id = v_uid or executor_id = v_uid);
  if v_done > 0 then raise exception 'REFERRAL_TOO_LATE'; end if;

  select id into v_referrer from public.profiles where referral_code = v_code;
  if v_referrer is null then raise exception 'BAD_CODE'; end if;
  if v_referrer = v_uid then raise exception 'SELF_REFERRAL'; end if;

  -- ТЕК байланыс. Санақ/бонус — шақырылған адам БІРІНШІ заказын
  -- аяқтағанда ғана (award_referral_rewards_if_due, order_advance ішінде).
  update public.profiles set referred_by = v_referrer where id = v_uid;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.redeem_referral_code(text) to authenticated;
