-- GazelGo · 0027_client_confirms_loading.sql
-- Заказ барысындағы «тиеу» қадамын енді КЛИЕНТ растайды (орындаушы емес).
-- Мақсат: орындаушы шынымен келгенін клиент растасын — сол расталмайынша
-- орындаушы «жолға шықтық» дей алмайды (жалған «келдім/тиедім» алдын алу).
--
-- Жаңа рөлдік ауысулар:
--   accepted   → arrived      : тек ОРЫНДАУШЫ («Келдім»)
--   arrived    → loading      : тек КЛИЕНТ  («Тиеу басталды» — растау)
--   loading    → in_transit   : тек ОРЫНДАУШЫ («Жолға шықтық»)
--   in_transit → completed    : тек ОРЫНДАУШЫ («Аяқтау»)

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
  else
    update public.orders set status = v_next where id = p_order;
  end if;
end;
$$;
grant execute on function public.order_advance(uuid,text) to authenticated;
