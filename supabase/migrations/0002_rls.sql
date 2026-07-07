-- GazelGo · 0002_rls.sql
-- Row Level Security. Жазу операцияларының көбі security definer RPC арқылы жүреді,
-- сондықтан төмендегі саясаттар негізінен SELECT/шектеулі UPDATE-INSERT үшін.

alter table public.profiles          enable row level security;
alter table public.executor_profiles enable row level security;
alter table public.tariff_sessions   enable row level security;
alter table public.balance_txns      enable row level security;
alter table public.topup_requests    enable row level security;
alter table public.orders            enable row level security;
alter table public.offers            enable row level security;
alter table public.vip_dispatches    enable row level security;
alter table public.reviews           enable row level security;
alter table public.earnings          enable row level security;
alter table public.app_settings      enable row level security;

-- ---------- profiles ----------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---------- executor_profiles ----------
drop policy if exists exec_select on public.executor_profiles;
create policy exec_select on public.executor_profiles
  for select to authenticated
  using (user_id = auth.uid() or status = 'approved' or public.is_moderator());

drop policy if exists exec_insert_own on public.executor_profiles;
create policy exec_insert_own on public.executor_profiles
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'executor')
  );

drop policy if exists exec_update_own on public.executor_profiles;
create policy exec_update_own on public.executor_profiles
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- tariff_sessions ----------
drop policy if exists sessions_select on public.tariff_sessions;
create policy sessions_select on public.tariff_sessions
  for select to authenticated
  using (executor_id = auth.uid() or public.is_moderator());

-- ---------- balance_txns ----------
drop policy if exists txns_select on public.balance_txns;
create policy txns_select on public.balance_txns
  for select to authenticated
  using (executor_id = auth.uid() or public.is_moderator());

-- ---------- topup_requests ----------
drop policy if exists topups_select on public.topup_requests;
create policy topups_select on public.topup_requests
  for select to authenticated
  using (executor_id = auth.uid() or public.is_moderator());

-- ---------- orders ----------
-- клиент өз заказдарын көреді
drop policy if exists orders_client on public.orders;
create policy orders_client on public.orders
  for select to authenticated
  using (client_id = auth.uid());

-- тағайындалған орындаушы өз заказын көреді
drop policy if exists orders_assigned on public.orders;
create policy orders_assigned on public.orders
  for select to authenticated
  using (executor_id = auth.uid());

-- қарапайым тарифтегі орындаушы лентаны көреді (өлшемі сай, іздеудегі bidding)
drop policy if exists orders_feed on public.orders;
create policy orders_feed on public.orders
  for select to authenticated
  using (
    status = 'searching' and type = 'bidding'
    and exists (select 1 from public.executor_profiles ep
                where ep.user_id = auth.uid()
                  and ep.status = 'approved'
                  and ep.vehicle_size = orders.size)
    and exists (select 1 from public.tariff_sessions ts
                where ts.executor_id = auth.uid()
                  and ts.kind = 'simple'
                  and ts.expires_at > now())
  );

-- VIP-ке жіберілген орындаушы өзіне түскен instant заказды көреді
drop policy if exists orders_dispatched on public.orders;
create policy orders_dispatched on public.orders
  for select to authenticated
  using (
    exists (select 1 from public.vip_dispatches d
            where d.order_id = orders.id and d.executor_id = auth.uid())
  );

-- модератор барлық заказды көреді
drop policy if exists orders_moderator on public.orders;
create policy orders_moderator on public.orders
  for select to authenticated
  using (public.is_moderator());

-- ---------- offers ----------
drop policy if exists offers_select on public.offers;
create policy offers_select on public.offers
  for select to authenticated
  using (
    executor_id = auth.uid()
    or exists (select 1 from public.orders o
               where o.id = offers.order_id and o.client_id = auth.uid())
    or public.is_moderator()
  );

-- ---------- vip_dispatches ----------
drop policy if exists dispatch_select on public.vip_dispatches;
create policy dispatch_select on public.vip_dispatches
  for select to authenticated
  using (
    executor_id = auth.uid()
    or exists (select 1 from public.orders o
               where o.id = vip_dispatches.order_id and o.client_id = auth.uid())
    or public.is_moderator()
  );

-- ---------- reviews ----------
drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews
  for select to authenticated using (true);

-- ---------- earnings ----------
drop policy if exists earnings_select on public.earnings;
create policy earnings_select on public.earnings
  for select to authenticated
  using (executor_id = auth.uid() or public.is_moderator());

-- ---------- app_settings ----------
drop policy if exists settings_select on public.app_settings;
create policy settings_select on public.app_settings
  for select to authenticated using (true);
