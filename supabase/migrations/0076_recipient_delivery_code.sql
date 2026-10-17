-- ============================================================
-- Tasu · 0076_recipient_delivery_code.sql
-- ============================================================
-- АЛУШЫҒА СІЛТЕМЕ және ЖЕТКІЗУ КОДЫ.
--
-- Мәселе: жүкті көбіне БАСҚА адам қабылдайды. Ол көліктің қайда екенін
-- білмейді, ал жүк дұрыс адамға тапсырылғанына кепіл жоқ.
--
-- Шешім:
--   * Клиент заказға АЛУШЫНЫ (аты + телефоны) қосады — `order_recipients`.
--   * Сервер 4 таңбалы КОД жасайды. Код орындаушыға КӨРІНБЕЙДІ (кестеге
--     тікелей қатынас жоқ, тек RPC арқылы, ал орындаушыға код берілмейді).
--   * Алушыға WhatsApp арқылы ЖЕКЕ сілтеме жіберіледі (`/track/<token>`):
--     картада көлік, келу уақыты және КОД. Бұл токен `orders.share_token`
--     емес (ол заказ жолында тұр, лентадағы орындаушылар да оқи алады) —
--     алушының өз токені, тек осы кестеде.
--   * Орындаушы «Аяқтау» басқанда алушыдан кодты сұрап енгізеді
--     (`verify_delivery_code`). Код расталмайынша заказ АЯҚТАЛМАЙДЫ
--     (триггер `CODE_REQUIRED` шығарады).
--   * Алушы кодты жоғалтса — клиент өз қосымшасынан «Жүк жетті» деп растай
--     алады (`client_confirm_delivery`), модератор кез келген уақытта.
--   * Код 6 рет қате енгізілсе — құлыпталады (CODE_LOCKED), тек клиент не
--     модератор растай алады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0075-тен кейін).
-- ============================================================

create table if not exists public.order_recipients (
  order_id          uuid primary key references public.orders(id) on delete cascade,
  name              text not null default '',
  phone             text not null,
  delivery_code     text,
  token             uuid not null default gen_random_uuid(),
  code_verified_at  timestamptz,
  verified_by       text,          -- 'code' | 'client' | 'moderator'
  attempts          int not null default 0,
  created_at        timestamptz not null default now()
);

create unique index if not exists idx_order_recipients_token
  on public.order_recipients (token);

alter table public.order_recipients enable row level security;
-- Тікелей SELECT/INSERT саясаты ӘДЕЙІ ЖОҚ: код орындаушыға көрінбеуі керек.
-- Барлық қатынас төмендегі SECURITY DEFINER функциялары арқылы.

-- Телефонды 7XXXXXXXXXX пішініне келтіру (қосымшадағы Phone.normalize-пен
-- бірдей ереже). Дұрыс емес болса — null.
create or replace function public.norm_kz_phone(p_raw text)
returns text
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  d text := regexp_replace(coalesce(p_raw, ''), '\D', '', 'g');
begin
  if length(d) = 11 and left(d, 1) = '8' then d := '7' || substr(d, 2); end if;
  if length(d) = 10 then d := '7' || d; end if;
  if length(d) = 11 and left(d, 2) = '77' then return d; end if;
  return null;
end;
$$;

-- ============================================================
-- 1) Клиент алушыны қосады / өзгертеді / алып тастайды
-- ============================================================
create or replace function public.set_order_recipient(
  p_order uuid,
  p_name text,
  p_phone text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_phone text;
  r record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status not in ('searching','accepted','arrived','loading','in_transit') then
    raise exception 'NOT_AVAILABLE';
  end if;

  -- Бос телефон — алушыны алып тастау (код әлі расталмаған болса ғана).
  if coalesce(trim(p_phone), '') = '' then
    delete from public.order_recipients
     where order_id = p_order and code_verified_at is null;
    return null;
  end if;

  v_phone := public.norm_kz_phone(p_phone);
  if v_phone is null then raise exception 'BAD_PHONE'; end if;

  insert into public.order_recipients (order_id, name, phone, delivery_code)
  values (p_order, left(coalesce(trim(p_name), ''), 80), v_phone,
          lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict (order_id) do update
    set name = excluded.name,
        phone = excluded.phone,
        delivery_code = coalesce(public.order_recipients.delivery_code,
                                 excluded.delivery_code);

  select * into r from public.order_recipients where order_id = p_order;
  return jsonb_build_object(
    'name', r.name,
    'phone', r.phone,
    'code', r.delivery_code,
    'token', r.token::text,
    'verified_at', r.code_verified_at
  );
end;
$$;

grant execute on function public.set_order_recipient(uuid, text, text) to authenticated;

-- ============================================================
-- 2) Алушы туралы мәлімет (кім сұрайтынына қарай)
-- ============================================================
-- Клиент пен модератор — бәрін (кодты қоса). Тағайындалған орындаушы —
-- аты мен телефонын (хабарласу үшін) және «код керек пе» белгісін, бірақ
-- КОДТЫҢ ӨЗІН ЕМЕС.
create or replace function public.get_order_recipient(p_order uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  r record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  select * into r from public.order_recipients where order_id = p_order;
  if not found then return null; end if;

  if o.client_id = v_uid or public.is_moderator() then
    return jsonb_build_object(
      'name', r.name, 'phone', r.phone,
      'code', r.delivery_code, 'token', r.token::text,
      'verified_at', r.code_verified_at, 'verified_by', r.verified_by,
      'attempts', r.attempts
    );
  end if;

  if o.executor_id = v_uid
     and o.status in ('accepted','arrived','loading','in_transit','completed') then
    return jsonb_build_object(
      'name', r.name, 'phone', r.phone,
      'has_code', r.delivery_code is not null,
      'verified_at', r.code_verified_at,
      'attempts', r.attempts
    );
  end if;

  raise exception 'FORBIDDEN';
end;
$$;

grant execute on function public.get_order_recipient(uuid) to authenticated;

-- ============================================================
-- 3) Орындаушы алушыдан алған кодты енгізеді
-- ============================================================
-- Қате кодта ҚАТЕ ШЫҒАРМАЙМЫЗ (әйтпесе транзакция кері қайтып, қате
-- әрекеттер саналмай қалар еді) — {ok:false, left:N} қайтарамыз.
create or replace function public.verify_delivery_code(p_order uuid, p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  r record;
  c_max constant int := 6;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.executor_id is distinct from v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status not in ('arrived','loading','in_transit') then
    raise exception 'BAD_TRANSITION';
  end if;

  select * into r from public.order_recipients where order_id = p_order for update;
  if not found then
    return jsonb_build_object('ok', true);
  end if;
  if r.delivery_code is null or r.code_verified_at is not null then
    return jsonb_build_object('ok', true);
  end if;
  if r.attempts >= c_max then raise exception 'CODE_LOCKED'; end if;

  if trim(coalesce(p_code, '')) = r.delivery_code then
    update public.order_recipients
       set code_verified_at = now(), verified_by = 'code'
     where order_id = p_order;
    return jsonb_build_object('ok', true);
  end if;

  update public.order_recipients set attempts = attempts + 1
   where order_id = p_order;
  return jsonb_build_object('ok', false, 'left', greatest(c_max - r.attempts - 1, 0));
end;
$$;

grant execute on function public.verify_delivery_code(uuid, text) to authenticated;

-- ============================================================
-- 4) Клиент жеткізуді өзі растайды (алушы кодты жоғалтса)
-- ============================================================
create or replace function public.client_confirm_delivery(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.client_id <> v_uid and not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  update public.order_recipients
     set code_verified_at = coalesce(code_verified_at, now()),
         verified_by = coalesce(verified_by,
                                case when o.client_id = v_uid then 'client'
                                     else 'moderator' end)
   where order_id = p_order;
end;
$$;

grant execute on function public.client_confirm_delivery(uuid) to authenticated;

-- ============================================================
-- 5) Код расталмайынша заказ аяқталмайды
-- ============================================================
create or replace function public.guard_delivery_code()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    -- Модератор (оқыс жағдай) — тексерусіз.
    if public.is_moderator() then return new; end if;
    if exists (
      select 1 from public.order_recipients r
       where r.order_id = new.id
         and r.delivery_code is not null
         and r.code_verified_at is null
    ) then
      raise exception 'CODE_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_delivery_code on public.orders;
create trigger trg_guard_delivery_code
  before update of status on public.orders
  for each row execute function public.guard_delivery_code();

-- ============================================================
-- 6) track_order v2 — алушының беті (код + келу уақыты) / бөлісу беті
-- ============================================================
-- Токен екі түрлі болуы мүмкін:
--   * АЛУШЫ токені (order_recipients.token) — бет кодты да көрсетеді әрі
--     share_trip баптауына тәуелсіз жұмыс істейді;
--   * БӨЛІСУ токені (orders.share_token) — бұрынғыдай, кодсыз.
create or replace function public.track_order(p_token text)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_token uuid;
  v_enabled boolean;
  v_live boolean;
  o record;
  v_order_id uuid;
  v_is_recipient boolean := false;
  v_recipient_name text;
  v_code text;
  v_verified_at timestamptz;
  v_executor_name text;
  v_lat float8; v_lng float8; v_heading float8; v_loc_at timestamptz;
begin
  begin
    v_token := p_token::uuid;
  exception when others then
    return jsonb_build_object('error', 'NOT_FOUND');
  end;

  select order_id, name, delivery_code, code_verified_at
    into v_order_id, v_recipient_name, v_code, v_verified_at
    from public.order_recipients where token = v_token;
  if v_order_id is not null then
    v_is_recipient := true;
    select * into o from public.orders where id = v_order_id;
    if not found then return jsonb_build_object('error', 'NOT_FOUND'); end if;
  else
    select coalesce((value->>'enabled')::boolean, false) into v_enabled
      from public.app_settings where key = 'share_trip';
    if not coalesce(v_enabled, false) then
      return jsonb_build_object('error', 'DISABLED');
    end if;
    select * into o from public.orders where share_token = v_token;
    if not found then
      return jsonb_build_object('error', 'NOT_FOUND');
    end if;
  end if;

  if o.executor_id is not null then
    -- Тек ЕСІМІ (тегісіз) — бөтен адамға толық аты-жөн керек емес.
    select split_part(trim(full_name), ' ', 1) into v_executor_name
      from public.profiles where id = o.executor_id;
  end if;

  select coalesce((value->>'enabled')::boolean, false) into v_live
    from public.app_settings where key = 'live_tracking';

  if coalesce(v_live, false) and o.status in ('accepted','arrived','loading','in_transit') then
    select lat, lng, heading, updated_at into v_lat, v_lng, v_heading, v_loc_at
      from public.executor_locations where order_id = o.id;
  end if;

  return jsonb_build_object(
    'status', o.status,
    'vehicle_type', o.vehicle_type,
    'from_city', o.from_city, 'to_city', o.to_city,
    'from_address', o.from_address, 'to_address', o.to_address,
    'from_lat', o.from_lat, 'from_lng', o.from_lng,
    'to_lat', o.to_lat, 'to_lng', o.to_lng,
    'distance_km', o.distance_km,
    'created_at', o.created_at, 'accepted_at', o.accepted_at,
    'completed_at', o.completed_at,
    'arrive_by', o.arrive_by, 'arrived_at', o.arrived_at,
    'executor_name', v_executor_name,
    'lat', v_lat, 'lng', v_lng, 'heading', v_heading, 'loc_updated_at', v_loc_at,
    'is_recipient', v_is_recipient,
    'recipient_name', v_recipient_name,
    -- Код тек алушының бетінде әрі әлі расталмаған болса.
    'delivery_code', case
      when v_is_recipient and v_verified_at is null then v_code
    end,
    'delivered', case when v_is_recipient then v_verified_at is not null end
  );
end;
$$;

grant execute on function public.track_order(text) to anon, authenticated;
