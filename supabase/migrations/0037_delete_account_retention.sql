-- Tasu · 0037_delete_account_retention.sql
-- Заңды талап: құқық бұзушылық тергелгенде полиция орындаушының
-- құжаттарын/аватарын сұрай алуы мүмкін, сол себепті аккаунт өшірілгенде
-- (анонимделгенде) кейбір Storage файлдары БІРДЕН емес, 30 күннен кейін
-- өшірілуі керек:
--
--   - docs (орындаушы құжаттары): орындаушы КЕМІНДЕ 1 заказды аяқтаған
--     болса — 30 күн сақталады, содан кейін өшіріледі. Ешбір заказды
--     аяқтамаса — бірден өшіріледі (тексеретін ештеңе жоқ).
--   - avatars (клиент/орындаушы): аккаунтта КЕМІНДЕ 1 аяқталған заказ
--     болса (клиент не орындаушы ретінде) — 30 күн сақталады, содан кейін
--     өшіріледі. Аяқталған заказ мүлдем болмаса — бірден өшіріледі.
--
-- (orders/support бакеттерінің 5 күндік тазалауы — 0032/0033 миграциялары,
-- бөлек, өзгеріссіз қалады.)
--
-- Кезек кестесі: delete-account функциясы (service_role) осында жазады,
-- cleanup-storage cron функциясы мерзімі жеткендерін нақты өшіреді.
-- app_secrets (0025) сияқты тәртіп: RLS қосулы, саясат ЖОҚ — тек
-- postgres/service_role оқи/жаза алады, authenticated/anon мүлдем көрмейді.

create table if not exists public.storage_purge_queue (
  id          uuid primary key default gen_random_uuid(),
  bucket      text not null,
  path        text not null,
  purge_after timestamptz not null,
  created_at  timestamptz not null default now()
);
alter table public.storage_purge_queue enable row level security;
-- Саясат ӘДЕЙІ жоқ — тек postgres/service_role.

create index if not exists idx_storage_purge_due
  on public.storage_purge_queue (purge_after);
