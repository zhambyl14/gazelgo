-- ============================================================
-- Tasu · 0082_moderator_tools.sql
-- ============================================================
-- МОДЕРАТОР ҚҰРАЛДАРЫ:
--   1) mod_dashboard_series — Шолудағы графиктер: күн сайынғы заказдар
--      (берілді / аяқталды / тоқтады), айналым (GMV), тариф сатылымы
--      (платформаның түсімі), расталған толтырулар, жаңа тіркелулер.
--   2) mod_broadcast — ЖАППАЙ ХАБАРЛАМА: барлық орындаушыға / клиентке
--      (орындаушыларға — қала мен көлік түрі бойынша сүзгімен). Push +
--      хабарламалар орталығы (0080).
--   3) mod_audit_log — ӘРЕКЕТТЕР ЖУРНАЛЫ: кім, қашан, не істеді (растау,
--      бұғаттау, баланс түзету, толтыру, статус, баптау). RPC-лерге ТИІСПЕЙМІЗ —
--      журналды кестелердегі ТРИГГЕРЛЕР толтырады, тек өзгерісті модератор
--      жасаса ғана.
--   4) mod_update_setting — жаңа баптаулар кілттері: order_chat, nearby_map.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0081-дан кейін).
-- ============================================================

-- ============================================================
-- 1) Графиктерге арналған күндік қатар
-- ============================================================
create or replace function public.mod_dashboard_series(p_days int default 14)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_days  int := greatest(1, least(coalesce(p_days, 14), 90));
  v_today date := (now() at time zone 'Asia/Almaty')::date;
  v_from  timestamptz;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  v_from := (v_today - (v_days - 1))::timestamp at time zone 'Asia/Almaty';

  return coalesce((
    with days as (
      select (v_today - g)::date as d
        from generate_series(0, v_days - 1) as g
    ),
    o as (
      select (created_at at time zone 'Asia/Almaty')::date as d,
             count(*) as created,
             count(*) filter (where status = 'completed') as completed,
             count(*) filter (where status in ('cancelled', 'expired')) as cancelled,
             coalesce(sum(coalesce(final_price, client_price))
                        filter (where status = 'completed'), 0) as gmv
        from public.orders
       where created_at >= v_from
       group by 1
    ),
    t as (
      select (started_at at time zone 'Asia/Almaty')::date as d,
             coalesce(sum(fee), 0) as tariffs,
             count(*) as tariff_count
        from public.tariff_sessions
       where started_at >= v_from
       group by 1
    ),
    tp as (
      select (coalesce(reviewed_at, created_at) at time zone 'Asia/Almaty')::date as d,
             coalesce(sum(amount), 0) as topups
        from public.topup_requests
       where status = 'approved'
         and coalesce(reviewed_at, created_at) >= v_from
       group by 1
    ),
    u as (
      select (created_at at time zone 'Asia/Almaty')::date as d,
             count(*) filter (where role = 'client') as new_clients,
             count(*) filter (where role = 'executor' or has_executor_role) as new_executors
        from public.profiles
       where created_at >= v_from
       group by 1
    )
    select jsonb_agg(
             jsonb_build_object(
               'day', days.d,
               'created', coalesce(o.created, 0),
               'completed', coalesce(o.completed, 0),
               'cancelled', coalesce(o.cancelled, 0),
               'gmv', coalesce(o.gmv, 0),
               'tariffs', coalesce(t.tariffs, 0),
               'tariff_count', coalesce(t.tariff_count, 0),
               'topups', coalesce(tp.topups, 0),
               'new_clients', coalesce(u.new_clients, 0),
               'new_executors', coalesce(u.new_executors, 0)
             )
             order by days.d
           )
      from days
      left join o on o.d = days.d
      left join t on t.d = days.d
      left join tp on tp.d = days.d
      left join u on u.d = days.d
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.mod_dashboard_series(int) to authenticated;

-- ============================================================
-- 2) Әрекеттер журналы
-- ============================================================
create table if not exists public.mod_audit_log (
  id           bigserial primary key,
  moderator_id uuid references public.profiles(id) on delete set null,
  action       text not null,
  target_type  text not null,
  target_id    text,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

create index if not exists idx_mod_audit_created on public.mod_audit_log (created_at desc);
create index if not exists idx_mod_audit_target on public.mod_audit_log (target_id);

alter table public.mod_audit_log enable row level security;

drop policy if exists mod_audit_read on public.mod_audit_log;
create policy mod_audit_read on public.mod_audit_log
  for select to authenticated using (public.is_moderator());

-- Журналға жазу — ТЕК өзгерісті модератор жасаса (клиенттің/орындаушының
-- өз әрекеті, cron, бот — жазылмайды). Қате болса өзгерістің өзін
-- тоқтатпайды.
create or replace function public.mod_audit(
  p_action text,
  p_target_type text,
  p_target_id text,
  p_details jsonb default '{}'::jsonb)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then return; end if;
  insert into public.mod_audit_log (moderator_id, action, target_type, target_id, details)
  values (auth.uid(), p_action, p_target_type, p_target_id,
          coalesce(p_details, '{}'::jsonb));
exception when others then
  null;
end;
$$;

-- --- орындаушы мәртебесі мен құжат сұранымы ---
create or replace function public.audit_executor_profiles()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    perform public.mod_audit('executor_status', 'executor', new.user_id::text,
      jsonb_build_object('from', old.status, 'to', new.status,
                         'comment', new.moderation_comment));
  end if;
  if new.docs_update_requested and not coalesce(old.docs_update_requested, false) then
    perform public.mod_audit('docs_requested', 'executor', new.user_id::text,
      jsonb_build_object('fields', to_jsonb(new.docs_update_fields),
                         'comment', new.docs_update_comment));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_executor_profiles on public.executor_profiles;
create trigger trg_audit_executor_profiles
  after update on public.executor_profiles
  for each row execute function public.audit_executor_profiles();

-- --- толтыру шешімі ---
create or replace function public.audit_topups()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    perform public.mod_audit('topup_' || new.status::text, 'executor',
      new.executor_id::text,
      jsonb_build_object('topup_id', new.id, 'amount', new.amount, 'note', new.note));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_topups on public.topup_requests;
create trigger trg_audit_topups
  after update on public.topup_requests
  for each row execute function public.audit_topups();

-- --- аккаунт бұғаты мен сенім деңгейі ---
create or replace function public.audit_profiles()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.blocked_at is distinct from old.blocked_at then
    perform public.mod_audit(
      case when new.blocked_at is null then 'account_unblock' else 'account_block' end,
      'user', new.id::text,
      jsonb_build_object('reason', new.block_reason));
  end if;
  if new.trust_score is distinct from old.trust_score then
    perform public.mod_audit('trust_score', 'user', new.id::text,
      jsonb_build_object('from', old.trust_score, 'to', new.trust_score));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_profiles on public.profiles;
create trigger trg_audit_profiles
  after update on public.profiles
  for each row execute function public.audit_profiles();

-- --- балансты қолмен түзету ---
create or replace function public.audit_balance_txns()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.type = 'adjustment' then
    perform public.mod_audit('balance_adjust', 'executor', new.executor_id::text,
      jsonb_build_object('amount', new.amount, 'note', new.note));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_balance_txns on public.balance_txns;
create trigger trg_audit_balance_txns
  after insert on public.balance_txns
  for each row execute function public.audit_balance_txns();

-- --- заказ статусын модератор өзгертсе ---
create or replace function public.audit_orders()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    perform public.mod_audit('order_status', 'order', new.id::text,
      jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_orders on public.orders;
create trigger trg_audit_orders
  after update of status on public.orders
  for each row execute function public.audit_orders();

-- --- баптаулар ---
create or replace function public.audit_settings()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public.mod_audit('setting_change', 'setting', new.key,
    jsonb_build_object('value', new.value));
  return new;
end;
$$;

drop trigger if exists trg_audit_settings on public.app_settings;
create trigger trg_audit_settings
  after insert or update on public.app_settings
  for each row execute function public.audit_settings();

-- ============================================================
-- 3) Жаппай хабарлама
-- ============================================================
-- p_audience: 'executors' | 'clients' | 'all'. Қала мен көлік түрі —
-- тек орындаушыларға (клиенттің тұрақты қаласы сақталмайды).
-- 500-ден бөліп жібереміз (push-notify функциясына бір сұраныста тым
-- үлкен тізім жібермеу үшін). Қайтарады: алушылар саны.
create or replace function public.mod_broadcast(
  p_audience text,
  p_title text,
  p_body text,
  p_city text default null,
  p_vehicle text default null)
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
  v_n int;
  v_i int := 1;
  v_city text := public.norm_city(p_city);
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(trim(p_title), '') = '' or coalesce(trim(p_body), '') = '' then
    raise exception 'EMPTY';
  end if;
  if p_audience not in ('executors', 'clients', 'all') then
    raise exception 'BAD_INPUT';
  end if;

  select array_agg(distinct p.id) into v_ids
    from public.profiles p
    left join public.executor_profiles ep on ep.user_id = p.id
   where p.role <> 'moderator'
     and p.blocked_at is null
     and (
       (p_audience in ('executors', 'all')
          and ep.user_id is not null
          and ep.status = 'approved'
          and (v_city is null or public.norm_city(ep.city) = v_city)
          and (p_vehicle is null or ep.vehicle_type::text = p_vehicle))
       or
       (p_audience in ('clients', 'all')
          and p.has_client_role
          and v_city is null and p_vehicle is null)
     );

  v_n := coalesce(array_length(v_ids, 1), 0);
  while v_i <= v_n loop
    perform public.send_push(
      trim(p_title),
      trim(p_body),
      jsonb_build_object('type', 'broadcast'),
      v_ids[v_i : least(v_i + 499, v_n)],
      trim(p_title),
      trim(p_body)
    );
    v_i := v_i + 500;
  end loop;

  perform public.mod_audit('broadcast', 'audience', p_audience,
    jsonb_build_object('title', p_title, 'body', p_body, 'city', p_city,
                       'vehicle', p_vehicle, 'recipients', v_n));
  return v_n;
end;
$$;

grant execute on function public.mod_broadcast(text, text, text, text, text) to authenticated;

-- ============================================================
-- 4) Баптаулардың рұқсат тізімі (0072 + жаңа кілттер)
-- ============================================================
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
    'share_trip', 'referral', 'news', 'support_contact',
    'order_chat', 'nearby_map'
  ) then
    raise exception 'BAD_KEY';
  end if;
  -- WhatsApp нөмірі: тек цифрлар, елдік кодпен (7XXXXXXXXXX).
  if p_key = 'support_contact'
     and coalesce(p_value->>'whatsapp', '') !~ '^[0-9]{10,15}$' then
    raise exception 'BAD_PHONE';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

insert into public.app_settings (key, value)
values ('nearby_map', jsonb_build_object('enabled', true))
on conflict (key) do nothing;
