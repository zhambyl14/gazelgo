-- ============================================================
-- Tasu · 0063_feed_preview_before_apply.sql
-- ============================================================
-- ЖАҢА ОРЫНДАУШЫ ӨТІНІМ ТОЛТЫРМАЙ ТҰРЫП ТА ЛЕНТАНЫ КӨРЕДІ.
--
-- Бұрынғы тәртіп: орындаушы рөліне ауысқан адам ЕҢ БІРІНШІ өтінім экранына
-- түсетін де, құжаттарын толтырмайынша қосымшаның ішін мүлдем көрмейтін
-- (`main.dart` → ExecutorApplyScreen). Ал `exec_can_see` де
-- `executor_profiles` жазбасы жоқ адамға `false` қайтаратын, `executor_stats`
-- болса `NOT_EXECUTOR` деп ҚАТЕ шығаратын — сондықтан экранды ашып қойған
-- күнде де лента бос/қатемен көрінер еді.
--
-- Бұл ДҰРЫС ЕМЕС: адам жүйеде өзіне лайық заказ бар-жоғын КӨРМЕЙ ТҰРЫП
-- құжат жинауға, көлік деректерін теруге мәжбүр болатын. Енді:
--   · өтінімі ЖОҚ орындаушы ТАНЫСУ РЕЖИМІНДЕ лентаны толық көреді —
--     көлік түрі де, қала да белгісіз болғандықтан СҮЗГІ ҚОЛДАНЫЛМАЙДЫ
--     (бәрі көрінеді, «мұнда қандай жұмыс бар» деген сұрақтың жауабы);
--   · бірақ ЕШТЕҢЕ ІСТЕЙ АЛМАЙДЫ — ұсыныс беру де, тариф сатып алу да
--     бұрынғыдай `exec_can_take`/`buy_tariff` ішінде бөгеледі (олар
--     `executor_profiles` жазбасын әрі `status = 'approved'` талап етеді,
--     ӨЗГЕРМЕЙДІ).
--
-- ҚОСА ТҮЗЕТІЛЕДІ: 0046-да қосылған «БЕЛСЕНДІ РӨЛ орындаушы болуы шарт»
-- тексерісі 0053/0060-та функция қайта жазылғанда БАЙҚАУСЫЗДА ТҮСІП
-- ҚАЛҒАН. Ол болмаса, өтінімсіз көрінуді қосқан бойда КЛИЕНТ рөліндегі
-- кез келген адам `executor_feed()` шақырып бүкіл заказды тізіп ала алар
-- еді. Тексеріс осында ҚАЙТА ОРНАТЫЛАДЫ.
--
-- ЕСКЕРТУ: идемпотентті, SQL Editor-да ҚОЛМЕН қолданылады (Supabase MCP
-- бұл сессияда авторизацияланбаған). 0060-тан КЕЙІН орындаңыз.
-- ============================================================

-- ============================================================
-- 1) exec_can_see — өтінімсіз орындаушыға «танысу режимі»
-- ============================================================
create or replace function public.exec_can_see(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
  exec_city text;
  o_from text;
  o_to   text;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' then return false; end if;
  -- Алдын ала тапсырыс (0060): уақыты жетпеген заказ лентада көрінбейді.
  if o.scheduled_at is not null and o.scheduled_at > now() then return false; end if;

  -- БЕЛСЕНДІ РӨЛ орындаушы болуы шарт (0046; 0053/0060-та түсіп қалған).
  -- Клиент режиміндегі адам лентаны да, «жаңа заказ» push-ын да алмайды.
  if not exists (select 1 from public.profiles
                  where id = p_exec and role = 'executor') then
    return false;
  end if;

  if o.client_id = p_exec then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;

  -- ТАНЫСУ РЕЖИМІ (0063): өтінім әлі толтырылмаған. Көлік түрі де, қала да
  -- белгісіз — сүзетін ештеңе жоқ, сондықтан лента ТОЛЫҚ көрсетіледі.
  -- Әрекет ету бәрібір `exec_can_take` ішінде бөгеледі.
  if not found then return true; end if;

  -- Бұдан әрі — өтінімі бар орындаушы. МАҚҰЛДАУ СТАТУСЫ ТЕКСЕРІЛМЕЙДІ
  -- (pending/rejected да лентаны толық көреді, тек ала алмайды).

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  -- ҚАЛА СҮЗГІСІ (0053): жергілікті заказ тек сол қаладағы орындаушыға
  -- КӨРІНЕДІ де. Межгород — бәріне. Қала бапталмаса — сүзгі жоқ.
  exec_city := public.norm_city(ep.city);
  o_from := public.norm_city(o.from_city);
  o_to   := public.norm_city(o.to_city);

  if exec_city is not null and o_from is not null
     and (o_to is null or o_from = o_to)  -- жергілікті (межгород емес)
     and exec_city <> o_from then
    return false;
  end if;

  return true;
end;
$$;

-- ============================================================
-- 2) executor_stats — өтінімсіз орындаушыға ҚАТЕ ЕМЕС, БОС күй
-- ============================================================
-- Бұл функция тек КӨРСЕТУ үшін оқылады (баланс таблеткасы, тариф картасы,
-- лента экранының жоғарғы жолағы). Өтінімі жоқ адамға `NOT_EXECUTOR` деп
-- қате шығарса — лента экраны түгелдей қате күйінде ашылатын. Енді нөлдік
-- көрсеткіштер қайтады да, экран қалыпты жұмыс істейді.
--
-- ЖАЗУ жасайтын функциялар (buy_tariff, set_on_line, set_order_push_enabled,
-- place_offer…) бұрынғыдай `NOT_EXECUTOR`/`NOT_APPROVED` шығарады —
-- олар ТИІСІЛМЕЙДІ.
create or replace function public.executor_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  ep record;
  v_day_start timestamptz;
  v_month_start timestamptz;
  v_today bigint;
  v_month bigint;
  v_left bigint;
  v_until timestamptz;
  v_trial timestamptz;
  v_price bigint;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  v_price := public.tariff_price_now('simple');

  select * into ep from public.executor_profiles where user_id = v_uid;
  if not found then
    -- ТАНЫСУ РЕЖИМІ: өтінім әлі жоқ. `no_profile` белгісі бойынша қосымша
    -- «Өтінім толтырыңыз» картасын көрсетеді.
    return jsonb_build_object(
      'no_profile', true,
      'balance', 0,
      'total_earned', 0,
      'today', 0,
      'month', 0,
      'busy_order_id', null,
      'orders_left', 0,
      'left', 0,
      'until', null,
      'trial_until', null,
      'has_tariff', false,
      'is_night', public.is_night_now(),
      'price', v_price,
      'vehicle_year', null,
      'vehicle_type', null,
      'on_line', false,
      'city', null,
      'simple_left', 0,
      'vip_left', 0,
      'simple_until', null,
      'vip_until', null,
      'simple_active', false,
      'vip_active', false,
      'price_simple', v_price,
      'price_vip', v_price
    );
  end if;

  v_day_start := date_trunc('day', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';

  select coalesce(sum(amount),0) into v_today from public.earnings
   where executor_id = v_uid and created_at >= v_day_start;
  select coalesce(sum(amount),0) into v_month from public.earnings
   where executor_id = v_uid and created_at >= v_month_start;

  select coalesce(sum(orders_left),0), max(expires_at)
    into v_left, v_until from public.tariff_sessions
   where executor_id = v_uid and not is_trial
     and coalesce(orders_left,0) > 0 and expires_at > now();
  select max(expires_at) into v_trial from public.tariff_sessions
   where executor_id = v_uid and is_trial and expires_at > now();

  return jsonb_build_object(
    'no_profile', false,
    'balance', ep.balance,
    'total_earned', ep.total_earned,
    'today', v_today,
    'month', v_month,
    'busy_order_id', ep.busy_order_id,
    'orders_left', v_left,
    'left', v_left,
    'until', v_until,
    'trial_until', v_trial,
    'has_tariff', public.exec_has_capacity(v_uid),
    'is_night', public.is_night_now(),
    'price', v_price,
    'vehicle_year', ep.vehicle_year,
    'vehicle_type', ep.vehicle_type,
    'on_line', ep.on_line,
    'city', ep.city,
    -- ескі кілттер (кері үйлесімділік):
    'simple_left', v_left,
    'vip_left', 0,
    'simple_until', v_until,
    'vip_until', null,
    'simple_active', public.exec_has_capacity(v_uid),
    'vip_active', false,
    'price_simple', v_price,
    'price_vip', v_price
  );
end;
$$;

grant execute on function public.executor_stats() to authenticated;
