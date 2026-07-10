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

   - `migrations/0014_tariff_orders_corrections.sql` ← **МАҢЫЗДЫ**: газель ӨЛШЕМІ
     алынды; заказ түрі = Простой/VIP санаты (клиент таңдайды, екеуі де bidding);
     орындаушы өз тарифінің заказдарын ғана көреді (лента бөлек). **ТАРИФ = 1
     АУЫСЫМ (12 сағат: 08:00–20:00 не 20:00–08:00), сол ауысымда МАКС 10 заказ**
     (`buy_tariff` → `expires_at = current_window_end()`, `orders_left = 10`).
     Ауысым бітсе НЕ 10 заказ алынса — тариф жабылады; белсенді тұрғанда сол
     тарифті қайта сатып алуға болмайды (`ALREADY_ACTIVE`). Простой мен VIP —
     бөлек: әрқайсысының ауысымы да, 10 лимиті де өз тұсында (`simple_left`/
     `vip_left`/`simple_until`/`vip_until`). VIP тариф тек көлік жылы жаңа болса
     қосылады (`app_settings.vehicle_rules.vip_min_year`, әдепкі 2010); адрес
     түзетулері (`address_corrections` + `nearby_address`/`save_address_correction`);
     жаңа құжат өрістері (права+селфи, куәлік+селфи, шетел паспорты+селфи).

   - `migrations/0015_sms_otp_auth.sql` ← ҚАЖЕТ ЕМЕС (SMS-код ағынынан бас
     тарттық — Mobizon ақылы). Орындасаңыз да зиян жоқ, бірақ қолданылмайды.
   - `migrations/0016_moderator_phone_login.sql` ← **МАҢЫЗДЫ, егер 0004 бұрын
     орындалған болса**: модератор аккаунты бұрын email-мен (`moderator@
     gazelgo.kz`) құрылған еді, ал LoginScreen енді тек телефон қабылдайды —
     осы миграция бар аккаунтты `+7 700 000 00 01` телефонына көшіреді
     (құпиясөз өзгермейді: `GazelGo#2026`). Жаңа орнатуларда 0004 бірден
     телефон-негізді жасайды, 0016 сонда ештеңе істемейді (idempotent).
   - `migrations/0017_fix_orders_rls_stale.sql` ← **МАҢЫЗДЫ БАГ ТҮЗЕТУІ**:
     орындаушы заказға ұсыныс/қабылдау жібергенде экран мәңгі жүктеліп
     қалатын (spinner тоқтамайтын) баг — `orders_feed` RLS саясаты әлі
     0014-те алынған газель-өлшемі моделін қолданатын. Осы миграция орындаушы
     ұсыныс берген заказды әрқашан көре алатындай саясат қосады және
     orders_feed-ті tariff моделіне сай түзетеді.
   - `migrations/0018_abuse_limits.sql` ← **Анти-спам («комитет аудиті»)**:
     клиент соңғы сағатта 3 заказды өзі тоқтатса — жаңа заказ уақытша
     бұғатталады (TOO_MANY_CANCELS триггері); `auth_events` кестесі —
     signup-тың IP-лимиті үшін (сағатына 5 тіркелу) + күнделікті тазалау
     cron-ы.
   - `migrations/0019_push_notifications.sql` ← **Push-хабарландырулар**:
     `push_tokens` кестесі + `save_push_token` RPC + газелист жаңа/қайта
     өтінім жібергенде барлық модераторға автоматты push жіберетін триггер
     (`pg_net` арқылы `push-notify` функциясын шақырады). Толық баптау —
     төмендегі бөлек бөлімде.
   - `migrations/0020_account_deletion_anonymize.sql` ← **МАҢЫЗДЫ БАГ
     ТҮЗЕТУІ**: `profiles.deleted_at` бағаны қосады. Себебі: 0016-дағы
     delete-account `auth.admin.deleteUser()` арқылы profiles-ті CASCADE-пен
     өшіретін — бірақ `orders.executor_id`-де CASCADE жоқ болғандықтан, заказ
     тарихы бар кез келген орындаушы аккаунтын өшіре алмай қалатын (FK
     қатесі), әрі `orders.client_id` CASCADE болғандықтан клиент өшірсе
     қарсы тараптың (орындаушының) earnings/reviews жазбалары да жоғалып
     кететін. Жаңа `delete-account` (қайта deploy керек, төменде) енді
     профильді ӨШІРМЕЙДІ — жеке дерек мәңгі тазаланады, кіру мүмкіндігі
     жабылады, ал заказ транзакциялары (GPS/баға/уақыт) сақталады.
   - `migrations/0021_order_reports.sql` ← **«Күдікті жүк туралы
     хабарлау»**: `order_reports` кестесі + `report_order` RPC — клиент/
     орындаушы заказ бойынша модераторға дереу белгі бере алады (хабарлама
     қолдау чатына автоматты түседі, бөлек модератор UI қажет емес).
   - `migrations/0022_fraud_flags.sql` ← **Жеңіл алаяқтық-эвристикасы**:
     `order_fraud_flags` RPC — модератор заказды ашқанда, сол client+executor
     жұбы соңғы 30 күнде қайталанса не жаңа аккаунт+жоғары баға тіркесімі
     болса, ескерту көрсетеді (статистика ғана, ML емес).
   - `migrations/0023_citizenship_tech_docs.sql` ← **МАҢЫЗДЫ, бұрыннан бар
     багты түзетеді**: `tech_passport_path` бағаны кестеде 0001-ден бері бар
     еді, бірақ өтінім экраны оны ешқашан жинамаған — модератор техпаспортты
     тексере алмайтын. Енді: (1) азаматтыққа қарай жеке құжат — ҚР азаматына
     жеке куәлік+селфи, шетелдікке паспорт+селфи (екеуі бірдей талап
     етілмейді); (2) көліктің техпаспорты+онымен фото енді екі жағдайда да
     МІНДЕТТІ (жаңа баған `tech_passport_selfie_path`); (3) модератордың
     өтінім/құжат-жаңарту/орындаушы-профиль терезелері енді осы толық
     жиынтықты (селфилерімен қоса) көрсетеді, азаматтыққа сай ғана тиісті
     құжатты сұрайды.
   - `migrations/0024_trust_score.sql` ← **Сенім деңгейі + автоматты блок**:
     `profiles.trust_score` (әдепкі 100), `blocked_at`, `block_reason`.
     Әр «Күдікті жүк туралы хабарлау» хабарланған тараптың баллын −15
     азайтады; 50-ден төмен түссе аккаунт автоматты бұғатталады (жаңа
     заказ/ұсыныс бере алмайды, бар тарихы бұзылмайды). Модераторда жаңа
     «Хабарламалар» табы (`ReportsScreen`) + заказ терезесіндегі клиент/
     орындаушы карточкасын басу арқылы қолмен балл түзету/блоктау
     (`mod_adjust_trust_score`, `mod_set_account_blocked`). Бұғатталған
     аккаунт енді қосымшаға МҮЛДЕМ кіре алмайды (`BlockedScreen`, main.dart).
     Сонымен қатар: «Күдікті жүк туралы хабарлау» енді ТЕК орындаушыға
     (клиент батырмасы алынды, RPC да FORBIDDEN қайтарады).
   - `migrations/0025_push_message_notifications.sql` ← **Чат push-тары**:
     бұрын тек модератор жаңа өтінім туралы FCM алатын, қолдау чатының
     хабарламалары қосымша ЖАБЫҚ тұрғанда мүлдем жетпейтін. Жаңа ортақ
     `send_push()` RPC (target_user_ids болмаса — барлық модератор,
     ескімен үйлесімді) + `notify_support_message` триггері (модератор
     жауап берсе — нақты сол пайдаланушыға, пайдаланушы жазса — барлық
     модераторға). **МАҢЫЗДЫ: `push-notify` edge function-ды ҚАЙТА deploy
     ету керек** (жалпы title/body/target_user_ids форматына көшті —
     төмендегі 2-қадамды қараңыз).

   - `migrations/0026_telegram_verification.sql` ← **Telegram телефон
     растау** (SMS-сіз, тегін): `telegram_verifications` кестесі +
     `tg_start_verification`/`tg_check_verification` RPC. Тіркелу енді нөмірді
     Telegram бот арқылы растайды (пайдаланушы ботта «Нөмірімді бөлісу»
     түймесін басады, Telegram нөмірді өзі растайды). Толық баптау төменде
     «Telegram верификация» бөлімінде. **МАҢЫЗДЫ: `signup` функциясы енді
     `tg_token` талап етеді — ҚАЙТА deploy керек.**

   Егер 0001–0004 бұрын орындалған болса, тек жаңа нөмірленген файлдарды
   ретімен іске қосыңыз (олар қайта орындауға қауіпсіз — idempotent).
   **0013, содан соң 0014, 0016, 0017, 0018, 0019, 0020, 0021, 0022, 0023,
   0024, 0025, ең соңынан 0026-ны орындаңыз.**
2. Edge functions: Dashboard → Edge Functions → **Deploy new function**:
   - аты `signup`, коды `functions/signup/index.ts`, **Verify JWT = OFF** —
     тіркелу осы функция арқылы (SMS-сыз, email растауын айналып өтеді).
     Аккаунттар синтетикалық email арқылы құрылады
     (`7XXXXXXXXXX@phone.gazelgo.kz`) — Supabase-тің телефон провайдерін де,
     SMS қызметін де баптау қажет ЕМЕС. **МАҢЫЗДЫ (0026 соң): енді `tg_token`
     талап етеді (Telegram-мен расталған нөмір), нөмір клиенттен емес, сол
     расталған жазбадан алынады — ҚАЙТА deploy жасаңыз.** IP бойынша
     rate-limit бар (0018-дегі auth_events кестесімен).
   - аты `telegram-webhook`, коды `functions/telegram-webhook/index.ts`,
     **Verify JWT = OFF** — Telegram боттың вебхукы (телефон растау). Толық
     баптау төмендегі «Telegram верификация» бөлімінде.
   - аты `delete-account`, коды `functions/delete-account/index.ts`,
     **Verify JWT = ON** — App Store/Play Market-тің «аккаунтты өшіру»
     талабы. **МАҢЫЗДЫ: бұрын deploy жасаған болсаңыз, ҚАЙТА deploy
     жасаңыз** — логикасы толық өзгерді (0020-ны қараңыз): енді өшірудің
     орнына анонимдейді, сондықтан алдымен 0020 миграциясын қолданыңыз.
   - аты `push-notify`, коды `functions/push-notify/index.ts`,
     **Verify JWT = OFF** (`pg_net` JWT жібермейді — орнына құпия
     `x-push-secret` header тексеріледі). Төмендегі «Push-хабарландырулар»
     бөлімін толық орындаңыз, әйтпесе бос жауап қайтарып, ештеңе жібермейді.
     **МАҢЫЗДЫ (0025 соң): бұрын deploy жасаған болсаңыз, ҚАЙТА deploy
     жасаңыз** — payload форматы `{applicant_name,is_resubmit}`-тен жалпы
     `{title,body,data,target_user_ids}`-ке көшті (қолдау чаты push-тары
     үшін). Ескі функция денесі жаңа `send_push()` RPC жіберетін өрістерді
     танымайды.
   - `functions/otp/` — ҚАЖЕТ ЕМЕС (SMS ағыны алынды), deploy жасамаңыз.

   **Edge Function Secrets**: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` —
   платформа автоматты береді, қолмен ештеңе қою қажет емес.

   Құпиясөзді ұмытқан пайдаланушылар қолдау қызметіне (WhatsApp) жазады —
   нөмірін `lib/core/env.dart` → `supportWhatsApp` ішіне қойыңыз. Модератор
   Dashboard → Authentication → Users бетінен пайдаланушыны тауып
   («7XXXXXXXXXX@phone.gazelgo.kz» email-і арқылы) жаңа құпиясөз орната алады.
3. Dashboard → Settings → API → `anon` / `publishable` key-ді көшіріп,
   `lib/core/env.dart` ішіндегі `supabaseAnonKey` мәніне қойыңыз.

## Telegram верификация (тіркелуде телефон растау — SMS-сіз, тегін)

Неге: SMS ақылы (Mobizon т.б.), ал Telegram боты арқылы нөмірді растау —
тегін әрі сенімді. Пайдаланушы ботта «📱 Нөмірімді бөлісу» түймесін
басқанда Telegram нөмірді ӨЗІ растап береді (жалған нөмір беру мүмкін емес).
Код (сан) қажет емес — контакт бөлісудің өзі растау болып табылады.

**ЕСКЕРТУ**: бұл әр пайдаланушыда Telegram болуын талап етеді, әрі аккаунт
телефоны = Telegram нөмірі болады.

### 1-қадам: Бот
1. [@BotFather](https://t.me/BotFather) → `/newbot` (немесе бар боты
   қолданыңыз). Username-ін жазып қойыңыз (мыс. `gazelgobot`) — оны
   `lib/core/env.dart` → `Env.telegramBot` ішіне қойыңыз (@-сыз).
2. **Токенді ешкімге жарияламаңыз.** Егер токен бір жерде ашылып қалса —
   BotFather → `/revoke` арқылы жаңасын алыңыз.

### 2-қадам: Edge Function Secrets (Dashboard → Edge Functions → Manage secrets)
- `TELEGRAM_BOT_TOKEN` — BotFather берген токен.
- `TELEGRAM_WEBHOOK_SECRET` — өзіңіз ойлап тапқан кез келген ұзын құпия жол
  (мыс. `openssl rand -hex 32`). Telegram әр сұраныста осыны header-мен
  жібереді, функция соны тексереді (бөгде сұраныстарды сүзу үшін).

### 3-қадам: `telegram-webhook` функциясын deploy жасаңыз
Dashboard → Edge Functions → Deploy new function, аты `telegram-webhook`,
коды `functions/telegram-webhook/index.ts`, **Verify JWT = OFF**.

### 4-қадам: Вебхукты Telegram-ға тіркеу
Браузерде (не терминалда) осы URL-ды бір рет ашыңыз — `<TOKEN>`,
`<SECRET>`-ті нақты мәндермен ауыстырыңыз:
```
https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/telegram-webhook&secret_token=<SECRET>
```
`{"ok":true,"result":true,...}` қайтса — сәтті. (`<SECRET>` дәл 2-қадамдағы
`TELEGRAM_WEBHOOK_SECRET`-пен бірдей болуы шарт.)

### Тексеру
Қосымшада тіркелуде «Telegram арқылы растау» → бот ашылады → «Нөмірімді
бөлісу» → қосымшаға оралғанда нөмір жасыл «расталды» болып көрінуі керек.
Жұмыс істемесе: Dashboard → Edge Functions → `telegram-webhook` → Logs.

## Push-хабарландырулар (модератор — жаңа өтінім, қосымша жабық болса да)

Неге керек: газелист тіркелу өтінімін жіберген сайын, модератор оны ТЕЗ көруі
керек — телефоны құлыпты не қосымша толық жабық болса да. Мұны тек Firebase
Cloud Messaging (FCM) арқылы шешуге болады (`flutter_local_notifications`
тек қосымша тірі/фонда тұрғанда жұмыс істейді). Mac/Xcode КЕРЕК ЕМЕС — бәрі
Firebase Console (веб-браузер) мен Supabase Dashboard арқылы жасалады.

### 1-қадам: Firebase жоба құру
1. https://console.firebase.google.com → **Add project** → атын жазыңыз
   (мыс. `GazelGo`) → Google Analytics міндетті емес, өшіре беріңіз.
2. Жоба ішінде **⚙️ Project settings → General → Your apps** → әр
   платформаны қосыңыз:
   - **Android**: package name дәл `kz.gazelgo.app` деп жазыңыз (SHA-сертификат
     сұраса — осы кезеңде қажет емес, өткізіп жіберуге болады).
   - **iOS**: Bundle ID дәл `kz.gazelgo.app` деп жазыңыз.
3. Әр қосылған қосымшаның **SDK setup and configuration → Config** бөлімінен
   мәндерді (apiKey, appId, messagingSenderId, projectId, storageBucket)
   көшіріп, [lib/core/firebase_options.dart](../lib/core/firebase_options.dart)
   ішіндегі тиісті бөлімге (`android`/`ios`) қойыңыз. iOS үшін
   `iosBundleId` өзгертпей қалдырыңыз.
4. **Cloud Messaging** қосулы тұрғанын тексеріңіз: ⚙️ Project settings →
   **Cloud Messaging** табы — «Firebase Cloud Messaging API (V1)» **Enabled**
   болуы керек (әдетте автоматты қосулы тұрады).

### 2-қадам: Service account кілті (edge function FCM жіберу үшін)
1. ⚙️ Project settings → **Service accounts** табы → **Generate new private
   key** → JSON файл жүктеледі. **Бұл файлды ешкіммен бөліспеңіз, репоға
   қоспаңыз.**
2. Файлдың ІШІНДЕГІ МӘТІНДІ (толық JSON) көшіріп алыңыз — келесі қадамда
   керек болады.
3. Сол JSON-дағы `project_id` мәнін жазып қойыңыз (мыс. `gazelgo-xxxxx`).

### 3-қадам: Supabase жағы
1. **Edge Function Secrets** (Dashboard → Edge Functions → Manage secrets)
   үшеуін қосыңыз:
   - `FCM_PROJECT_ID` — 2-қадамдағы `project_id`.
   - `FCM_SERVICE_ACCOUNT_JSON` — 2-қадамда жүктелген JSON файлдың **толық
     мазмұны** (бір жол ретінде, тұтас JSON мәтінін қойса болады).
   - `PUSH_TRIGGER_SECRET` — өзіңіз ойлап тапқан кез келген ұзын құпия жол
     (мыс. терминалда `openssl rand -hex 32` командасымен жасаңыз).
2. SQL Editor-да (0025 миграциясы қолданылған СОҢ, БІР РЕТ) осы команданы
   орындаңыз — 3.1-дегімен **дәл сол бір** `PUSH_TRIGGER_SECRET` мәнін
   қойыңыз. (Ескі `alter database ... set app.settings...` Supabase
   хостингте ЕНДІ РҰҚСАТ ЕТІЛМЕЙДІ — сол себепті құпия сөз енді
   `app_secrets` кестесінде, RLS-пен құлыпталған.)
   ```sql
   insert into public.app_secrets (key, value)
   values ('push_trigger_secret', 'СІЗДІҢ_ҚҰПИЯ_ЖОЛЫҢЫЗ')
   on conflict (key) do update set value = excluded.value;
   ```
   (Мәнді дәл 3.1-дегімен бірдей жазыңыз — екеуі сәйкес келмесе, edge function
   `FORBIDDEN` қайтарып, push жіберілмейді.)
3. `push-notify` функциясын **Verify JWT = OFF** етіп deploy жасаңыз
   (жоғарыдағы 2-қадамды қараңыз). **Кода өрісіне JSON емес, тек
   `supabase/functions/push-notify/index.ts` файлының өзіндегі TypeScript
   мәтінін қойыңыз** — JSON кілт бөлек «Manage secrets» өрісіне ғана барады.

### 4-қадам: Android/iOS — қосымша өзгерту қажет емес
`google-services.json`/`GoogleService-Info.plist` файлдарын Xcode-қа/Gradle-ге
қосудың орнына, барлық баптау `firebase_options.dart`-тағы Dart
константалары арқылы жүреді — Gradle/Xcode файлдарына қол тигізілмеген.

### Тексеру
Жоғарыдағы бәрін орындаған соң: модератор аккаунтпен кемінде бір рет
қосымшаны ашуы керек (токенін тіркеу үшін), содан соң газелист жаңа өтінім
жіберсе — модератордың телефонына push келуі керек (қосымша жабық болса да).
Push келмесе — Supabase Dashboard → Edge Functions → `push-notify` → Logs
бөлімінен қатені қараңыз.

## Сторға шығар алдындағы тізім (App Store / Play Market)

- **Құпиялылық саясаты URL**: екі стор да консольде жария URL сұрайды.
  Қосымша ішіндегі мәтін (lib/features/legal/legal_screen.dart) дайын —
  соны GitHub Pages-ке де қойыңыз (репоға `docs/privacy.html` қосып,
  Settings → Pages қосу жеткілікті) және сол сілтемені консольдерге беріңіз.
- **Аккаунтты өшіру**: қосымшада бар (Профиль → Аккаунтты өшіру) —
  `delete-account` функциясы deploy болуы шарт. Google Play қосымша
  «веб-сілтеме» да сұрайды — сол privacy бетіне «аккаунтты қосымша ішінен
  өшіруге болады» деген бөлім қосыңыз.
- **Data safety (Play) / App Privacy (Apple)** формасында: аты-жөні,
  телефон, геолокация (precise), фотолар, құжаттар (executor) — «жиналады,
  үшінші тарапқа берілмейді, аккаунтпен байланысты» деп белгілеңіз.
- **Оператор деректемелері**: legal_screen.dart мәтініндегі байланыс бөліміне
  нақты ЖК/компания атауы мен деректемелерді қосып қойған жөн (стор
  тексерушілері заңды тұлғаны көргісі келеді).

## 3-жол: Supabase CLI

```
supabase link --project-ref xibxaqcrdpgyzohfplda
supabase db push
supabase functions deploy signup --no-verify-jwt
```

## Тексеру

- Модератор кіру: телефон `+7 700 000 00 01`, құпиясөз `GazelGo#2026`
  (кірген соң профильден құпиясөзді ауыстырыңыз! Ескі `moderator@gazelgo.kz`
  email-мен ЕНДІ КІРЕ АЛМАЙСЫЗ — LoginScreen тек телефон қабылдайды, 0016
  миграциясы аккаунтты осы нөмірге көшірген.)
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
