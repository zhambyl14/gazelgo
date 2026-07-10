-- GazelGo · 0020_account_deletion_anonymize.sql
-- 0016-дағы delete-account функциясы `auth.admin.deleteUser()` арқылы
-- profiles жолын CASCADE-пен өшіретін — бірақ бұл ЕКІ БАГ тудырады:
--
-- 1) orders.executor_id FK-да ON DELETE CASCADE ЖОҚ (тек client_id-де бар).
--    Кез келген заказ тарихы бар орындаушы аккаунтын өшіргенде FK қатесімен
--    сәтсіз аяқталатын еді (DELETE_FAILED).
-- 2) orders.client_id CASCADE болғандықтан, клиент аккаунтын өшірсе — сол
--    заказдардағы ҚАРСЫ ТАРАПТЫҢ (орындаушының) earnings/reviews жазбалары
--    да CASCADE-пен жоғалып кетеді (executor_id арқылы earnings/reviews
--    orders(id)-ге cascade тәуелді).
--
-- Түзету: аккаунт енді ӨШІРІЛМЕЙДІ — АНОНИМДЕЛЕДІ (jeke дерек мәңгі
-- өшіріледі, кіру мүмкіндігі жабылады, ал заказ транзакциялары GPS/баға/
-- уақытымен сақталады — заң бұзушылықты тергеу үшін де, қарсы тараптың
-- өз тарихын жоғалтпауы үшін де). Толық логика: functions/delete-account.

alter table public.profiles
  add column if not exists deleted_at timestamptz;
