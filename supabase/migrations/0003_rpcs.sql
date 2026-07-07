-- GazelGo · 0003_rpcs.sql
-- Бизнес-логика: барлық жазу операциялары security definer RPC арқылы.
-- Қателер код түрінде көтеріледі (INSUFFICIENT_BALANCE, EXPIRED, ...) — қосымша оларды аударады.

-- ==================== ТАРИФ САТЫП АЛУ ====================
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
  v_until timestamptz;
  v_night boolean;
  v_session uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_kind := p_kind::public.tariff_kind;

  select * into ep from public.executor_profiles where user_id = v_uid for update;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  if exists (select 1 from public.tariff_sessions
             where executor_id = v_uid and kind = v_kind and expires_at > now()) then
    raise exception 'ALREADY_ACTIVE';
  end if;

  v_price := public.tariff_price_now(p_kind);
  v_night := public.is_night_now();
  if ep.balance < v_price then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.executor_profiles set balance = balance - v_price where user_id = v_uid;

  insert into public.balance_txns (executor_id, amount, type, note)
  values (v_uid, -v_price, 'tariff_fee',
          case when v_kind = 'simple' then 'Қарапайым тариф' else 'VIP тариф' end);

  v_until := public.current_window_end();
  insert into public.tariff_sessions (executor_id, kind, fee, is_night, expires_at)
  values (v_uid, v_kind, v_price, v_night, v_until)
  returning id into v_session;

  return jsonb_build_object('session_id', v_session, 'expires_at', v_until, 'fee', v_price);
end;
$$;

-- ==================== ЗАКАЗ ҚҰРУ ====================
create or replace function public.create_order(
  p_type text,
  p_from_address text, p_from_lat float8, p_from_lng float8,
  p_to_address text,   p_to_lat float8,   p_to_lng float8,
  p_distance_km numeric,
  p_cargo text, p_comment text,
  p_size text,
  p_client_price bigint default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_type public.order_type;
  v_size public.vehicle_size;
  v_system bigint;
  v_id uuid;
  v_active int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'client') then
    raise exception 'NOT_CLIENT';
  end if;

  v_type := p_type::public.order_type;
  v_size := p_size::public.vehicle_size;

  if coalesce(trim(p_from_address),'') = '' or coalesce(trim(p_to_address),'') = ''
     or coalesce(trim(p_cargo),'') = '' then
    raise exception 'BAD_INPUT';
  end if;

  select count(*) into v_active from public.orders
  where client_id = v_uid
    and status in ('searching','accepted','arrived','loading','in_transit');
  if v_active >= 5 then raise exception 'TOO_MANY_ACTIVE'; end if;

  if v_type = 'bidding' then
    if p_client_price is null or p_client_price < 100 then raise exception 'BAD_PRICE'; end if;
    v_system := null;
  else
    v_system := public.instant_quote(p_size, p_distance_km);
  end if;

  insert into public.orders
    (client_id, type, from_address, from_lat, from_lng,
     to_address, to_lat, to_lng, distance_km, cargo_desc, comment, size,
     client_price, system_price)
  values
    (v_uid, v_type, trim(p_from_address), p_from_lat, p_from_lng,
     trim(p_to_address), p_to_lat, p_to_lng, coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), v_size,
     case when v_type = 'bidding' then p_client_price end,
     v_system)
  returning id into v_id;

  if v_type = 'instant' then
    perform public.assign_next_vip(v_id);
  end if;

  return jsonb_build_object('id', v_id, 'system_price', v_system);
end;
$$;

-- ==================== VIP ТАРАТУ (ішкі) ====================
create or replace function public.assign_next_vip(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
  v_exec uuid;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.type <> 'instant' or o.status <> 'searching' then return; end if;

  update public.vip_dispatches
     set status = 'expired'
   where order_id = p_order and status = 'pending' and expires_at <= now();

  if exists (select 1 from public.vip_dispatches
             where order_id = p_order and status = 'pending' and expires_at > now()) then
    return;
  end if;

  select ep.user_id into v_exec
  from public.executor_profiles ep
  join public.profiles p on p.id = ep.user_id
  where ep.status = 'approved'
    and ep.vehicle_size = o.size
    and ep.busy_order_id is null
    and exists (select 1 from public.tariff_sessions ts
                where ts.executor_id = ep.user_id
                  and ts.kind = 'vip' and ts.expires_at > now())
    and not exists (select 1 from public.vip_dispatches d
                    where d.order_id = p_order and d.executor_id = ep.user_id)
  order by p.rating desc, random()
  limit 1;

  if v_exec is not null then
    insert into public.vip_dispatches (order_id, executor_id, expires_at)
    values (p_order, v_exec, now() + interval '10 seconds');
  end if;
end;
$$;

-- Клиент тарапынан "келесі орындаушыға өткіз" (таймер бойынша шақырылады)
create or replace function public.advance_vip(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.orders
                 where id = p_order and (client_id = v_uid or public.is_moderator())) then
    raise exception 'FORBIDDEN';
  end if;
  perform public.assign_next_vip(p_order);
end;
$$;

-- Cron: барлық іздеудегі instant заказдар бойынша таратуды жылжыту
create or replace function public.advance_all_vip()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record;
begin
  for r in select id from public.orders
           where type = 'instant' and status = 'searching'
  loop
    perform public.assign_next_vip(r.id);
  end loop;
end;
$$;

-- ==================== VIP ҚАБЫЛДАУ / БАС ТАРТУ ====================
create or replace function public.accept_vip(p_dispatch uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order_id uuid;
  d record;
  o record;
  ep record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select order_id into v_order_id from public.vip_dispatches
  where id = p_dispatch and executor_id = v_uid;
  if v_order_id is null then raise exception 'NOT_FOUND'; end if;

  -- құлыптау реті: order -> dispatch -> executor (deadlock болдырмау)
  select * into o from public.orders where id = v_order_id for update;
  select * into d from public.vip_dispatches where id = p_dispatch for update;

  if d.status <> 'pending' then raise exception 'NOT_PENDING'; end if;

  if d.expires_at <= now() then
    update public.vip_dispatches set status = 'expired' where id = p_dispatch;
    perform public.assign_next_vip(v_order_id);
    raise exception 'EXPIRED';
  end if;

  if o.status <> 'searching' then
    update public.vip_dispatches set status = 'expired' where id = p_dispatch;
    raise exception 'ORDER_TAKEN';
  end if;

  select * into ep from public.executor_profiles where user_id = v_uid for update;
  if ep.busy_order_id is not null then raise exception 'BUSY'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;

  update public.vip_dispatches set status = 'accepted' where id = p_dispatch;
  update public.orders
     set executor_id = v_uid, final_price = system_price,
         status = 'accepted', accepted_at = now()
   where id = v_order_id;
  update public.executor_profiles set busy_order_id = v_order_id where user_id = v_uid;

  return jsonb_build_object('order_id', v_order_id);
end;
$$;

create or replace function public.decline_vip(p_dispatch uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order_id uuid;
  d record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select order_id into v_order_id from public.vip_dispatches
  where id = p_dispatch and executor_id = v_uid;
  if v_order_id is null then raise exception 'NOT_FOUND'; end if;

  perform 1 from public.orders where id = v_order_id for update;
  select * into d from public.vip_dispatches where id = p_dispatch for update;

  if d.status = 'pending' then
    update public.vip_dispatches set status = 'declined' where id = p_dispatch;
    perform public.assign_next_vip(v_order_id);
  end if;
end;
$$;

-- ==================== ҰСЫНЫСТАР (bidding) ====================
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
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_price is null or p_price < 100 then raise exception 'BAD_PRICE'; end if;

  select * into ep from public.executor_profiles where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
  if ep.status <> 'approved' then raise exception 'NOT_APPROVED'; end if;
  if ep.busy_order_id is not null then raise exception 'BUSY'; end if;

  if not exists (select 1 from public.tariff_sessions
                 where executor_id = v_uid and kind = 'simple' and expires_at > now()) then
    raise exception 'NO_SESSION';
  end if;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.type <> 'bidding' or o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;
  if o.size <> ep.vehicle_size then raise exception 'SIZE_MISMATCH'; end if;
  if o.client_id = v_uid then raise exception 'OWN_ORDER'; end if;

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

create or replace function public.withdraw_offer(p_offer uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  update public.offers set status = 'withdrawn'
  where id = p_offer and executor_id = v_uid and status = 'pending';
end;
$$;

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
  ep record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select order_id into v_order_id from public.offers where id = p_offer;
  if v_order_id is null then raise exception 'NOT_FOUND'; end if;

  select * into o from public.orders where id = v_order_id for update;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  select * into ofr from public.offers where id = p_offer for update;
  if ofr.status <> 'pending' then raise exception 'OFFER_GONE'; end if;

  select * into ep from public.executor_profiles
  where user_id = ofr.executor_id for update;
  if ep.status <> 'approved' then raise exception 'EXEC_UNAVAILABLE'; end if;
  if ep.busy_order_id is not null then raise exception 'EXEC_BUSY'; end if;

  update public.offers set status = 'accepted' where id = p_offer;
  update public.offers set status = 'rejected'
   where order_id = v_order_id and id <> p_offer and status = 'pending';
  update public.orders
     set executor_id = ofr.executor_id, final_price = ofr.price,
         status = 'accepted', accepted_at = now()
   where id = v_order_id;
  update public.executor_profiles set busy_order_id = v_order_id
   where user_id = ofr.executor_id;

  return jsonb_build_object('order_id', v_order_id, 'executor_id', ofr.executor_id);
end;
$$;

-- ==================== ЗАКАЗ БАРЫСЫ ====================
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
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_next := p_status::public.order_status;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.executor_id is null or o.executor_id <> v_uid then raise exception 'FORBIDDEN'; end if;

  v_expected := case o.status
    when 'accepted'   then 'arrived'::public.order_status
    when 'arrived'    then 'loading'::public.order_status
    when 'loading'    then 'in_transit'::public.order_status
    when 'in_transit' then 'completed'::public.order_status
    else null
  end;
  if v_expected is null or v_next <> v_expected then raise exception 'BAD_TRANSITION'; end if;

  if v_next = 'completed' then
    update public.orders set status = 'completed', completed_at = now() where id = p_order;
    insert into public.earnings (executor_id, order_id, amount)
    values (v_uid, p_order, coalesce(o.final_price, 0))
    on conflict (order_id) do nothing;
    update public.executor_profiles
       set total_earned = total_earned + coalesce(o.final_price, 0),
           busy_order_id = null
     where user_id = v_uid;
  else
    update public.orders set status = v_next where id = p_order;
  end if;
end;
$$;

create or replace function public.cancel_order(p_order uuid, p_reason text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  if o.client_id <> v_uid and (o.executor_id is null or o.executor_id <> v_uid) then
    raise exception 'FORBIDDEN';
  end if;
  if o.status in ('completed','cancelled','expired') then raise exception 'NOT_AVAILABLE'; end if;
  -- іздеу кезеңінде тек клиент тоқтата алады
  if o.status = 'searching' and o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;

  update public.orders
     set status = 'cancelled', cancelled_by = v_uid,
         cancel_reason = coalesce(trim(p_reason),'')
   where id = p_order;

  update public.vip_dispatches set status = 'expired'
   where order_id = p_order and status = 'pending';
  update public.offers set status = 'rejected'
   where order_id = p_order and status = 'pending';

  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;
end;
$$;

-- ==================== ПІКІР / РЕЙТИНГ ====================
create or replace function public.submit_review(p_order uuid, p_rating int, p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'BAD_RATING'; end if;

  select * into o from public.orders where id = p_order for update;
  if not found or o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status <> 'completed' then raise exception 'NOT_COMPLETED'; end if;
  if o.executor_id is null then raise exception 'NOT_FOUND'; end if;
  if exists (select 1 from public.reviews where order_id = p_order) then
    raise exception 'ALREADY_REVIEWED';
  end if;

  insert into public.reviews (order_id, client_id, executor_id, rating, comment)
  values (p_order, v_uid, o.executor_id, p_rating, coalesce(trim(p_comment),''));

  update public.profiles p
     set rating = sub.avg_r, rating_count = sub.cnt
    from (select round(avg(rating)::numeric, 2) as avg_r, count(*) as cnt
            from public.reviews where executor_id = o.executor_id) sub
   where p.id = o.executor_id;
end;
$$;

-- ==================== БАЛАНС ТОЛТЫРУ ====================
create or replace function public.request_topup(p_amount bigint, p_receipt_path text default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_min bigint;
  v_id uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.executor_profiles where user_id = v_uid) then
    raise exception 'NOT_EXECUTOR';
  end if;
  select coalesce((value->>'min_topup')::bigint, 500) into v_min
    from public.app_settings where key = 'payment';
  if p_amount is null or p_amount < coalesce(v_min, 500) then raise exception 'BAD_AMOUNT'; end if;

  insert into public.topup_requests (executor_id, amount, receipt_path)
  values (v_uid, p_amount, p_receipt_path)
  returning id into v_id;
  return v_id;
end;
$$;

-- ==================== ОРЫНДАУШЫ СТАТИСТИКАСЫ ====================
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
  v_simple timestamptz;
  v_vip timestamptz;
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

  select max(expires_at) into v_simple from public.tariff_sessions
   where executor_id = v_uid and kind = 'simple' and expires_at > now();
  select max(expires_at) into v_vip from public.tariff_sessions
   where executor_id = v_uid and kind = 'vip' and expires_at > now();

  return jsonb_build_object(
    'balance', ep.balance,
    'total_earned', ep.total_earned,
    'today', v_today,
    'month', v_month,
    'busy_order_id', ep.busy_order_id,
    'simple_until', v_simple,
    'vip_until', v_vip,
    'is_night', public.is_night_now(),
    'price_simple', public.tariff_price_now('simple'),
    'price_vip', public.tariff_price_now('vip')
  );
end;
$$;

-- ==================== МОДЕРАТОР ====================
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

  if v_status = 'blocked' then
    update public.tariff_sessions set expires_at = now()
     where executor_id = p_user and expires_at > now();
  end if;
end;
$$;

create or replace function public.mod_review_topup(p_topup uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  t record;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  select * into t from public.topup_requests where id = p_topup for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if t.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  if p_approve then
    update public.topup_requests
       set status = 'approved', note = nullif(trim(coalesce(p_note,'')),''),
           reviewed_by = v_uid, reviewed_at = now()
     where id = p_topup;
    update public.executor_profiles set balance = balance + t.amount
     where user_id = t.executor_id;
    insert into public.balance_txns (executor_id, amount, type, note, ref_id)
    values (t.executor_id, t.amount, 'topup', 'Kaspi толтыру', p_topup);
  else
    update public.topup_requests
       set status = 'rejected', note = nullif(trim(coalesce(p_note,'')),''),
           reviewed_by = v_uid, reviewed_at = now()
     where id = p_topup;
  end if;
end;
$$;

create or replace function public.mod_adjust_balance(p_user uuid, p_amount bigint, p_note text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  update public.executor_profiles set balance = balance + p_amount where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
  insert into public.balance_txns (executor_id, amount, type, note)
  values (p_user, p_amount, 'adjustment', coalesce(trim(p_note),''));
end;
$$;

-- ==================== CRON ТАЗАЛАУ ====================
create or replace function public.expire_stale_orders()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  -- instant: 15 минут ішінде ешкім қабылдамаса
  update public.orders o
     set status = 'expired'
   where o.type = 'instant' and o.status = 'searching'
     and o.created_at < now() - interval '15 minutes'
     and not exists (select 1 from public.vip_dispatches d
                     where d.order_id = o.id and d.status = 'pending' and d.expires_at > now());
  -- bidding: 24 сағаттан ескі
  update public.orders
     set status = 'expired'
   where type = 'bidding' and status = 'searching'
     and created_at < now() - interval '24 hours';
end;
$$;

-- ==================== GRANTS ====================
-- Ішкі функцияларды сыртқа жаппау
revoke execute on function public.assign_next_vip(uuid) from public, anon, authenticated;
revoke execute on function public.advance_all_vip() from public, anon, authenticated;
revoke execute on function public.expire_stale_orders() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

grant execute on function public.buy_tariff(text) to authenticated;
grant execute on function public.create_order(text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint) to authenticated;
grant execute on function public.advance_vip(uuid) to authenticated;
grant execute on function public.accept_vip(uuid) to authenticated;
grant execute on function public.decline_vip(uuid) to authenticated;
grant execute on function public.place_offer(uuid,bigint,text) to authenticated;
grant execute on function public.withdraw_offer(uuid) to authenticated;
grant execute on function public.accept_offer(uuid) to authenticated;
grant execute on function public.order_advance(uuid,text) to authenticated;
grant execute on function public.cancel_order(uuid,text) to authenticated;
grant execute on function public.submit_review(uuid,int,text) to authenticated;
grant execute on function public.request_topup(bigint,text) to authenticated;
grant execute on function public.executor_stats() to authenticated;
grant execute on function public.mod_set_executor_status(uuid,text,text) to authenticated;
grant execute on function public.mod_review_topup(uuid,boolean,text) to authenticated;
grant execute on function public.mod_adjust_balance(uuid,bigint,text) to authenticated;
grant execute on function public.tariff_price_now(text) to authenticated;
grant execute on function public.instant_quote(text,numeric) to authenticated;
grant execute on function public.is_night_now() to authenticated;
grant execute on function public.is_moderator() to authenticated;
