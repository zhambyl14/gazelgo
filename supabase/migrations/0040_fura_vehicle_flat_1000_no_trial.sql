-- GazelGo · 0040_fura_vehicle_daily_tariff_no_trial.sql
-- Пайдаланушы сұраған өзгерістер:
--   1) ЖАҢА КӨЛІК ТҮРІ: «Фура» (fura) — ауыр жүк көлігі, 5–20 тонна.
--      executor_profiles/orders CHECK тізіміне + create_order валидациясына
--      'fura' қосылады.
--   2) ТАРИФ ТЕРЕЗЕСІ ӨЗГЕРІССІЗ: баяғы 12 сағаттық ауысым (08:00–20:00 не
--      20:00–08:00), сол ауысымда 10 заказға дейін. current_window_end()
--      бұрынғы (0001) күйінде қалады — бұл жерде оны ТИІСПЕЙМІЗ.
--   3) Тариф бағасы: бірыңғай 1000 ₸ (күндіз де, түнде де бірдей).
--   4) «Жаңа орындаушыларға 1 ай тегін» (триал) АЛЫНЫП ТАСТАЛДЫ:
--      grant_trial енді ешкімге триал бермейді; mod_set_executor_status
--      растағанда триал шақырмайды; ағымдағы белсенді триалдар жабылады.
--
-- ЕСКЕРТУ: бұл миграцияны Supabase → SQL Editor-да ҚОЛМЕН орындау керек.
-- 0039-дан КЕЙІН орындаңыз.

-- ============================================================
-- 1) «Фура» көлік түрін CHECK тізіміне қосу
-- ============================================================
alter table public.executor_profiles
  drop constraint if exists executor_profiles_vehicle_type_check;
alter table public.executor_profiles
  add constraint executor_profiles_vehicle_type_check check (vehicle_type in
    ('gazelle','furgon','kamaz','fura','crane','manipulator','assenizator',
     'excavator','loader','minivan','tractor'));

alter table public.orders
  drop constraint if exists orders_vehicle_type_check;
alter table public.orders
  add constraint orders_vehicle_type_check check (vehicle_type in
    ('gazelle','furgon','kamaz','fura','crane','manipulator','assenizator',
     'excavator','loader','minivan','tractor'));

-- ============================================================
-- 2) Тариф бағасы: бірыңғай 1000 ₸ (күн/түн бірдей)
-- ============================================================
insert into public.app_settings (key, value) values
  ('tariffs', '{"simple_day": 1000, "simple_night": 1000, "vip_day": 1000, "vip_night": 1000}')
on conflict (key) do update set value = excluded.value;

-- ============================================================
-- 3) Тариф терезесі: 12 сағаттық ауысым ӨЗГЕРІССІЗ (current_window_end
--    0001-дегі күйінде: 08:00–20:00 / 20:00–08:00). Мұнда ештеңе жасалмайды.
-- ============================================================

-- ============================================================
-- 4) Триалды алып тастау
-- ============================================================
-- 4.1 grant_trial енді ешкімге триал бермейді (толық no-op).
create or replace function public.grant_trial(p_exec uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- «1 ай тегін» кезеңі алынып тасталды — жаңа триал берілмейді.
  return;
end;
$$;
revoke execute on function public.grant_trial(uuid) from public, anon, authenticated;

-- 4.2 Растау кезінде триал шақырмайтын нұсқа (0013-тен, grant_trial-сыз).
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

  -- Растағанда триал БЕРІЛМЕЙДІ (алынып тасталды).

  if v_status = 'blocked' then
    update public.tariff_sessions set expires_at = now(), orders_left = 0
     where executor_id = p_user
       and ((is_trial and expires_at > now()) or (not is_trial and coalesce(orders_left,0) > 0));
  end if;
end;
$$;

-- 4.3 Ағымдағы белсенді триалдарды жабу (бірыңғай ақылы модель).
update public.tariff_sessions
   set expires_at = now()
 where is_trial and expires_at > now();

-- ============================================================
-- 5) create_order — 'fura' валидацияға қосылды (қалғаны 0029-дай)
-- ============================================================
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text,text,text);

create function public.create_order(
  p_type text,
  p_from_address text, p_from_lat float8, p_from_lng float8,
  p_to_address text,   p_to_lat float8,   p_to_lng float8,
  p_distance_km numeric,
  p_cargo text, p_comment text,
  p_size text,
  p_client_price bigint default null,
  p_photos text[] default '{}',
  p_from_city text default null,
  p_to_city text default null,
  p_tariff text default 'simple',
  p_vehicle_type text default 'gazelle'
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_vehicle text;
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

  v_vehicle := coalesce(nullif(trim(p_vehicle_type),''), 'gazelle');
  if v_vehicle not in ('gazelle','furgon','kamaz','fura','crane','manipulator',
                       'assenizator','excavator','loader','minivan','tractor') then
    raise exception 'BAD_VEHICLE_TYPE';
  end if;

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
    (client_id, type, tariff, vehicle_type, from_address, from_lat, from_lng, from_city,
     to_address, to_lat, to_lng, to_city, distance_km, cargo_desc, comment, size,
     client_price, system_price, photos)
  values
    (v_uid, 'bidding', 'simple', v_vehicle,
     trim(p_from_address), p_from_lat, p_from_lng, v_from_city,
     trim(p_to_address), p_to_lat, p_to_lng, v_to_city, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), 'small',
     p_client_price, null, coalesce(p_photos, '{}'))
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'intercity', v_intercity,
                            'vehicle_type', v_vehicle);
end;
$$;

grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,
  text[],text,text,text,text) to authenticated;
