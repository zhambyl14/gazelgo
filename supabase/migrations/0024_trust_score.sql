-- GazelGo · 0024_trust_score.sql
-- Клиент/орындаушы «сенім деңгейі»: order_reports арқылы хабарланған сайын
-- зардап шеккен тарап емес, ХАБАРЛАНҒАН тараптың trust_score-ы кемиді
-- (әдепкі 100, әр хабарлама -15). 50-ден төмен түссе — аккаунт автоматты
-- бұғатталады: жаңа заказ (клиент) немесе жаңа ұсыныс (орындаушы) бере
-- алмайды, бар тарихы/ағымдағы заказы өзгеріссіз қалады. Модератор
-- «Хабарламалар» экранынан қолмен балл қоса/азайта алады және блокты
-- алып тастай алады. ML/автоматты «түпкілікті шешім» ЕМЕС — тек қайталанған
-- хабарламалар санағышы, модератор әрдайым қарай/қайтара алады.

alter table public.profiles
  add column if not exists trust_score int not null default 100,
  add column if not exists blocked_at timestamptz,
  add column if not exists block_reason text;

create index if not exists idx_profiles_blocked
  on public.profiles (blocked_at) where blocked_at is not null;

-- ---------- тікелей клиенттік UPDATE-тен қорғау ----------
create or replace function public.guard_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    return new;
  end if;
  if new.role is distinct from old.role
     or new.rating is distinct from old.rating
     or new.rating_count is distinct from old.rating_count
     or new.trust_score is distinct from old.trust_score
     or new.blocked_at is distinct from old.blocked_at
     or new.block_reason is distinct from old.block_reason then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  return new;
end;
$$;

-- ---------- report_order: хабарлау + хабарланған тараптың баллы кемиді ----------
create or replace function public.report_order(p_order uuid, p_reason text default '')
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role text;
  v_reported uuid;
  v_reason text;
  v_body text;
  v_report_id uuid;
  v_new_score int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  -- Тек орындаушы хабарлай алады (жүкті нақты көретін тарап сол; клиент
  -- өз жүгін өзі «күдікті» деп белгілей алмайды — UI-де де батырма алынды).
  if o.executor_id = v_uid then
    v_role := 'executor';
    v_reported := o.client_id;
  elsif o.client_id = v_uid then
    raise exception 'FORBIDDEN';
  else
    raise exception 'FORBIDDEN';
  end if;

  v_reason := coalesce(trim(p_reason), '');

  insert into public.order_reports (order_id, reporter_id, reporter_role, reason)
  values (p_order, v_uid, v_role, v_reason)
  returning id into v_report_id;

  if v_reported is not null then
    update public.profiles
       set trust_score = greatest(trust_score - 15, 0)
     where id = v_reported
    returning trust_score into v_new_score;

    if v_new_score is not null and v_new_score <= 50 then
      update public.profiles
         set blocked_at = coalesce(blocked_at, now()),
             block_reason = coalesce(block_reason,
               'Сенім деңгейі 50-ден төмен түсті (қайталанған хабарламалар)')
       where id = v_reported;
    end if;
  end if;

  v_body := '🚨 КҮДІКТІ ЖҮК ТУРАЛЫ ХАБАРЛАМА — заказ #' || left(p_order::text, 8)
    || E'\nХабарлаған: Газелист'
    || E'\nЖүк сипаттамасы: ' || coalesce(nullif(o.cargo_desc, ''), '(жазылмаған)')
    || (case when v_reason <> '' then E'\nСебебі: ' || v_reason else '' end)
    || (case when v_new_score is not null
             then E'\nҚарсы тараптың сенім деңгейі енді: ' || v_new_score || '/100'
             else '' end);

  perform public.support_send(v_body, null);

  return v_report_id;
end;
$$;
revoke all on function public.report_order(uuid, text) from public, anon;
grant execute on function public.report_order(uuid, text) to authenticated;

-- ---------- модератор: балл қолмен түзету (+ өссе автоматты блок жаппайды) ----------
create or replace function public.mod_adjust_trust_score(
  p_user uuid, p_delta int, p_reason text default '')
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_score int;
begin
  if not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  update public.profiles
     set trust_score = greatest(least(trust_score + p_delta, 100), 0)
   where id = p_user
  returning trust_score into v_score;
  if not found then raise exception 'NOT_FOUND'; end if;

  if v_score <= 50 then
    update public.profiles
       set blocked_at = coalesce(blocked_at, now()),
           block_reason = coalesce(block_reason, nullif(trim(p_reason), ''),
             'Сенім деңгейі 50-ден төмен түсті')
     where id = p_user;
  end if;

  return jsonb_build_object('trust_score', v_score);
end;
$$;
revoke all on function public.mod_adjust_trust_score(uuid,int,text) from public, anon;
grant execute on function public.mod_adjust_trust_score(uuid,int,text) to authenticated;

-- ---------- модератор: блоктау / блоктан шығару қолмен ----------
create or replace function public.mod_set_account_blocked(
  p_user uuid, p_blocked boolean, p_reason text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  update public.profiles
     set blocked_at = case when p_blocked then now() else null end,
         block_reason = case when p_blocked then nullif(trim(p_reason), '') else null end,
         trust_score = case when not p_blocked and trust_score <= 50 then 60 else trust_score end
   where id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
end;
$$;
revoke all on function public.mod_set_account_blocked(uuid,boolean,text) from public, anon;
grant execute on function public.mod_set_account_blocked(uuid,boolean,text) to authenticated;

-- ---------- модератор: хабарлама статусын өзгерту (open/reviewed/dismissed) ----------
create or replace function public.mod_set_report_status(p_report uuid, p_status text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  if p_status not in ('open','reviewed','dismissed') then raise exception 'BAD_STATUS'; end if;
  update public.order_reports set status = p_status where id = p_report;
  if not found then raise exception 'NOT_FOUND'; end if;
end;
$$;
revoke all on function public.mod_set_report_status(uuid,text) from public, anon;
grant execute on function public.mod_set_report_status(uuid,text) to authenticated;

-- ---------- бұғатталған аккаунттар: жаңа заказ/ұсыныс бере алмайды ----------
-- (бар белсенді заказы/тарихы бұзылмайды — тек ЖАҢА әрекет тоқтатылады)
create or replace function public.check_client_not_blocked()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from public.profiles
             where id = new.client_id and blocked_at is not null) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_client_blocked_check on public.orders;
create trigger trg_client_blocked_check
  before insert on public.orders
  for each row execute function public.check_client_not_blocked();

create or replace function public.check_executor_not_blocked()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from public.profiles
             where id = new.executor_id and blocked_at is not null) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_executor_blocked_check on public.offers;
create trigger trg_executor_blocked_check
  before insert on public.offers
  for each row execute function public.check_executor_not_blocked();
