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

   - `migrations/0029_vehicle_types_single_tariff.sql` ← **МАҢЫЗДЫ, көлік
     түрлері + бірыңғай тариф** (0028-ден кейін орындаңыз):
     (1) `vehicle_type` бағаны (`executor_profiles` + `orders`): газель,
     фургон, КамАЗ, кран, манипулятор, ассенизатор, экскаватор, погрузчик,
     мини вэн, трактор 3в1. Орындаушы тіркелгенде түрін таңдайды, клиент
     заказ бергенде түрін таңдайды — заказ ТЕК сол түрдегі орындаушыларға
     көрінеді (`exec_can_take` ішінде, лента да, push та автоматты сүзіледі).
     (2) **Тариф бірыңғай**: Простой/VIP жоқ, бағасы 300 ₸ (күндіз де, түнде
     де). Ауысым/10 заказ механикасы өзгеріссіз. Клиент заказ санатын енді
     таңдамайды.
     (3) **Жаңа расталған орындаушыға 1 АЙ тегін** (бұрынғы 24 сағат орнына).
     Өзгерген RPC-лер: `buy_tariff`, `create_order` (жаңа `p_vehicle_type`),
     `place_offer`, `accept_offer`, `executor_stats`, `exec_can_take`,
     `exec_has_capacity`, `consume_order`, `grant_trial`, `mod_line_stats`.

   - `migrations/0030_admin_settings_force_update.sql` ← **Модератор
     баптаулары + мәжбүрлі жаңарту** (0029-дан кейін орындаңыз): жаңа
     `app_version_gate()` RPC (авторизациясыз да шақырылады — кіру
     экранындағы ескі нұсқаны да бұғаттау үшін, тек `version_gate`
     баптауын қайтарады) және `mod_update_setting(key, value)` RPC
     (модератор ғана; тариф бағасын, Kaspi деректерін, мәжбүрлі жаңарту
     санын SQL-сыз, Модератор → **Баптаулар** табынан өзгертуге болады).
     Толық қолдану нұсқаулығы: `PUBLISH.md` → §0.1/§0.2.

   - `migrations/0031_cancel_quota_refund.sql` ← **Заказ бас тарту логикасын
     түзету** (0030-дан кейін орындаңыз): екі қате жөнделеді.
     (1) Бұрын орындаушының тариф лимиті (`orders_left`) заказ
     ҚАБЫЛДАНҒАНДА бір-ақ рет шегеріліп, кейін ешқашан қайтарылмайтын —
     клиент қабылданған заказды тоқтатса да, орындаушының лимиті
     босқа кетіп жататын. Енді: заказда қай тариф-сессиядан шегерілгені
     жазылады (`orders.charged_session_id`), клиент бас тартқанда сол
     сессияға +1 қайтарылады. Орындаушы ӨЗІ бас тартса — қайтарылмайды
     (өз кінәсі, лимит -1 болып қалады) — бұл өзгермейді.
     (2) `check_client_order_abuse` триггері (0018) клиенттің соңғы
     60 минутта тоқтатқан заказдарын `created_at` (заказ АШЫЛҒАН уақыт)
     бойынша санап жүрген еді — дұрысы `cancelled_at` (ТОҚТАТЫЛҒАН уақыт)
     болу керек. Жаңа `orders.cancelled_at` бағаны қосылып, `cancel_order`/
     `mod_cancel_order` соны толтырады, триггер соны қолданады.

   - `migrations/0032_storage_retention_cron.sql` ← **Storage автоматты
     тазалау** (0031-ден кейін орындаңыз): `trigger_storage_cleanup()`
     функциясы + оны күн сайын шақыратын `pg_cron` тапсырмасы. Бұл
     миграция өзі ештеңе өшірмейді — тек cron-ды баптайды; нақты өшіру
     `cleanup-storage` edge function-да (төмендегі «Storage тазалау
     (cron)» бөлімін қараңыз, **міндетті түрде edge function deploy
     ЖӘНЕ секрет қою керек**, әйтпесе cron үнсіз ештеңе істемейді).

   - `migrations/0033_docs_update_storage_cleanup.sql` ← **Орындаушы
     құжатын жаңартқанда ескі файл өшірілсін** (0032-ден кейін
     орындаңыз): модератор белгілі бір құжатты (мыс. паспортты) қайта
     жүктеуді сұраса (`mod_request_docs`), орындаушы жаңасын жіберген
     соң ЕСКІ файл Storage-та мәңгі орфан болып қалатын еді — енді
     `submit_docs_update` нақты ауыстырылған ескі жолдарды қайтарады,
     клиент оларды бірден өшіреді. Сонымен қатар 0023-тегі регрессия
     түзетілді: көлік фотосын қайта сұраса, жаңа фото базаға
     ЖАЗЫЛМАЙТЫН еді (`vehicle_photos =` SET тізімінен жоғалып қалған
     болатын) — қалпына келтірілді.

   - `migrations/0034_orders_support_storage_update_policy.sql` ←
     **"new row violates row-level security policy" қатесін түзету**
     (заказ фотосын жүктегенде): `Repo.uploadOrderPhoto`/support фото
     жүктеу `upsert: true` қолданады, ал Supabase Storage upsert
     кезінде ішінде "ON CONFLICT DO UPDATE" шығарады — соған UPDATE
     RLS саясаты керек, нақты қайшылық болмаса да. `orders`/`support`
     бакеттерінде ол жоқ болатын (`docs`/`avatars`-та бар еді) — енді
     екеуіне де `*_update_own` саясаты қосылды.

   - `migrations/0035_tasu_rebrand_texts.sql` ← **GazelGo → Tasu, қалып
     қойған екі жер**: қолдау чатының push тақырыбы
     (`notify_support_message`) және `app_settings.payment.kaspi_name`
     (тек әлі әдепкі "GazelGo" болып тұрса ғана түзетеді — модератор
     Баптаулар табынан өзгертіп қойған болса тимейді).

   - `migrations/0036_remove_vip_dispatch.sql` ← **VIP/instant заказ
     тарату механизмі толық өшіріледі** (0029-дан бастап `create_order`
     ешқашан `type='instant'` жасамайды — сол себепті `vip_dispatches`
     кестесі, `assign_next_vip`/`accept_vip`/`decline_vip`/`advance_vip`/
     `advance_all_vip`/`set_auto_accept_vip` RPC-тері, `has_my_dispatch`
     RLS функциясы, `gazelgo-vip-advance` cron job (әр 10 секунд сайын
     жұмыс істеп тұрған!), `instant_quote`, `executor_profiles.
     auto_accept_vip` бағаны — бәрі өлі код еді). `cancel_order`/
     `mod_cancel_order`/`expire_stale_orders` осы тәуелділіктерсіз қайта
     анықталады, bidding-логикасы толық сақталады. Клиент (Dart) жағы
     да сәйкесінше тазаланды (executor_shell.dart, order_detail_screen.
     dart, vip_dispatch_dialog.dart өшірілді). **Ретті сақтаңыз** —
     файлдың өзінде тәуелділік ретімен түсіндірме бар.

   Егер 0001–0004 бұрын орындалған болса, тек жаңа нөмірленген файлдарды
   ретімен іске қосыңыз (олар қайта орындауға қауіпсіз — idempotent).
   **0013, содан соң 0014, 0016, 0017, 0018, 0019, 0020, 0021, 0022, 0023,
   0024, 0025, 0026, 0027, 0028, 0029, 0030, 0031, 0032, 0033, 0034, 0035,
   ең соңынан 0036-ны орындаңыз.**
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
     баптау төмендегі «Telegram верификация» бөлімінде. (0035 соң: бот
     жауаптарындағы атау Tasu-ге түзетілді — бұрын deploy жасаған
     болсаңыз, ҚАЙТА deploy жасаңыз.)
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

## Storage тазалау (cron) — заказ/қолдау фотолары шексіз жиналмасын

Неге керек: заказдың жүк фотолары мен қолдау чатының скриншоттары бұрын
тек біреу тиісті экранды АШҚАНДА ғана тазаланатын (client-side, `Repo.
deleteOrderPhotos`/`cleanupSupportImages`) — ешкім ашпаса, файл Storage-та
мәңгі қалады. Бұл нақты кепілдік емес, тек «сирек болса да тазаланады»
дегенді білдіреді. Енді сервер жағында, экранға тәуелсіз, күн сайын
жұмыс істейтін нақты тазалау бар:

- **Заказдар**: 5+ күн бұрын аяқталған/бас тартылған/мерзімі өткен
  заказдың Storage-тағы жүк фотолары өшіріледі (заказдың өзі — тарих,
  дау/тексеру үшін — қалады, тек `photos` бос массивке ауыстырылады).
- **Қолдау тредтері**: 5+ күн бұрын ЖАБЫЛҒАН тред — хабарламаларымен
  және Storage суреттерімен қоса — толық өшіріледі (ашық/белсенді
  тредтерге тиіспейді).
- **Docs (құжаттар)**: модератор орындаушыдан құжатты қайта жүктеуді
  сұраса, ЕСКІ файл дереу өшіріледі (0033); жаңа өтінім/тіркелу жолы
  бұрыннан дұрыс еді.
- **Avatars**: пайдаланушы аватарды өзгерткенде ЕСКІ файл дереу
  өшіріледі (`Repo.updateAvatar`, клиент жағы) — cron-ға тәуелсіз.
- **Аккаунт өшіру (0037, `storage_purge_queue`)**: полиция тергеу
  сұрауы үшін заңды сақтау мерзімі — аккаунт өшірілгенде (delete-account
  функциясы) docs/avatars файлдары шартты өшіріледі:
  - orқындаушы кемінде 1 заказды АЯҚТАҒАН болса → docs 30 күн сақталып,
    содан кейін осы cron арқылы өшеді; аяқталған заказы болмаса →
    бірден өшеді.
  - аккаунтта (клиент не орындаушы ретінде) кемінде 1 аяқталған заказ
    болса → avatar 30 күн сақталып, содан кейін өшеді; болмаса — бірден
    өшеді.
  - DB көрсеткіштері (avatar_url, doc_path-тар) екі жағдайда да БІРДЕН
    тазаланады — тек нақты Storage файлы кідіреді, полиция сол аралықта
    Storage Dashboard-тан пайдаланушының uuid қалтасын тікелей қарай
    алады.

Storage файлдарын SQL тікелей өшіре алмайды (Supabase шектеуі), сол
себепті бұл — edge function + `pg_cron` арқылы:

**МАҢЫЗДЫ**: төмендегі deploy қадамдары БІР РЕТ те жасалмаған болуы
мүмкін — сол жағдайда orders/support/purge-кезегі файлдары ЕШҚАШАН
автоматты өшпейді, тек Storage-та жинала береді. Bucket-те файл саны
өспей тұрса — алдымен осы бетті толық орындаңыз.

### 0-қадам: миграциялар (0037 purge-кезек, 0038 expire push, 0039 reminder)

- `supabase/migrations/0037_delete_account_retention.sql` — жаңа
  `storage_purge_queue` кестесін жасайды (аккаунт өшіргенде докс/аватар
  файлдарының 30 күндік сақтау кезегі).
- `supabase/migrations/0038_order_expiry_notify.sql` — `expire_stale_orders()`
  функциясын ауыстырады: заказ 6 сағат ішінде ешкіммен қабылданбай
  automat expire болғанда, енді клиентке push жіберіледі («Заказ
  табылмады»). Бұрын бұл жағдайда клиентке ЕШБІР хабарлама келмейтін.
  (0039-да тағы да ауыстырылады, тарихи қадам ретінде қалады.)
- `supabase/migrations/0039_order_search_reminder.sql` — `expire_stale_orders()`-ті
  СОҢҒЫ түрге ауыстырады: заказ ешкіммен қабылданбаса, клиентке
  ҚАЙТАЛАНАТЫН еске салу push келеді — 15 мин, 45 мин, содан кейін әр
  1 сағат сайын, 6 сағатта expire болғанша («ешкім қабылдамай жатыр,
  бағаны көтеріп көріңіз»).

Үшеуін де SQL Editor-да ретімен (0037 → 0038 → 0039) орындаңыз.

### 1-қадам: Edge function deploy (ЕКЕУІ де)

Dashboard → Edge Functions → **Deploy new function** → аты
`cleanup-storage`, коды `supabase/functions/cleanup-storage/index.ts`,
**Verify JWT = OFF** (pg_net-тен, JWT-сіз шақырылады — орнына функцияның
өз ішінде `x-cron-secret` header тексеріледі). Ескерту: қолдау
тредтерінің сақтау мерзімі енді **1 күн** (бұрын 5), заказ фотолары
өзгеріссіз **5 күн**.

Сонымен қатар `delete-account` функциясын да ҚАЙТА deploy жасаңыз (0037
логикасы — заказ тарихын тексеріп, докс/аватарды бірден өшіру не 30
күнге кезекке қою — осы функцияның ішінде).

### 2-қадам: Секрет қою (екі жерде, БІРДЕЙ мән)

1. **Edge Function Secrets** (Dashboard → Edge Functions → Manage secrets)
   → `CRON_SECRET` — өзіңіз ойлап тапқан ұзын құпия жол (мыс. терминалда
   `openssl rand -hex 32`).
2. SQL Editor-да (0032 миграциясы қолданылған СОҢ, БІР РЕТ) — 2.1-дегімен
   **дәл сол бір** мәнді қойыңыз (секрет `push_trigger_secret`-пен бірдей
   `app_secrets` кестесінде сақталады):
   ```sql
   insert into public.app_secrets (key, value)
   values ('cron_cleanup_secret', 'СІЗДІҢ_ҚҰПИЯ_ЖОЛЫҢЫЗ')
   on conflict (key) do update set value = excluded.value;
   ```
   (Мәндер сәйкес келмесе — cron үнсіз ештеңе істемейді, ешбір қате де
   көрсетілмейді, себебі `trigger_storage_cleanup()` секрет бос болса
   үнсіз қайтады.)

### Тексеру

SQL Editor-да қолмен бір рет шақырып көруге болады:
```sql
select public.trigger_storage_cleanup();
```
Содан соң Supabase Dashboard → Edge Functions → `cleanup-storage` →
**Logs** бөлімінен нәтижені (`threadsDeleted`, `orderPhotosDeleted`,
`purgedFiles`, т.б.) көріңіз. Cron тапсырмасының өзін (`tasu-storage-cleanup`, күн сайын
02:30 UTC) Database → Cron бөлімінен көруге/өшіруге болады.

Мерзімді (5 күн) өзгерту керек болса — `supabase/functions/cleanup-storage/
index.ts` ішіндегі `RETENTION_DAYS` константасын түзетіп, функцияны
қайта deploy жасаңыз.

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
- `app_settings` кестесінде тарифтер (0029 соң): бірыңғай тариф 300₸
  (күндіз де, түнде де). Минимум баға: `order_min` → қала ішінде 100,
  межгород 1000.
- Kaspi нөмірін өзгерту: `app_settings.payment` → `kaspi_number`, `kaspi_name`.
- 0013 соң тексеру: газелист өтінімде **қала** таңдайды; расталғанда 24 сағат тегін триал
  беріледі; тариф сатып алса 10 заказ болады; клиент заказы тек bidding (баға өзі қояды).

## Ескертпелер

- Тегін жоспар лимиті: бір аккаунтта 2 белсенді тегін проект. `gazelgo` деп жаңа
  проект құру мүмкін болмады (лимит толы: `qoima` + `xibxaqcrdpgyzohfplda`),
  сондықтан backend осы дайын SQL түрінде сақталды.
- `pg_cron` VIP таратуды 10 секунд сайын жылжытады; клиент қосымшасы да іздеу
  экранында 5 секунд сайын `advance_vip` шақырып, кідірісті азайтады.
