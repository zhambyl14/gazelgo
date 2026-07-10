-- GazelGo · 0017_fix_orders_rls_stale.sql
-- Баг: орындаушы заказға ұсыныс бергенде («Келісу» не «Өз бағам») немесе
-- қабылдағанда, ExecutorOrderScreen мәңгі жүктеліп қалады.
--
-- Себебі: orders_feed RLS саясаты (0002_rls.sql) әлі ескі газель-өлшемі
-- моделін қолданады — `ep.vehicle_size = orders.size`. Бірақ 0014-те өлшем
-- логикасы толық алынды (`v_size` әрқашан 'small' болып жазылады,
-- "өлшем ескерілмейді" деген түсініктемемен). Сонымен қатар саясат тариф
-- түрін тексермей, қатаң `ts.kind = 'simple'`-ге қатып қалған — VIP
-- тарифіндегі орындаушы ешбір заказды көре алмайды. Нәтижесінде
-- Repo.orderStream (тікелей `orders` кестесінен, RLS астында) көбіне бос
-- жауап қайтарады. Лентаның өзі бұзылмайды, өйткені executor_feed RPC
-- SECURITY DEFINER болып RLS-ті айналып өтеді — сол себепті баг тек заказ
-- ішіне кіргенде ғана байқалады.
--
-- Түзету: (1) орындаушы ҰСЫНЫС берген заказды тариф/статус қалай болса да
-- көре алатын жаңа саясат (ең маңыздысы — дәл осы бапталмаған сценарийді
-- жабады); (2) orders_feed ағымдағы tariff моделіне сай түзетілді.

drop policy if exists orders_offered on public.orders;
create policy orders_offered on public.orders
  for select to authenticated
  using (
    exists (select 1 from public.offers of
            where of.order_id = orders.id and of.executor_id = auth.uid())
  );

drop policy if exists orders_feed on public.orders;
create policy orders_feed on public.orders
  for select to authenticated
  using (
    status = 'searching' and type = 'bidding'
    and exists (select 1 from public.executor_profiles ep
                where ep.user_id = auth.uid()
                  and ep.status = 'approved')
    and exists (select 1 from public.tariff_sessions ts
                where ts.executor_id = auth.uid()
                  and ts.kind = orders.tariff
                  and ts.expires_at > now())
  );
