-- Tasu · 0034_orders_support_storage_update_policy.sql
-- Қате: "new row violates row-level security policy" (StorageException,
-- 403) заказ фотосын (кейде support суретін) жүктегенде.
--
-- Себебі: Repo.uploadOrderPhoto / support-хабарлама фото жүктеу
-- (lib/core/repo.dart) `FileOptions(upsert: true)` қолданады. Supabase
-- Storage upsert=true болғанда серверде "INSERT ... ON CONFLICT DO
-- UPDATE" операциясын шығарады — ал Postgres RLS мұндай операцияға
-- ТИІСТІ UPDATE саясаты болуын талап етеді, ТІПТІ нақты конфликт
-- (қайталанған жол) болмаса да. `docs`/`avatars` бакеттерінде
-- `*_update_own` саясаты бар болатын (0004_seed.sql), ал `orders`/
-- `support`-та ЖОҚ болатын — сол себепті INSERT саясатын қанша қайта
-- жасаса да (сурет 403 қалуда еді), нәтиже өзгермейтін.

-- МАҢЫЗДЫ: ON CONFLICT DO UPDATE үшін UPDATE саясатының USING (бар жол)
-- ЖӘНЕ WITH CHECK (жаңа жол) — ЕКЕУІ де керек. Тек USING жеткіліксіз.
drop policy if exists "orders_update_own" on storage.objects;
create policy "orders_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'orders' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'orders' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "support_update_own" on storage.objects;
create policy "support_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'support' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'support' and (storage.foldername(name))[1] = auth.uid()::text);
