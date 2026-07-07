-- GazelGo · 0009_line_modstatus.sql
-- Модератор: заказ статусын өзгерту + «Линия» (онлайн орындаушылар, іздеудегі заказдар).

-- ============ модератор: заказ статусын мәжбүрлі өзгерту ============
create or replace function public.mod_set_order_status(p_order uuid, p_status text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_next public.order_status;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  v_next := p_status::public.order_status;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status = v_next then return; end if;

  if v_next = 'completed' then
    if o.executor_id is null then raise exception 'NO_EXECUTOR'; end if;
    update public.orders set status = 'completed', completed_at = now()
     where id = p_order;
    insert into public.earnings (executor_id, order_id, amount)
    values (o.executor_id, p_order, coalesce(o.final_price, 0))
    on conflict (order_id) do nothing;
    update public.executor_profiles
       set total_earned = total_earned + coalesce(o.final_price, 0),
           busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
    update public.profiles set trips = trips + 1
     where id in (o.client_id, o.executor_id);
  elsif v_next = 'cancelled' then
    perform public.mod_cancel_order(p_order, 'статус түзету');
  elsif v_next in ('accepted','arrived','loading','in_transit') then
    if o.executor_id is null then raise exception 'NO_EXECUTOR'; end if;
    update public.orders set status = v_next where id = p_order;
    -- орындаушының busy күйін қалпына келтіру
    update public.executor_profiles set busy_order_id = p_order
     where user_id = o.executor_id;
  elsif v_next = 'searching' then
    perform public.mod_reopen_order(p_order);
  else
    raise exception 'BAD_STATUS';
  end if;
end;
$$;

-- ============ модератор: «Линия» статистикасы ============
create or replace function public.mod_line_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_searching_bidding int;
  v_searching_instant int;
  v_active_orders int;
  v_online jsonb;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  select count(*) into v_searching_bidding from public.orders
   where status = 'searching' and type = 'bidding';
  select count(*) into v_searching_instant from public.orders
   where status = 'searching' and type = 'instant';
  select count(*) into v_active_orders from public.orders
   where status in ('accepted','arrived','loading','in_transit');

  -- онлайн орындаушылар (белсенді сессиясы барлар)
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_online
  from (
    select ep.user_id,
           p.full_name,
           p.avatar_url,
           ep.vehicle_size,
           ep.busy_order_id,
           exists (select 1 from public.tariff_sessions ts
                   where ts.executor_id = ep.user_id
                     and ts.kind = 'simple' and ts.expires_at > now()) as simple_on,
           exists (select 1 from public.tariff_sessions ts
                   where ts.executor_id = ep.user_id
                     and ts.kind = 'vip' and ts.expires_at > now()) as vip_on
    from public.executor_profiles ep
    join public.profiles p on p.id = ep.user_id
    where ep.status = 'approved'
      and exists (select 1 from public.tariff_sessions ts
                  where ts.executor_id = ep.user_id and ts.expires_at > now())
    order by p.full_name
  ) t;

  return jsonb_build_object(
    'searching_bidding', v_searching_bidding,
    'searching_instant', v_searching_instant,
    'active_orders', v_active_orders,
    'online', v_online
  );
end;
$$;

grant execute on function public.mod_set_order_status(uuid,text) to authenticated;
grant execute on function public.mod_line_stats() to authenticated;
