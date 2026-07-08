# GazelGo backend-ті қосу (Supabase)

Backend толығымен осы папкада дайын. Оны нақты Supabase проектіге қолданудың 3 жолы бар.

Мақсатты проект: `xibxaqcrdpgyzohfplda` (https://supabase.com/dashboard/project/xibxaqcrdpgyzohfplda)

## 1-жол (ұсынылады): Claude-қа рұқсат беру

1. Қарапайым терминалда (IDE ішінде емес):
   ```
   cd C:\Users\taraz\magazel
   claude
   /mcp
   ```
   `supabase` серверін таңдап → **Authenticate** → браузерде рұқсат бер.
2. Claude Code-ты қайта ашып: **«backend-ті қолдан»** деп жаз.
   Claude миграцияларды ретімен қолданып, edge function-ды deploy жасап,
   `lib/core/env.dart` ішіне anon key-ді өзі жазады.

## 2-жол: SQL Editor арқылы қолмен

1. https://supabase.com/dashboard/project/xibxaqcrdpgyzohfplda/sql/new ашып,
   мына файлдарды **ретімен** орындаңыз:
   - `migrations/0001_init.sql`
   - `migrations/0002_rls.sql`
   - `migrations/0003_rpcs.sql`
   - `migrations/0004_seed.sql`
   - `migrations/0005_fix_rls_recursion.sql`  ← RLS рекурсия түзетуі
   - `migrations/0006_features.sql`           ← аватар, рейтинг, чат, фото т.б.
   - `migrations/0007_mod_and_support.sql`    ← чат-заказ, мод. әрекеттер, статистика
   - `migrations/0008_docs_review_geo.sql`    ← құжат ревью, VIP 20с, тек ҚР ішінде
   - `migrations/0009_line_modstatus.sql`     ← Линия панелі, модератор статус мәжбүрлеу
   - `migrations/0010_storage_cleanup.sql`    ← ескі қолдау чат суреттерін тазалау
   - `migrations/0011_vip_retry_online_toggle.sql` ← Линия қосу/өшіру, VIP циклдік таратуы,
     жауап терезесі 25с, VIP автоматты қабылдау опциясы
   - `migrations/0012_executor_cancel_requeue.sql` ← орындаушы қабылданған заказдан бас
     тартса — «cancelled» емес, қайта «іздеуде» күйіне ашылады; заказда from_city/to_city
     сақталады (адрес форматы, межгород белгісі үшін)
   - `migrations/0013_spec_economy.sql` ← **МАҢЫЗДЫ, спецификацияға толық сай қайта құру**:
     §1 тариф бағасы (Простой 200/150, VIP 400/200 күн/түн); §2 минимум баға (қала ішінде
     100 ₸, межгород 1000 ₸); §3 VIP-те авто ЖОҚ — барлық заказ bidding; §4 тариф = 10 заказ
     пакеті (әр қабылдау −1); §5 межгород маршрутымен қосымша заказ; §6 газелист тек өз
     қаласынан шығатын заказды көреді; §7 расталған газелиске 24 сағат тегін тариф.
     Жаңа RPC-лер: `executor_feed`, `set_executor_city`; өзгергені: `buy_tariff`,
     `create_order`, `place_offer`, `accept_offer`, `executor_stats`, `tariff_price_now`,
     `mod_set_executor_status`. «instant» авто-тарату кроны өшіріледі.

   Егер 0001–0004 бұрын орындалған болса, тек жаңа нөмірленген файлдарды
   ретімен іске қосыңыз (олар қайта орындауға қауіпсіз — idempotent).
   **0013-ті ең соңынан, 0001–0012 қолданылған соң орындаңыз.**
2. Edge function: Dashboard → Edge Functions → **Deploy new function** →
   аты `signup`, коды `functions/signup/index.ts`, **Verify JWT = OFF**.
3. Dashboard → Settings → API → `anon` / `publishable` key-ді көшіріп,
   `lib/core/env.dart` ішіндегі `supabaseAnonKey` мәніне қойыңыз.

## 3-жол: Supabase CLI

```
supabase link --project-ref xibxaqcrdpgyzohfplda
supabase db push
supabase functions deploy signup --no-verify-jwt
```

## Тексеру

- Модератор кіру: `moderator@gazelgo.kz` / `GazelGo#2026` (кірген соң құпиясөзді ауыстырыңыз!)
- `app_settings` кестесінде тарифтер (0013 соң): Простой 200₸ (түн 150), VIP 400₸ (түн 200).
  Минимум баға: `order_min` → қала ішінде 100, межгород 1000.
- Kaspi нөмірін өзгерту: `app_settings.payment` → `kaspi_number`, `kaspi_name`.
- 0013 соң тексеру: газелист өтінімде **қала** таңдайды; расталғанда 24 сағат тегін триал
  беріледі; тариф сатып алса 10 заказ болады; клиент заказы тек bidding (баға өзі қояды).

## Ескертпелер

- Тегін жоспар лимиті: бір аккаунтта 2 белсенді тегін проект. `gazelgo` деп жаңа
  проект құру мүмкін болмады (лимит толы: `qoima` + `xibxaqcrdpgyzohfplda`),
  сондықтан backend осы дайын SQL түрінде сақталды.
- `pg_cron` VIP таратуды 10 секунд сайын жылжытады; клиент қосымшасы да іздеу
  экранында 5 секунд сайын `advance_vip` шақырып, кідірісті азайтады.
