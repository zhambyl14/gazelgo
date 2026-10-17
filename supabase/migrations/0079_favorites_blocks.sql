-- ============================================================
-- Tasu · 0079_favorites_blocks.sql
-- ============================================================
-- ТАҢДАУЛЫ ОРЫНДАУШЫЛАР ❤ және «МАҒАН КӨРСЕТПЕУ».
--
--   * Клиент жақсы жұмыс істеген орындаушыны ТАҢДАУЛЫ деп белгілейді.
--     Сол клиент жаңа заказ бергенде таңдаулы орындаушыға (заказ оған сай
--     болса) АРНАЙЫ push кетеді: «Сізді таңдаулы деп белгілеген клиенттен
--     жаңа заказ» — ол бәрінен бұрын көңіл бөледі. Ұсыныстар тізімінде
--     таңдаулылар бірінші тұрады.
--   * Клиент жаман тәжірибеден кейін орындаушыны БҰҒАТТАЙДЫ — сол
--     орындаушы бұл клиенттің заказдарын лентада көрмейді, ұсыныс бере
--     алмайды, push алмайды (`exec_can_see` арқылы — ол лентаға да,
--     `exec_can_take`/`place_offer`-ге де, push-қа да ортақ тексеріс).
--   * Екеуі бір-бірін жоққа шығарады: бұғаттаса — таңдаулыдан шығады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0078-дан кейін).
-- ============================================================

create table if not exists public.client_favorites (
  client_id   uuid not null references public.profiles(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (client_id, executor_id)
);

create table if not exists public.client_blocks (
  client_id   uuid not null references public.profiles(id) on delete cascade,
  executor_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (client_id, executor_id)
);

create index if not exists idx_client_favorites_exec
  on public.client_favorites (executor_id);
create index if not exists idx_client_blocks_exec
  on public.client_blocks (executor_id);

alter table public.client_favorites enable row level security;
alter table public.client_blocks enable row level security;

-- Клиент тек ӨЗ тізімін оқиды; өзгерту — RPC арқылы.
drop policy if exists client_favorites_read on public.client_favorites;
create policy client_favorites_read on public.client_favorites
  for select to authenticated using (client_id = auth.uid());

drop policy if exists client_blocks_read on public.client_blocks;
create policy client_blocks_read on public.client_blocks
  for select to authenticated using (client_id = auth.uid());

-- ============================================================
-- Белгілеу: 'favorite' | 'block' | 'none'
-- ============================================================
create or replace function public.set_executor_pref(p_executor uuid, p_kind text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_executor is null or p_executor = v_uid then raise exception 'BAD_INPUT'; end if;
  if p_kind not in ('favorite', 'block', 'none') then raise exception 'BAD_INPUT'; end if;

  -- Тек бірге жұмыс істеген (кемінде бір заказда кездескен) орындаушыны
  -- белгілеуге болады — бөтен адамдарды тізімге жинау мүмкін емес.
  if p_kind <> 'none' and not exists (
    select 1 from public.orders o
     where o.client_id = v_uid and o.executor_id = p_executor
  ) and not exists (
    select 1 from public.offers f
      join public.orders o on o.id = f.order_id
     where o.client_id = v_uid and f.executor_id = p_executor
  ) then
    raise exception 'FORBIDDEN';
  end if;

  delete from public.client_favorites where client_id = v_uid and executor_id = p_executor;
  delete from public.client_blocks where client_id = v_uid and executor_id = p_executor;

  if p_kind = 'favorite' then
    insert into public.client_favorites (client_id, executor_id) values (v_uid, p_executor);
  elsif p_kind = 'block' then
    insert into public.client_blocks (client_id, executor_id) values (v_uid, p_executor);
  end if;
end;
$$;

grant execute on function public.set_executor_pref(uuid, text) to authenticated;

-- Бұғат тексерісі — SECURITY DEFINER (exec_can_see орындаушы атынан
-- шақырылуы мүмкін, ал ол клиенттің бұғат тізімін RLS бойынша оқи алмайды).
create or replace function public.is_blocked_by_client(p_client uuid, p_exec uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.client_blocks b
     where b.client_id = p_client and b.executor_id = p_exec
  );
$$;

-- ============================================================
-- exec_can_see v3 — 0063 нұсқасы + клиенттің бұғаты
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
  if not found then return true; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

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

-- ============================================================
-- Жаңа заказ push-ы v2 — 0071 нұсқасы + таңдаулыларға бөлек мәтін
-- ============================================================
create or replace function public.notify_executors_new_order()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fav   uuid[];
  v_ready uuid[];
  v_idle  uuid[];
begin
  if new.status <> 'searching' then return new; end if;

  -- 1) Осы клиенттің ТАҢДАУЛЫ орындаушылары (заказ оларға сай болса).
  select array_agg(f.executor_id) into v_fav
    from public.client_favorites f
    join public.executor_profiles ep on ep.user_id = f.executor_id
   where f.client_id = new.client_id
     and ep.status = 'approved'
     and ep.order_push_enabled = true
     and public.exec_can_see(f.executor_id, new.id);

  -- 2) Қалғандары — 0071-дегідей (таңдаулыларға екінші push кетпейді).
  select
    array_agg(ep.user_id) filter (where public.exec_can_take(ep.user_id, new.id)),
    array_agg(ep.user_id) filter (where not public.exec_can_take(ep.user_id, new.id))
  into v_ready, v_idle
  from public.executor_profiles ep
  where ep.status = 'approved'
    and ep.order_push_enabled = true
    and ep.user_id <> new.client_id
    and not (ep.user_id = any(coalesce(v_fav, '{}'::uuid[])))
    and public.exec_can_see(ep.user_id, new.id);

  if coalesce(array_length(v_fav, 1), 0) > 0 then
    perform public.send_push(
      'Таңдаулы клиентіңізден заказ ❤',
      'Сізді таңдаулы деп белгілеген клиент жаңа заказ берді — қараңыз.',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_fav,
      'Заказ от клиента, где вы в избранном ❤',
      'Клиент, отметивший вас избранным, создал новый заказ — посмотрите.'
    );
  end if;

  if coalesce(array_length(v_ready, 1), 0) > 0 then
    perform public.send_push(
      'Жаңа заказ',
      'Сізге сай жаңа заказ шықты — тезірек қараңыз.',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_ready,
      'Новый заказ',
      'Появился подходящий заказ — посмотрите скорее.'
    );
  end if;

  if coalesce(array_length(v_idle, 1), 0) > 0 then
    perform public.send_push(
      'Жаңа заказ',
      'Сізге сай жаңа заказ шықты. Алу үшін линияға шығыңыз (тариф).',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_idle,
      'Новый заказ',
      'Появился подходящий заказ. Чтобы взять его, выйдите на линию (тариф).'
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;
