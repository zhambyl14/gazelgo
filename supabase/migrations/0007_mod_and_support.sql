-- GazelGo · 0007_mod_and_support.sql
-- Қолдау чатына заказ контексті, модератордың заказ әрекеттері, орындаушы статистикасы.

-- ============ support_threads: заказ байланысы ============
alter table public.support_threads
  add column if not exists order_id uuid references public.orders(id) on delete set null;

-- support_send: p_order_id параметрін қосу
drop function if exists public.support_send(text, text);
create or replace function public.support_send(
  p_body text, p_image_path text default null, p_order_id uuid default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_thread uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if coalesce(trim(p_body),'') = '' and p_image_path is null then raise exception 'EMPTY'; end if;

  select id into v_thread from public.support_threads
   where user_id = v_uid and status = 'open'
   order by created_at desc limit 1;

  if v_thread is null then
    insert into public.support_threads
      (user_id, order_id, last_sender_role, last_user_msg_at, last_msg_at)
    values (v_uid, p_order_id, 'user', now(), now())
    returning id into v_thread;
  else
    update public.support_threads
       set last_sender_role = 'user', last_user_msg_at = now(), last_msg_at = now(),
           order_id = coalesce(p_order_id, order_id)
     where id = v_thread;
  end if;

  insert into public.support_messages (thread_id, sender_id, sender_role, body, image_path)
  values (v_thread, v_uid, 'user', coalesce(trim(p_body),''), p_image_path);
  return v_thread;
end;
$$;

grant execute on function public.support_send(text,text,uuid) to authenticated;

-- ============ модератор: заказды мәжбүрлі тоқтату ============
create or replace function public.mod_cancel_order(p_order uuid, p_reason text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status in ('completed','cancelled','expired') then raise exception 'NOT_AVAILABLE'; end if;

  update public.orders
     set status = 'cancelled', cancelled_by = v_uid,
         cancel_reason = 'Модератор: ' || coalesce(trim(p_reason),'')
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

-- ============ модератор: заказды қайта ашу / басқа орындаушыға ұсыну ============
create or replace function public.mod_reopen_order(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  -- ағымдағы орындаушыны босату
  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;

  update public.orders
     set status = 'searching', executor_id = null, accepted_at = null,
         final_price = null
   where id = p_order;

  -- ескі ұсыныстар/таратуларды тазарту
  update public.offers set status = 'rejected'
   where order_id = p_order and status in ('pending','accepted');
  update public.vip_dispatches set status = 'expired'
   where order_id = p_order and status = 'pending';

  -- instant болса — қайта тарату
  if o.type = 'instant' then
    perform public.assign_next_vip(p_order);
  end if;
end;
$$;

-- ============ модератор: орындаушы статистикасы ============
create or replace function public.mod_executor_summary(p_user uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_day timestamptz;
  v_week timestamptz;
  v_today int; v_week_cnt int; v_total int;
  v_active int; v_cancelled int;
  v_earned_today bigint; v_earned_total bigint;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  v_day := date_trunc('day', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';
  v_week := now() - interval '7 days';

  select count(*) into v_today from public.orders
   where executor_id = p_user and status = 'completed' and completed_at >= v_day;
  select count(*) into v_week_cnt from public.orders
   where executor_id = p_user and status = 'completed' and completed_at >= v_week;
  select count(*) into v_total from public.orders
   where executor_id = p_user and status = 'completed';
  select count(*) into v_active from public.orders
   where executor_id = p_user
     and status in ('accepted','arrived','loading','in_transit');
  select count(*) into v_cancelled from public.orders
   where executor_id = p_user and status = 'cancelled' and cancelled_by = p_user;
  select coalesce(sum(amount),0) into v_earned_today from public.earnings
   where executor_id = p_user and created_at >= v_day;
  select coalesce(sum(amount),0) into v_earned_total from public.earnings
   where executor_id = p_user;

  return jsonb_build_object(
    'today', v_today, 'week', v_week_cnt, 'total', v_total,
    'active', v_active, 'cancelled', v_cancelled,
    'earned_today', v_earned_today, 'earned_total', v_earned_total
  );
end;
$$;

grant execute on function public.mod_cancel_order(uuid,text) to authenticated;
grant execute on function public.mod_reopen_order(uuid) to authenticated;
grant execute on function public.mod_executor_summary(uuid) to authenticated;
