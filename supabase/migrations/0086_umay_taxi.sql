-- ============================================================
-- Tasu · 0086_umay_taxi.sql
-- ============================================================
-- «ҰМАЙ ТАКСИ»: Такси бөліміндегі қосымша түр — заказдарды ТЕК әйел
-- жүргізушілер орындайды (әйелдер мен кішкентай балаларды тасиды).
-- Атауын модератор баптаудан өзгерте алады, бастапқыда «Ұмай такси».
--
--   * vehicle_types — жаңа жол 'umay' (is_taxi = true, built_in = true,
--     sort_order 15: «Такси» мен «Жеткізу» арасында). БАСТАПҚЫДА ӨШІК
--     (active = false): модератор алдымен әйел жүргізушілерді белгілеп,
--     содан кейін Баптау → Ұмай бөлімінен қосады. ON CONFLICT DO NOTHING —
--     модератор кейін өзгерткен атау/мәтін/қосулы күйі ешқашан үстінен
--     жазылмайды.
--   * executor_profiles.is_umay — әйел жүргізуші белгісі. Оны ТЕК
--     'executors' рұқсаты бар модератор қояды (mod_set_executor_umay);
--     орындаушы өзі өзгерте алмайды: UPDATE-те guard_executor_profiles,
--     жаңа өтінімде (INSERT) guard_executor_profiles_insert.
--   * exec_can_see — 'umay' заказы тек is_umay жүргізушіге (көлігі
--     'taxi') көрінеді. Тексеру «профильсіз танысу режимінен» ӘЛДЕҚАЛАЙ
--     БҰРЫН орындалады. Лента, push, escalate_waiting_orders,
--     exec_can_take және place_offer — бәрі осы функция арқылы өтеді.
--     Әдеттегі 'taxi' заказдары Ұмай жүргізушісіне бұрынғыдай көрінеді.
--   * orders_feed RLS — Ұмай емес орындаушы 'umay' заказын тікелей
--     select-пен де көре алмайды.
--   * nearby_executors — p_vehicle = 'umay' болса: көлігі 'taxi' әрі
--     is_umay орындаушылар.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0085-тен кейін).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Әйел жүргізуші белгісі
-- ------------------------------------------------------------
alter table public.executor_profiles
  add column if not exists is_umay boolean not null default false;

comment on column public.executor_profiles.is_umay is
  'Әйел жүргізуші: Ұмай такси заказдарын да көреді (тек модератор қояды, 0086)';

-- ------------------------------------------------------------
-- 2) 'umay' көлік түрі (бастапқыда өшік)
-- ------------------------------------------------------------
insert into public.vehicle_types
  (code, label_kk, label_ru, desc_kk, desc_ru, emoji,
   sort_order, is_taxi, active, built_in)
values
  ('umay', 'Ұмай такси', 'Умай такси',
   'Тек әйел жүргізушілер · әйелдер мен балаларға',
   'Только женщины-водители · для женщин и детей',
   '🌸', 15, true, false, true)
on conflict (code) do nothing;

-- ------------------------------------------------------------
-- 3) guard_executor_profiles — 0013 нұсқасы + is_umay тыйым
-- ------------------------------------------------------------
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
     or new.trial_granted is distinct from old.trial_granted
     or new.is_umay is distinct from old.is_umay then
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

-- Жаңа өтінім (INSERT) арқылы да белгіні өзіне қоя алмасын: UPDATE
-- қорғанысы INSERT-ке әсер етпейді, ал exec_insert_own саясаты бағандарды
-- шектемейді. Тек сервер (service_role) не SECURITY DEFINER RPC қоя алады.
create or replace function public.guard_executor_profiles_insert()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user not in ('postgres','service_role','supabase_admin') then
    new.is_umay := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_executor_profiles_insert on public.executor_profiles;
create trigger trg_guard_executor_profiles_insert
  before insert on public.executor_profiles
  for each row execute function public.guard_executor_profiles_insert();

-- ------------------------------------------------------------
-- 4) Модератор әйел жүргізушіні белгілейді / белгісін алады
-- ------------------------------------------------------------
create or replace function public.mod_set_executor_umay(p_user uuid, p_on boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator()
     or not public.mod_can('executors') then
    raise exception 'FORBIDDEN';
  end if;
  -- Бұғатталған қызметкер (0084) — басқа mod_* сияқты бұл да жабық.
  if exists (select 1 from public.profiles
              where id = auth.uid() and blocked_at is not null) then
    raise exception 'NO_PERMISSION' using errcode = '42501';
  end if;

  update public.executor_profiles
     set is_umay = coalesce(p_on, false)
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;

  perform public.mod_audit('executor_umay', 'executor', p_user::text,
    jsonb_build_object('on', coalesce(p_on, false)));
end;
$$;

revoke execute on function public.mod_set_executor_umay(uuid, boolean) from public, anon;
grant execute on function public.mod_set_executor_umay(uuid, boolean) to authenticated;

-- ------------------------------------------------------------
-- 5) exec_can_see v4 — 0079 нұсқасы + Ұмай ережесі
-- ------------------------------------------------------------
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

  -- БЕЛСЕНДІ РӨЛ орындаушы болуы шарт (0046/0063).
  if not exists (select 1 from public.profiles
                  where id = p_exec and role = 'executor') then
    return false;
  end if;

  if o.client_id = p_exec then return false; end if;

  -- Клиент бұл орындаушыны бұғаттаған (0079) — заказ оған мүлдем көрінбейді.
  if public.is_blocked_by_client(o.client_id, p_exec) then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;

  -- ТАНЫСУ РЕЖИМІ (0063): өтінім әлі толтырылмаған — сүзгі жоқ.
  -- ҰМАЙ (0086): бірақ Ұмай заказы профильсіз адамға ЕШҚАШАН көрінбейді.
  if not found then
    if o.vehicle_type = 'umay' then return false; end if;
    return true;
  end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді.
  -- ҰМАЙ (0086): тек көлігі 'taxi' әрі модератор белгілеген әйел жүргізуші.
  if o.vehicle_type = 'umay' then
    if ep.vehicle_type::text is distinct from 'taxi'
       or not coalesce(ep.is_umay, false) then
      return false;
    end if;
  elsif o.vehicle_type is distinct from ep.vehicle_type then
    return false;
  end if;

  -- ҚАЛА СҮЗГІСІ (0053): жергілікті заказ тек сол қаладағы орындаушыға.
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

-- ------------------------------------------------------------
-- 6) orders_feed RLS — 0017 нұсқасы + Ұмай шарты
-- ------------------------------------------------------------
drop policy if exists orders_feed on public.orders;
create policy orders_feed on public.orders
  for select to authenticated
  using (
    status = 'searching' and type = 'bidding'
    and exists (select 1 from public.executor_profiles ep
                where ep.user_id = auth.uid()
                  and ep.status = 'approved')
    and exists (select 1 from public.tariff_sessions ts
                where ts.executor_id = auth.uid()
                  and ts.kind = orders.tariff
                  and ts.expires_at > now())
    and (vehicle_type is distinct from 'umay'
         or exists (select 1 from public.executor_profiles ep
                    where ep.user_id = auth.uid() and ep.is_umay
                      and ep.vehicle_type::text = 'taxi'))
  );

-- ------------------------------------------------------------
-- 7) nearby_executors — 0075 нұсқасы + 'umay' сүзгісі
-- ------------------------------------------------------------
create or replace function public.nearby_executors(
  p_lat float8,
  p_lng float8,
  p_vehicle text default null,
  p_radius_km float8 default 15)
returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select
      round(l.lat::numeric, 3)::float8 as lat,
      round(l.lng::numeric, 3)::float8 as lng,
      ep.vehicle_type::text as vehicle_type,
      l.heading
    from public.executor_locations l
    join public.executor_profiles ep on ep.user_id = l.executor_id
    join public.profiles p on p.id = l.executor_id
    where l.updated_at > now() - interval '10 minutes'
      and l.order_id is null
      and ep.status = 'approved'
      and ep.busy_order_id is null
      and coalesce(ep.on_line, true)
      and p.role = 'executor'
      and (p_vehicle is null
           or (p_vehicle = 'umay'
               and ep.vehicle_type::text = 'taxi' and ep.is_umay)
           or (p_vehicle <> 'umay' and ep.vehicle_type::text = p_vehicle))
      and abs(l.lat - p_lat) < (p_radius_km / 111.0)
      and abs(l.lng - p_lng) < (p_radius_km / (111.0 * cos(radians(p_lat))))
      and public.exec_has_capacity(l.executor_id)
    order by (l.lat - p_lat) ^ 2 + (l.lng - p_lng) ^ 2
    limit 30
  ) x;
$$;

grant execute on function public.nearby_executors(float8, float8, text, float8)
  to anon, authenticated;

notify pgrst, 'reload schema';
