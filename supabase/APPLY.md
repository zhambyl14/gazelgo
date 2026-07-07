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
   - `migrations/0011_vip_retry_online_toggle.sql` ← Линия қосу/өшіру, VIP циклдік таратуы

   Егер 0001–0004 бұрын орындалған болса, тек жаңа нөмірленген файлдарды
   ретімен іске қосыңыз (олар қайта орындауға қауіпсіз — idempotent).
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
- `app_settings` кестесінде тарифтер: қарапайым 400₸, VIP 800₸, түнде -50%.
- Kaspi нөмірін өзгерту: `app_settings.payment` → `kaspi_number`, `kaspi_name`.

## Ескертпелер

- Тегін жоспар лимиті: бір аккаунтта 2 белсенді тегін проект. `gazelgo` деп жаңа
  проект құру мүмкін болмады (лимит толы: `qoima` + `xibxaqcrdpgyzohfplda`),
  сондықтан backend осы дайын SQL түрінде сақталды.
- `pg_cron` VIP таратуды 10 секунд сайын жылжытады; клиент қосымшасы да іздеу
  экранында 5 секунд сайын `advance_vip` шақырып, кідірісті азайтады.
