-- ============================================================
-- Tasu · 0059_bonus_program.sql
-- ============================================================
-- ОРЫНДАУШЫҒА БОНУС БАҒДАРЛАМАСЫ (модератор баптайды).
--
-- Идея: орындаушы белгілі кезеңде (күн/апта/ай) N заказ аяқтаса —
-- БАЛАНСЫНА бонус сомасы автоматты түседі. Бонус ТЕК балансқа түседі
-- (қолма-қол шешіп алу жоқ) — оны тариф сатып алуға жұмсайды.
--
-- Модератор Баптаулардан (`app_settings.bonus`) басқарады:
--   enabled (bool)   — бағдарлама қосулы ма (әдепкі: өшірулі)
--   target  (int)    — бонусқа қажет заказ саны
--   amount  (bigint) — бонус сомасы (₸)
--   period  (text)   — 'day' | 'week' | 'month' — санақ қай кезеңде нөлденеді
--   repeat  (bool)   — кезең ішінде әр `target` сайын қайталана ма
--
-- МАҢЫЗДЫ (енгізу шешімі): бонус `balance_txns.type = 'adjustment'`
-- түрімен жазылады, жаңа enum мәні ҚОСЫЛМАЙДЫ. Себебі PostgreSQL-де
-- `alter type ... add value` жасаған соң сол мәнді СОЛ ТРАНЗАКЦИЯДА
-- қолдануға болмайды — Supabase SQL Editor бүкіл файлды бір транзакцияда
-- орындайтындықтан миграция сынар еді. Бонустың толық тарихы бөлек
-- `bonus_awards` кестесінде жатыр — қосымша соны оқиды.
-- ============================================================

-- ============================================================
-- 1) Баптау кілті
-- ============================================================
insert into public.app_settings (key, value)
values ('bonus', '{"enabled": false, "target": 20, "amount": 2000, "period": "week", "repeat": true}'::jsonb)
on conflict (key) do nothing;

-- Кілт бұрын қолмен жасалған болса — жетпейтін өрістерді толтырамыз
-- (merge: бар мәндер сақталады).
update public.app_settings
set value = '{"enabled": false, "target": 20, "amount": 2000, "period": "week", "repeat": true}'::jsonb || value
where key = 'bonus';

-- ============================================================
-- 2) mod_update_setting — 'bonus' кілті қосылды
-- ============================================================
create or replace function public.mod_update_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if p_key not in ('tariffs', 'payment', 'version_gate', 'order_min',
                   'vehicle_rules', 'listings', 'taxi', 'topup_bot',
                   'support_bot', 'support', 'bonus') then
    raise exception 'BAD_KEY';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.mod_update_setting(text, jsonb) to authenticated;

-- ============================================================
-- 3) Берілген бонустардың тарихы
-- ============================================================
-- `seq` — сол кезеңдегі НЕШІНШІ бонус (repeat=true болса 1, 2, 3…).
-- (executor_id, period_start, seq) БІРЕГЕЙ — сол себепті бір бонус екі рет
-- берілмейді (заказ аяқталған сайын шақырылса да).
create table if not exists public.bonus_awards (
  id           uuid primary key default gen_random_uuid(),
  executor_id  uuid not null references public.profiles(id) on delete cascade,
  period       text not null,
  period_start timestamptz not null,
  seq          int  not null,
  target       int  not null,
  amount       bigint not null,
  orders_count int  not null,
  created_at   timestamptz not null default now(),
  unique (executor_id, period_start, seq)
);

create index if not exists idx_bonus_awards_exec
  on public.bonus_awards (executor_id, created_at desc);

alter table public.bonus_awards enable row level security;

drop policy if exists bonus_awards_own_select on public.bonus_awards;
create policy bonus_awards_own_select on public.bonus_awards
  for select to authenticated
  using (executor_id = auth.uid() or public.is_moderator());

-- ============================================================
-- 4) Кезеңнің басы / соңы (Asia/Almaty)
-- ============================================================
create or replace function public.bonus_period_start(p_period text)
returns timestamptz
language sql stable
set search_path = public, pg_temp
as $$
  select case p_period
    when 'day'   then date_trunc('day',   now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty'
    when 'month' then date_trunc('month', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty'
    else              date_trunc('week',  now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty'
  end;
$$;

create or replace function public.bonus_period_end(p_period text)
returns timestamptz
language sql stable
set search_path = public, pg_temp
as $$
  select case p_period
    when 'day'   then public.bonus_period_start('day')   + interval '1 day'
    when 'month' then public.bonus_period_start('month') + interval '1 month'
    else              public.bonus_period_start('week')  + interval '7 days'
  end;
$$;

-- ============================================================
-- 5) Бонусты тексеріп, керек болса БЕРУ
-- ============================================================
-- Заказ аяқталған сайын шақырылады (order_advance ішінен). Идемпотентті:
-- `bonus_awards` бірегей кілті екінші рет беруге жол бермейді.
create or replace function public.award_bonus_if_due(p_exec uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  cfg      jsonb;
  v_target int;
  v_amount bigint;
  v_period text;
  v_repeat boolean;
  v_start  timestamptz;
  v_done   int;
  v_seq    int;
  v_have   int;
begin
  if p_exec is null then return; end if;

  select value into cfg from public.app_settings where key = 'bonus';
  if cfg is null or coalesce((cfg->>'enabled')::boolean, false) = false then
    return;
  end if;

  v_target := coalesce((cfg->>'target')::int, 0);
  v_amount := coalesce((cfg->>'amount')::bigint, 0);
  if v_target < 1 or v_amount < 1 then return; end if;

  v_period := coalesce(cfg->>'period', 'week');
  if v_period not in ('day', 'week', 'month') then v_period := 'week'; end if;
  v_repeat := coalesce((cfg->>'repeat')::boolean, true);
  v_start  := public.bonus_period_start(v_period);

  select count(*) into v_done from public.orders
   where executor_id = p_exec
     and status = 'completed'
     and completed_at >= v_start;

  v_seq := v_done / v_target;                       -- бүтін бөлу
  if not v_repeat and v_seq > 1 then v_seq := 1; end if;
  if v_seq < 1 then return; end if;

  select coalesce(max(seq), 0) into v_have from public.bonus_awards
   where executor_id = p_exec and period_start = v_start;

  -- ҚАУІПСІЗДІК ШЕГІ: қалыпты жағдайда бір заказ аяқталғанда ең көбі
  -- БІР бонус беріледі. Бірақ модератор `target`-ті кезең ортасында
  -- күрт азайтып жіберсе (мыс. 20 → 1), артта қалған ондаған бонус
  -- бірден берілуі мүмкін еді. Бір шақыруда 3-еуімен шектейміз —
  -- қалғаны келесі заказдарда әділ түрде беріліп бітеді.
  if v_seq > v_have + 3 then v_seq := v_have + 3; end if;

  while v_have < v_seq loop
    v_have := v_have + 1;

    insert into public.bonus_awards
      (executor_id, period, period_start, seq, target, amount, orders_count)
    values
      (p_exec, v_period, v_start, v_have, v_target, v_amount, v_done)
    on conflict (executor_id, period_start, seq) do nothing;

    -- Жарыс жағдайында (екі заказ бір мезетте аяқталса) жазба қосылмаса —
    -- бонус БҰРЫН берілген, балансқа екінші рет қоспаймыз.
    if not found then continue; end if;

    update public.executor_profiles
       set balance = balance + v_amount
     where user_id = p_exec;

    insert into public.balance_txns (executor_id, amount, type, note)
    values (p_exec, v_amount, 'adjustment',
            'Бонус: ' || (v_have * v_target) || ' заказ');

    perform public.send_push(
      'Бонус берілді! 🎁',
      (v_have * v_target) || ' заказ аяқталды. Балансыңызға ' ||
        v_amount || ' ₸ бонус қосылды.',
      jsonb_build_object('type', 'bonus'),
      array[p_exec],
      'Бонус начислен! 🎁',
      'Выполнено ' || (v_have * v_target) || ' заказов. На баланс добавлено ' ||
        v_amount || ' ₸ бонуса.'
    );
  end loop;
exception when others then
  -- Бонус — қосымша мүмкіндік: қатесі ЕШҚАШАН заказды аяқтауды бұзбауы керек.
  null;
end;
$$;

revoke execute on function public.award_bonus_if_due(uuid) from public, anon, authenticated;

-- ============================================================
-- 6) order_advance — аяқтағанда бонусты тексереді
-- ============================================================
-- 0027-дегі нұсқаның толық көшірмесі + соңында `award_bonus_if_due`.
create or replace function public.order_advance(p_order uuid, p_status text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_next public.order_status;
  v_expected public.order_status;
  v_is_client boolean;
  v_is_executor boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_next := p_status::public.order_status;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  v_is_client := (o.client_id = v_uid);
  v_is_executor := (o.executor_id is not null and o.executor_id = v_uid);
  if not v_is_client and not v_is_executor then raise exception 'FORBIDDEN'; end if;

  v_expected := case o.status
    when 'accepted'   then 'arrived'::public.order_status
    when 'arrived'    then 'loading'::public.order_status
    when 'loading'    then 'in_transit'::public.order_status
    when 'in_transit' then 'completed'::public.order_status
    else null
  end;
  if v_expected is null or v_next <> v_expected then raise exception 'BAD_TRANSITION'; end if;

  -- Рөлдік тексеру: тиеу растауы — клиенттікі, қалғаны — орындаушыныкі.
  if v_next = 'loading' then
    if not v_is_client then raise exception 'CLIENT_ONLY'; end if;
  else
    if not v_is_executor then raise exception 'EXECUTOR_ONLY'; end if;
  end if;

  if v_next = 'completed' then
    update public.orders set status = 'completed', completed_at = now() where id = p_order;
    insert into public.earnings (executor_id, order_id, amount)
    values (o.executor_id, p_order, coalesce(o.final_price, 0))
    on conflict (order_id) do nothing;
    update public.executor_profiles
       set total_earned = total_earned + coalesce(o.final_price, 0),
           busy_order_id = null
     where user_id = o.executor_id;
    -- поездка санағышы (екі жаққа)
    update public.profiles set trips = trips + 1
     where id in (o.client_id, o.executor_id);
    -- бонус бағдарламасы (0059) — лимитке жетсе балансқа сома қосылады
    perform public.award_bonus_if_due(o.executor_id);
  else
    update public.orders set status = v_next where id = p_order;
  end if;
end;
$$;

grant execute on function public.order_advance(uuid,text) to authenticated;

-- ============================================================
-- 7) executor_bonus() — орындаушыға прогресс
-- ============================================================
-- Лентадағы «бонусқа N заказ қалды» жолағы осыны оқиды.
create or replace function public.executor_bonus()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  cfg      jsonb;
  v_target int;
  v_amount bigint;
  v_period text;
  v_repeat boolean;
  v_start  timestamptz;
  v_end    timestamptz;
  v_done   int;
  v_awarded int;
  v_earned  bigint;
  v_total   bigint;
  v_cycle   int;
  v_left    int;
  v_finished boolean := false;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select value into cfg from public.app_settings where key = 'bonus';
  if cfg is null or coalesce((cfg->>'enabled')::boolean, false) = false then
    return jsonb_build_object('enabled', false);
  end if;

  v_target := coalesce((cfg->>'target')::int, 0);
  v_amount := coalesce((cfg->>'amount')::bigint, 0);
  if v_target < 1 or v_amount < 1 then
    return jsonb_build_object('enabled', false);
  end if;

  v_period := coalesce(cfg->>'period', 'week');
  if v_period not in ('day', 'week', 'month') then v_period := 'week'; end if;
  v_repeat := coalesce((cfg->>'repeat')::boolean, true);
  v_start  := public.bonus_period_start(v_period);
  v_end    := public.bonus_period_end(v_period);

  select count(*) into v_done from public.orders
   where executor_id = v_uid
     and status = 'completed'
     and completed_at >= v_start;

  select count(*), coalesce(sum(amount), 0) into v_awarded, v_earned
    from public.bonus_awards
   where executor_id = v_uid and period_start = v_start;

  select coalesce(sum(amount), 0) into v_total
    from public.bonus_awards where executor_id = v_uid;

  -- Қайталанбайтын режимде кезеңдегі бонус алынып қойса — прогресс толық.
  if not v_repeat and v_awarded >= 1 then
    v_cycle := v_target;
    v_left  := 0;
    v_finished := true;
  else
    v_cycle := v_done % v_target;
    v_left  := v_target - v_cycle;
  end if;

  return jsonb_build_object(
    'enabled', true,
    'target', v_target,
    'amount', v_amount,
    'period', v_period,
    'repeat', v_repeat,
    'done', v_done,
    'in_cycle', v_cycle,
    'left', v_left,
    'finished', v_finished,
    'awarded_count', v_awarded,
    'earned', v_earned,
    'earned_total', v_total,
    'period_start', v_start,
    'period_end', v_end
  );
end;
$$;

grant execute on function public.executor_bonus() to authenticated;

-- ============================================================
-- 8) my_bonus_awards() — орындаушының бонус тарихы
-- ============================================================
create or replace function public.my_bonus_awards()
returns setof public.bonus_awards
language sql stable
security definer
set search_path = public, pg_temp
as $$
  select * from public.bonus_awards
   where executor_id = auth.uid()
   order by created_at desc
   limit 100;
$$;

grant execute on function public.my_bonus_awards() to authenticated;

-- ============================================================
-- 9) mod_bonus_stats() — модераторға қысқаша есеп
-- ============================================================
create or replace function public.mod_bonus_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
  v_sum   bigint;
  v_month_count int;
  v_month_sum   bigint;
  v_top   jsonb;
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  select count(*), coalesce(sum(amount), 0) into v_count, v_sum
    from public.bonus_awards;

  select count(*), coalesce(sum(amount), 0) into v_month_count, v_month_sum
    from public.bonus_awards
   where created_at >= date_trunc('month', now() at time zone 'Asia/Almaty')
                         at time zone 'Asia/Almaty';

  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into v_top
  from (
    select p.full_name,
           count(*)              as awards,
           sum(ba.amount)::bigint as total
      from public.bonus_awards ba
      join public.profiles p on p.id = ba.executor_id
     group by p.full_name
     order by sum(ba.amount) desc
     limit 5
  ) x;

  return jsonb_build_object(
    'awards_total', v_count,
    'amount_total', v_sum,
    'awards_month', v_month_count,
    'amount_month', v_month_sum,
    'top', v_top
  );
end;
$$;

grant execute on function public.mod_bonus_stats() to authenticated;
