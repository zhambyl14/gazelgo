-- GazelGo · 0005_fix_rls_recursion.sql
-- Түзету: orders ↔ vip_dispatches (және offers → orders) саясаттары бір-біріне
-- сілтеме жасап, "infinite recursion detected in policy" қатесін тудырды.
-- Шешім: subquery-лерді SECURITY DEFINER функцияларға ауыстыру (олар RLS-ті
-- айналып өтеді → цикл үзіледі).

-- Мен осы заказдың клиентімін бе?
create or replace function public.is_order_client(p_order uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.orders
    where id = p_order and client_id = auth.uid()
  );
$$;

-- Маған осы заказ бойынша VIP тарату жіберілген бе?
create or replace function public.has_my_dispatch(p_order uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.vip_dispatches
    where order_id = p_order and executor_id = auth.uid()
  );
$$;

grant execute on function public.is_order_client(uuid) to authenticated;
grant execute on function public.has_my_dispatch(uuid) to authenticated;

-- orders: dispatched саясатын definer-функциямен қайта құру
drop policy if exists orders_dispatched on public.orders;
create policy orders_dispatched on public.orders
  for select to authenticated
  using (public.has_my_dispatch(id));

-- vip_dispatches: orders-ке тікелей subquery-ні алып тастау
drop policy if exists dispatch_select on public.vip_dispatches;
create policy dispatch_select on public.vip_dispatches
  for select to authenticated
  using (
    executor_id = auth.uid()
    or public.is_order_client(order_id)
    or public.is_moderator()
  );

-- offers: orders-ке тікелей subquery-ні алып тастау
drop policy if exists offers_select on public.offers;
create policy offers_select on public.offers
  for select to authenticated
  using (
    executor_id = auth.uid()
    or public.is_order_client(order_id)
    or public.is_moderator()
  );
