-- GazelGo · 0013_spec_economy.sql
-- Тариф/заказ экономикасын спецификацияға сай толық қайта құру:
--   §1 Тариф бағасы: Простой 200/150, VIP 400/200 (күн/түн).
--   §2 Минимум баға: қала ішінде 100 ₸, межгород 1000 ₸.
--   §3 VIP-те авто-баға да, авто-қабылдау да ЖОҚ — барлық заказ клиент баға
--       қоятын bidding. «instant» режимі жасалмайды (объектілер қалады, бірақ
--       қолданылмайды — кері үйлесімділік үшін).
--   §4 Тариф = 10 заказ пакеті. Әр қабылданған заказ −1. 0 болса — қайта сатып алу.
--   §5 Межгород маршрутымен қосымша заказ алу (Тараз→Алматы алса, Шу→Алматы да
--       көрінеді әрі алуға болады; әрқайсысы да −1).
--   §6 Газелист тек өз қаласынан ШЫҒАТЫН заказдарды көреді (қала ішінде + сол
--       қаладан шығатын межгород).
--   §7 Жаңа расталған газелиске 24 сағат тегін тариф (шексіз заказ).
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек.

-- ============================================================
-- 0) Схема өзгерістері
-- ============================================================
alter table public.executor_profiles
  add column if not exists city text;
alter table public.executor_profiles
  add column if not exists trial_granted boolean not null default false;

alter table public.tariff_sessions
  add column if not exists orders_left integer;          -- null = шексіз (тегін триал)
alter table public.tariff_sessions
  add column if not exists is_trial boolean not null default false;

-- guard: city-ді орындаушы өзі өзгерте алады, ал trial_granted тек сервер
create or replace function public.guard_executor_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    new.updated_at := now();
    return new;
  end if;
  if new.balance is distinct from old.balance
     or new.total_earned is distinct from old.total_earned
     or new.busy_order_id is distinct from old.busy_order_id
     or new.moderated_by is distinct from old.moderated_by
     or new.moderated_at is distinct from old.moderated_at
     or new.moderation_comment is distinct from old.moderation_comment
     or new.docs_update_requested is distinct from old.docs_update_requested
     or new.docs_update_comment is distinct from old.docs_update_comment
     or new.docs_update_fields is distinct from old.docs_update_fields
     or new.docs_review_pending is distinct from old.docs_review_pending
     or new.trial_granted is distinct from old.trial_granted then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  if new.status is distinct from old.status
     and not (old.status = 'rejected' and new.status = 'pending') then
    raise exception 'FORBIDDEN_STATUS';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================
-- 1) §1 Тариф бағалары (күн/түн бөлек)
-- ============================================================
insert into public.app_settings (key, value) values
  ('tariffs', '{"simple_day": 200, "simple_night": 150, "vip_day": 400, "vip_night": 200}'),
  ('order_min', '{"city": 100, "intercity": 1000}')
on conflict (key) do update set value = excluded.value;

-- Тарифтің қазіргі бағасы (күн/түн — тарифке бөлек мәндер)
create or replace function public.tariff_price_now(p_kind text)
returns bigint
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  cfg jsonb;
  night boolean := public.is_night_now();
  v bigint;
begin
  select value into cfg from public.app_settings where key = 'tariffs';
  if cfg is null then raise exception 'SETTINGS_MISSING'; end if;
  if p_kind = 'simple' then
    v := (cfg->>(case when night then 'simple_night' else 'simple_day' end))::bigint;
  elsif p_kind = 'vip' then
    v := (cfg->>(case when night then 'vip_night' else 'vip_day' end))::bigint;
  else
    raise exception 'BAD_TARIFF';
  end if;
  return v;
end;
$$;

-- ============================================================
-- 2) Көмекшілер: қаланы нормалау, сыйымдылық, маршрут
-- ============================================================

-- Қала атауын салыстыруға дайындау (әкімшілік жұрнақтарды алып тастау).
-- Dart-тағы Geo.normalizeCity-мен үйлеседі.
create or replace function public.norm_city(p text)
returns text
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  s text;
  suf text;
  sufs text[] := array[
    'қалалық әкімшілігі','қаласының әкімшілігі','городская администрация',
    'администрация города','әкімшілігі','қаласы','ауданы','облысы',
    'селолық округі','ауылдық округі','города','город','ауылы','село','с.'];
  changed boolean := true;
begin
  if p is null then return null; end if;
  s := lower(btrim(p));
  if position(',' in s) > 0 then
    s := btrim(split_part(s, ',', 1));   -- «Тараз, Тараз ГА» → «тараз»
  end if;
  while changed loop
    changed := false;
    foreach suf in array sufs loop
      if s like ('%' || suf) then
        s := btrim(left(s, length(s) - length(suf)));
        changed := true;
      end if;
    end loop;
  end loop;
  return nullif(s, '');
end;
$$;

-- Орындаушыда белсенді тариф (не заказ орны) бар ма?
create or replace function public.exec_has_capacity(p_exec uuid)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tariff_sessions
    where executor_id = p_exec
      and ((is_trial and expires_at > now())
        or (not is_trial and coalesce(orders_left, 0) > 0))
  );
$$;

-- Тегін триал белсенді ме (осы кезде заказ санынан шегерілмейді)?
create or replace function public.exec_trial_active(p_exec uuid)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tariff_sessions
    where executor_id = p_exec and is_trial and expires_at > now()
  );
$$;

-- Орындаушы осы заказды ала ала ма? §5/§6 логикасының жалғыз көзі.
create or replace function public.exec_can_take(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
  exec_city text;
  o_from text; o_to text;
  o_intercity boolean;
  has_active boolean;
  base_visible boolean;
  route_visible boolean;
  can_stack boolean;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' or o.type <> 'bidding' then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found or ep.status <> 'approved' then return false; end if;
  if o.size <> ep.vehicle_size then return false; end if;
  if o.client_id = p_exec then return false; end if;

  exec_city := public.norm_city(ep.city);
  o_from := public.norm_city(o.from_city);
  o_to   := public.norm_city(o.to_city);
  o_intercity := (o_from is not null and o_to is not null and o_from <> o_to);

  -- §6 базалық көріну: заказ орындаушының қаласынан шығады
  -- (қаласы белгісіз болса — уақытша бәрін көрсетеміз, әйтпесе жаңа орындаушы
  --  қаласын таңдағанша ешнәрсе көре алмас еді).
  base_visible := (exec_city is null) or (o_from is not null and o_from = exec_city);

  -- Орындаушының белсенді (аяқталмаған) заказдары
  has_active := exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit'));

  -- §5 маршрутпен көріну: орындаушы қазір межгород жолда болса (→ Қала T),
  -- сол T-ға баратын басқа межгород заказдар да көрінеді (Шу→Алматы т.б.).
  route_visible := o_intercity and exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit')
      and public.norm_city(a.from_city) is not null
      and public.norm_city(a.to_city) is not null
      and public.norm_city(a.from_city) <> public.norm_city(a.to_city)
      and public.norm_city(a.to_city) = o_to);

  if not (base_visible or route_visible) then return false; end if;

  -- Бос болса — ала алады
  if not has_active then return true; end if;

  -- Бос емес: тек межгород маршрутын жалғастыруға рұқсат (§5), әйтпесе бос емес.
  can_stack := o_intercity and exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit')
      and public.norm_city(a.from_city) is not null
      and public.norm_city(a.to_city) is not null
      and public.norm_city(a.from_city) <> public.norm_city(a.to_city)
      and (public.norm_city(a.to_city) = o_to
        or public.norm_city(a.from_city) = o_from));
  return can_stack;
end;
$$;

-- Заказ қабылданғанда тариф лимитінен 1 шегеру (триал болса — тегін).
create or replace function public.consume_order(p_exec uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if public.exec_trial_active(p_exec) then
    return;  -- 24 сағат тегін — шегерілмейді
  end if;
  select id into v_id from public.tariff_sessions
   where executor_id = p_exec and not is_trial and coalesce(orders_left,0) > 0
   order by orders_left asc, started_at asc
   limit 1;
  if v_id is not null then
    update public.tariff_sessions set orders_left = orders_left - 1 where id = v_id;
  end if;
end;
$$;

-- Тегін триал беру (бір рет, расталған сәтте).
create or replace function public.grant_trial(p_exec uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare ep record;
begin
  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found or ep.trial_granted then return; end if;
  insert into public.tariff_sessions
    (executor_id, kind, fee, is_night, is_trial, orders_left, started_at, expires_at)
  values
    (p_exec, 'simple', 0, public.is_night_now(), true, null, now(), now() + interval '24 hours');
  update public.executor_profiles set trial_granted = true where user_id = p_exec;
end;
$$;

-- ============================================================
-- 3) §4 Тариф сатып алу — 10 заказ пакеті (уақыт емес)
-- ============================================================
create or replace function public.buy_tariff(p_kind text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_kind public.tariff_kind;
  ep record;
  v_price bigint;
  v_session uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_kind := p_kind::public.tariff_kind;

  select * into ep from public.executor_profiles where user_id = v_uid for update;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  v_price := public.tariff_price_now(p_kind);
  if ep.balance < v_price then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.executor_profiles set balance = balance - v_price where user_id = v_uid;

  insert into public.balance_txns (executor_id, amount, type, note)
  values (v_uid, -v_price, 'tariff_fee',
          case when v_kind = 'simple' then 'Қарапайым тариф (10 заказ)'
               else 'VIP тариф (10 заказ)' end);

  -- Уақытпен бітпейді → expires_at алысқа қойылады; белсенділік orders_left-пен.
  insert into public.tariff_sessions
    (executor_id, kind, fee, is_night, is_trial, orders_left, started_at, expires_at)
  values
    (v_uid, v_kind, v_price, public.is_night_now(), false, 10, now(), now() + interval '3650 days')
  returning id into v_session;

  return jsonb_build_object('session_id', v_session, 'fee', v_price, 'orders_left', 10);
end;
$$;

-- ============================================================
-- 4) §1–§3 Заказ құру — тек bidding + межгород минимумы
-- ============================================================
create or replace function public.create_order(
  p_type text,
  p_from_address text, p_from_lat float8, p_from_lng float8,
  p_to_address text,   p_to_lat float8,   p_to_lng float8,
  p_distance_km numeric,
  p_cargo text, p_comment text,
  p_size text,
  p_client_price bigint default null,
  p_photos text[] default '{}',
  p_from_city text default null,
  p_to_city text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_size public.vehicle_size;
  v_id uuid;
  v_active int;
  v_intercity boolean;
  v_min bigint;
  v_from_city text;
  v_to_city text;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'client') then
    raise exception 'NOT_CLIENT';
  end if;

  v_size := p_size::public.vehicle_size;

  if coalesce(trim(p_from_address),'') = '' or coalesce(trim(p_to_address),'') = ''
     or coalesce(trim(p_cargo),'') = '' then
    raise exception 'BAD_INPUT';
  end if;

  if p_from_lat < 40 or p_from_lat > 56 or p_from_lng < 46 or p_from_lng > 88
     or p_to_lat < 40 or p_to_lat > 56 or p_to_lng < 46 or p_to_lng > 88 then
    raise exception 'OUT_OF_KZ';
  end if;

  select count(*) into v_active from public.orders
  where client_id = v_uid
    and status in ('searching','accepted','arrived','loading','in_transit');
  if v_active >= 5 then raise exception 'TOO_MANY_ACTIVE'; end if;

  v_from_city := nullif(trim(coalesce(p_from_city,'')),'');
  v_to_city   := nullif(trim(coalesce(p_to_city,'')),'');

  -- §2/§3: барлық заказ — клиент бағасы (bidding). Межгород болса минимум 1000.
  v_intercity := (public.norm_city(v_from_city) is not null
                  and public.norm_city(v_to_city) is not null
                  and public.norm_city(v_from_city) <> public.norm_city(v_to_city));
  select coalesce((value->>(case when v_intercity then 'intercity' else 'city' end))::bigint,
                  case when v_intercity then 1000 else 100 end)
    into v_min from public.app_settings where key = 'order_min';
  v_min := coalesce(v_min, case when v_intercity then 1000 else 100 end);

  if p_client_price is null or p_client_price < v_min then
    if v_intercity then raise exception 'MIN_INTERCITY';
    else raise exception 'MIN_CITY'; end if;
  end if;

  insert into public.orders
    (client_id, type, from_address, from_lat, from_lng, from_city,
     to_address, to_lat, to_lng, to_city, distance_km, cargo_desc, comment, size,
     client_price, system_price, photos)
  values
    (v_uid, 'bidding', trim(p_from_address), p_from_lat, p_from_lng, v_from_city,
     trim(p_to_address), p_to_lat, p_to_lng, v_to_city, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), v_size,
     p_client_price, null, coalesce(p_photos, '{}'))
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'intercity', v_intercity, 'min', v_min);
end;
$$;

-- ============================================================
-- 5) §4–§6 Ұсыныс беру — тариф лимиті + қала/маршрут фильтрі
-- ============================================================
create or replace function public.place_offer(p_order uuid, p_price bigint, p_message text default '')
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  ep record;
  v_existing record;
  v_id uuid;
  v_intercity boolean;
  v_min bigint;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into ep from public.executor_profiles where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  -- §4: белсенді тариф (не триал) керек
  if not public.exec_has_capacity(v_uid) then raise exception 'NO_ORDERS_LEFT'; end if;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.type <> 'bidding' or o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  -- §5/§6: қала мен маршрут ережесі (бос емес болса тек межгород жалғасы)
  if not public.exec_can_take(v_uid, p_order) then raise exception 'NOT_ELIGIBLE'; end if;

  -- §2: минимум баға
  v_intercity := (public.norm_city(o.from_city) is not null
                  and public.norm_city(o.to_city) is not null
                  and public.norm_city(o.from_city) <> public.norm_city(o.to_city));
  select coalesce((value->>(case when v_intercity then 'intercity' else 'city' end))::bigint,
                  case when v_intercity then 1000 else 100 end)
    into v_min from public.app_settings where key = 'order_min';
  v_min := coalesce(v_min, case when v_intercity then 1000 else 100 end);
  if p_price is null or p_price < v_min then
    if v_intercity then raise exception 'MIN_INTERCITY';
    else raise exception 'MIN_CITY'; end if;
  end if;

  select * into v_existing from public.offers
  where order_id = p_order and executor_id = v_uid for update;

  if found then
    if v_existing.status = 'accepted' then raise exception 'ALREADY_ACCEPTED'; end if;
    update public.offers
       set price = p_price, message = coalesce(trim(p_message),''),
           status = 'pending', created_at = now()
     where id = v_existing.id;
    return v_existing.id;
  end if;

  insert into public.offers (order_id, executor_id, price, message)
  values (p_order, v_uid, p_price, coalesce(trim(p_message),''))
  returning id into v_id;
  return v_id;
end;
$$;

-- ============================================================
-- 6) §4 Ұсынысты қабылдау — лимиттен шегеру
-- ============================================================
create or replace function public.accept_offer(p_offer uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order_id uuid;
  o record;
  ofr record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select order_id into v_order_id from public.offers where id = p_offer;
  if v_order_id is null then raise exception 'NOT_FOUND'; end if;

  select * into o from public.orders where id = v_order_id for update;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  select * into ofr from public.offers where id = p_offer for update;
  if ofr.status <> 'pending' then raise exception 'OFFER_GONE'; end if;

  -- Орындаушы әлі де ала ала ма (лимит + қала/маршрут) — қайта тексереміз
  if not public.exec_has_capacity(ofr.executor_id) then raise exception 'EXEC_NO_ORDERS'; end if;
  if not public.exec_can_take(ofr.executor_id, v_order_id) then raise exception 'EXEC_BUSY'; end if;

  update public.offers set status = 'accepted' where id = p_offer;
  update public.offers set status = 'rejected'
   where order_id = v_order_id and id <> p_offer and status = 'pending';
  update public.orders
     set executor_id = ofr.executor_id, final_price = ofr.price,
         status = 'accepted', accepted_at = now()
   where id = v_order_id;
  update public.executor_profiles set busy_order_id = v_order_id
   where user_id = ofr.executor_id;

  -- §4: лимиттен 1 шегеру (триал болса тегін)
  perform public.consume_order(ofr.executor_id);

  return jsonb_build_object('order_id', v_order_id, 'executor_id', ofr.executor_id);
end;
$$;

-- ============================================================
-- 7) §6/§5 Орындаушы лентасы — RPC (қала/маршрут фильтрі бірыңғай логикадан)
-- ============================================================
create or replace function public.executor_feed()
returns setof public.orders
language sql stable security definer
set search_path = public, pg_temp
as $$
  select o.*
  from public.orders o
  where o.status = 'searching'
    and o.type = 'bidding'
    and public.exec_can_take(auth.uid(), o.id)
  order by o.created_at desc
  limit 100;
$$;

-- ============================================================
-- 8) §4/§7 executor_stats — orders_left, trial_until, has_tariff
-- ============================================================
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
  v_orders_left bigint;
  v_trial timestamptz;
  v_simple boolean;
  v_vip boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into ep from public.executor_profiles where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;

  v_day_start := date_trunc('day', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';
  v_month_start := date_trunc('month', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';

  select coalesce(sum(amount),0) into v_today from public.earnings
   where executor_id = v_uid and created_at >= v_day_start;
  select coalesce(sum(amount),0) into v_month from public.earnings
   where executor_id = v_uid and created_at >= v_month_start;

  select coalesce(sum(orders_left),0) into v_orders_left from public.tariff_sessions
   where executor_id = v_uid and not is_trial and coalesce(orders_left,0) > 0;
  select max(expires_at) into v_trial from public.tariff_sessions
   where executor_id = v_uid and is_trial and expires_at > now();

  v_simple := exists (select 1 from public.tariff_sessions
                      where executor_id = v_uid and kind = 'simple'
                        and not is_trial and coalesce(orders_left,0) > 0);
  v_vip := exists (select 1 from public.tariff_sessions
                   where executor_id = v_uid and kind = 'vip'
                     and not is_trial and coalesce(orders_left,0) > 0);

  return jsonb_build_object(
    'balance', ep.balance,
    'total_earned', ep.total_earned,
    'today', v_today,
    'month', v_month,
    'busy_order_id', ep.busy_order_id,
    'orders_left', v_orders_left,
    'trial_until', v_trial,
    'has_tariff', public.exec_has_capacity(v_uid),
    'simple_active', v_simple,
    'vip_active', v_vip,
    'is_night', public.is_night_now(),
    'price_simple', public.tariff_price_now('simple'),
    'price_vip', public.tariff_price_now('vip'),
    'on_line', ep.on_line,
    'city', ep.city
  );
end;
$$;

-- ============================================================
-- 9) §7 Расталған сәтте тегін триал беру
-- ============================================================
create or replace function public.mod_set_executor_status(p_user uuid, p_status text, p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_status public.executor_status;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  v_status := p_status::public.executor_status;
  if v_status not in ('approved','rejected','blocked') then raise exception 'BAD_STATUS'; end if;

  update public.executor_profiles
     set status = v_status,
         moderation_comment = nullif(trim(coalesce(p_comment,'')),''),
         moderated_by = v_uid,
         moderated_at = now()
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;

  if v_status = 'approved' then
    perform public.grant_trial(p_user);   -- §7: бір рет 24 сағат тегін
  end if;

  if v_status = 'blocked' then
    update public.tariff_sessions set expires_at = now(), orders_left = 0
     where executor_id = p_user
       and ((is_trial and expires_at > now()) or (not is_trial and coalesce(orders_left,0) > 0));
  end if;
end;
$$;

-- ============================================================
-- 10) §6 Орындаушының қаласын орнату
-- ============================================================
create or replace function public.set_executor_city(p_city text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  update public.executor_profiles set city = nullif(trim(coalesce(p_city,'')),'')
   where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

-- ============================================================
-- 11) Grants + instant авто-таратуды өшіру
-- ============================================================
revoke execute on function public.exec_can_take(uuid,uuid) from public, anon, authenticated;
revoke execute on function public.exec_has_capacity(uuid) from public, anon, authenticated;
revoke execute on function public.exec_trial_active(uuid) from public, anon, authenticated;
revoke execute on function public.consume_order(uuid) from public, anon, authenticated;
revoke execute on function public.grant_trial(uuid) from public, anon, authenticated;
revoke execute on function public.norm_city(text) from public, anon;

grant execute on function public.buy_tariff(text) to authenticated;
grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text) to authenticated;
grant execute on function public.place_offer(uuid,bigint,text) to authenticated;
grant execute on function public.accept_offer(uuid) to authenticated;
grant execute on function public.executor_feed() to authenticated;
grant execute on function public.executor_stats() to authenticated;
grant execute on function public.mod_set_executor_status(uuid,text,text) to authenticated;
grant execute on function public.set_executor_city(text) to authenticated;
grant execute on function public.tariff_price_now(text) to authenticated;

-- instant авто-тарату кроны керек емес (жаңа instant заказ жасалмайды)
do $$ begin perform cron.unschedule('gazelgo-vip-advance');
exception when others then null; end $$;
