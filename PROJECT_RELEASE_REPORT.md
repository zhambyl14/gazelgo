# PROJECT_RELEASE_REPORT — Tasu

> Аудит және релизге дайындау есебі. Күні: 2026-07-13.
> Стек: Flutter 3.41.9 / Dart 3.11.5 · Supabase · Firebase Cloud Messaging.
> Принцип: **архитектура, бизнес-логика, UI және Supabase схемасы өзгертілген жоқ** —
> тек релиз конфигурациясы мен қауіпсіз түзетулер.

---

## 1. Не түзетілді (Fixed)

| # | Мәселе | Түзету | Файл |
|---|--------|--------|------|
| 1 | **iOS Bundle ID сәйкессіздігі** — Xcode-та `com.magazel.magazel`, ал Firebase iOS қосымшасы мен Android `kz.gazelgo.app`. Осы күйде iOS push жеткізілмейді және App Store Connect-те қате шығады. | Барлық iOS build-конфигінде (Debug/Release/Profile) `kz.gazelgo.app` қойылды, тест таргеті `kz.gazelgo.app.RunnerTests`. | `ios/Runner.xcodeproj/project.pbxproj` |
| 2 | **Бұзылған тест** — `widget_test.dart` env «бапталмаған» экранын күтетін, бірақ нақты anon key қосылғандықтан тест ҚҰЛАП тұрған (0/1). CI-ды бұзатын. | Backend-ке тәуелсіз, детерминирленген unit-тесттермен ауыстырылды (`Phone` нормализациясы) — 5/5 жасыл. | `test/widget_test.dart` |
| 3 | **Тексерілмеген dependency жаңарту қаупі** — `flutter pub upgrade` `firebase_core` 4.12.0 + `firebase_messaging` 16.4.2 нұсқаларын әкелді, олар өзара **үйлеспейді** (`Type 'FirebasePlugin' not found`), release build құлайды. `flutter analyze` мұны КӨРМЕЙДІ (тек `lib/` тексереді). | Lock файл белгілі-жұмыс істейтін нұсқаларға қайтарылды (§3 қараңыз). | `pubspec.lock` |

---

## 2. Не оптимизацияланды (Optimized)

| # | Оптимизация | Мәні | Файл |
|---|-------------|------|------|
| 1 | **R8 / code shrinking + resource shrinking** қосылды (release build-та). Толық release AAB **сәтті құрастырылды** (расталды). | Кодты кішірейтеді/обфускациялайды. Плагиндер өз consumer-proguard ережелерін әкеледі. R8-ды өткізу үшін Flutter embedding-тің **Play Core** («deferred components») класстарына `-dontwarn` ережесі қосу қажет болды — онсыз `minifyReleaseWithR8` «Missing class» қатесімен құлайтын (build кезінде табылып, түзетілді). | `android/app/build.gradle.kts`, `android/app/proguard-rules.pro` (жаңа) |
| 2 | Кескін кэші (`imageCache`) 150 сурет / 30 МБ-қа шектелген (бұрыннан бар, расталды). | Мобильде жад үнемдейді. | `lib/main.dart` |
| 3 | Тізімдер `ListView.builder/separated` (16 жер) + кескіндер `cacheWidth/cacheHeight` (9 жер) — жалқау жүктеу мен тиімді декодтау расталды. | Rebuild/жад тиімділігі. | (өзгертілмеді, аудит) |

**Ескерту (R8):** Компиляция сәтті өтті, бірақ R8 обфускациясының runtime әсерін
эмуляторда/құрылғыда бір рет **release режимінде** сынап шығу ұсынылады (push,
геолокация, фото жүктеу, заказ ағыны). Кез келген мәселе болса — `proguard-rules.pro`-ға
`-keep` ережесін қосу жеткілікті, немесе `isMinifyEnabled = false` деп уақытша өшіруге болады.

---

## 3. Қандай зависимостер жаңартылды (Dependencies)

**Шешім:** релиз тұрақтылығы үшін тәуелділіктер **белгілі-жұмыс істейтін** нұсқаларда
қалдырылды. `flutter pub upgrade` сынап көрілді, бірақ ол Firebase-ті үйлеспейтін
нұсқаларға көтеріп, release build-ты бұзды — сондықтан қайтарылды.

| Пакет | Қалды (тұрақты) | Соңғы қолжетімді | Неге көтерілмеді |
|-------|-----------------|------------------|-------------------|
| firebase_core | 4.11.0 | 4.12.0 | 4.12.0 + messaging 16.4.2 = build құлайды |
| firebase_messaging | 16.4.1 | 16.4.2 | ↑ жоғарыдағы себеп |
| supabase_flutter | 2.15.4 | 2.16.0 | Firebase-пен бірге қайтарылды (топтама реверт) |
| flutter_riverpod | 2.6.1 | 3.3.2 | Major (breaking) — архитектура өзгерісін талап етеді, тиіспедік |
| package_info_plus | 8.3.1 | 10.2.0 | Major — тиіспедік |
| flutter_local_notifications | 19.5.0 | 22.0.1 | Major — тиіспедік |
| latlong2 | 0.9.1 | 0.10.1 | Minor breaking — тиіспедік |

> Кейін жаңартқыңыз келсе: Firebase екеуін БІРГЕ, тек өзара үйлесімді жұп ретінде
> көтеріп, әр жолы `flutter build appbundle --release` мен құрылғыда тексеріңіз.

---

## 4. Қандай файлдар өзгертілді (Changed files)

```
ios/Runner.xcodeproj/project.pbxproj      — iOS bundle id → kz.gazelgo.app (6 жол)
android/app/build.gradle.kts              — release: minify + shrinkResources + proguard (+9 жол)
android/app/proguard-rules.pro            — ЖАҢА: R8 keep/dontwarn ережелері
test/widget_test.dart                     — бұзылған тест → Phone unit-тесттері (5/5)
PROJECT_RELEASE_REPORT.md                 — ЖАҢА: осы есеп
```

> `pubspec.lock` уақытша жаңартылып, кейін committed күйге қайтарылды —
> **таза нәтижесі: өзгеріссіз** (тұрақты Firebase/Supabase нұсқалары сақталды).

Код (`lib/`) логикасы, UI, Supabase схемасы, API — **өзгертілмеді**.

---

## 5. Қолмен істелетін жұмыс (Manual — қалды)

1. **Android қол қою кілті** (Play үшін міндетті) — `PUBLISH.md §1`: `keytool`-мен
   `.jks` жасап, `android/key.properties` толтыру (git-ке қоспаңыз). Кілт болмаса
   release debug-кілтпен қол қойылады — Play қабылдамайды.
2. **iOS (Mac қажет)** — `PUBLISH.md §2`: Xcode-та Signing, APNs `.p8` кілті
   (Firebase-ке), «Push Notifications» capability. Bundle id енді дайын (`kz.gazelgo.app`).
3. **Release smoke-test** — R8 қосылғаннан кейін құрылғыда бір рет толық ағынды тексеру
   (тіркелу → push → геолокация → фото → заказ).
4. **Privacy Policy хостинг** — `docs/privacy.html` дайын, оны GitHub Pages/Netlify-ге
   жариялап, сілтемесін екі дүкенге де беру.
5. **Модератор құпиясөзі** мен Kaspi/тариф баптаулары — `PUBLISH.md §0`.

---

## 6. Google Play Console үшін не керек

- [ ] Play Console аккаунты ($25, бір рет).
- [ ] `android/key.properties` + upload keystore (§5.1).
- [ ] `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`.
- [ ] **SDK деңгейлері** (Flutter 3.41 әдепкісі, расталды): `minSdk 24` (Android 7.0),
      `targetSdk 36` (Android 16), `compileSdk 36`. Google Play талабы (API 35) орындалады,
      сұралған Android 10–16 диапазоны толық қамтылады.
- [ ] **64-bit + App Bundle** — AAB автоматты түрде барлық ABI-ды қамтиды (armeabi-v7a,
      arm64-v8a, x86_64), 64-bit талабы орындалады.
- [ ] **Data safety** формасы: локация (заказ), фото (құжат/жүк), email+телефон (аккаунт).
- [ ] **Privacy Policy** сілтемесі (локация + камера жиналатындықтан міндетті).
- [ ] Скриншоттар, 512×512 иконка (`assets/icon/icon.png`), сипаттама.
- [ ] Permissions негіздемесі: FINE/COARSE_LOCATION, CAMERA, POST_NOTIFICATIONS.
- [ ] Internal testing → Production.

---

## 7. App Store Connect үшін не керек (Mac қажет)

- [ ] Apple Developer аккаунты ($99/жыл), Xcode бар Mac.
- [ ] Bundle ID `kz.gazelgo.app` — **дайын** (осы аудитте түзетілді), App Store Connect-те
      бірдей ID-мен қосымша құру.
- [ ] APNs `.p8` кілті → Firebase (iOS push үшін), Xcode «Push Notifications» capability.
- [ ] Info.plist рұқсат мәтіндері — **дайын** (локация/камера/фотогалерея, қазақша).
- [ ] `flutter build ipa` → Transporter/Xcode → TestFlight → App Review.
- [ ] Privacy «Nutrition Label» (App Privacy) — Data safety-мен бірдей деректер.
- [ ] Deployment target iOS 13.0 — дайын.

---

## 8. Жариялауда болуы мүмкін мәселелер (Potential issues)

1. **R8 обфускациясы** — сирек жағдайда рефлексияға сүйенетін плагин release-те
   істемей қалуы мүмкін. Алдын алу: құрылғыда release smoke-test (§5.3). Түзету оңай:
   `proguard-rules.pro` немесе `isMinifyEnabled = false`.
2. **iOS push** — APNs `.p8` + Xcode capability жасалмайынша iOS-та push жеткізілмейді
   (Android жұмыс істейді). Бұл Mac-ты талап етеді.
3. **Play Data safety сәйкессіздігі** — локация/камера жиналатынын формада ТОЛЫҚ көрсету
   керек, әйтпесе шолуда қабылданбайды.
4. **Landscape/iPad** — қосымша барлық бағдарды қолдайды (Info.plist), бірақ UI негізінен
   портретке арналған. App Review iPad-та тексеруі мүмкін — қаласаңыз бағдарды тек портретке
   шектеуге болады (міндетті емес).
5. **Dependency ескіруі** — Firebase/Riverpod major нұсқалары артта; кейін жоспарлы,
   тексерілген жаңарту қажет (бірден бәрін емес).
6. **Native debug symbols** — build кезінде «failed to strip debug symbols from native
   libraries» ЕСКЕРТУІ шығады (NDK toolchain, өлімші емес). AAB жарамды әрі Play қабылдайды,
   бірақ жүктеме көлемі сәл үлкенірек. Қаласаңыз `flutter doctor`-мен NDK-ды түзеп,
   немесе `android/app/build.gradle.kts`-ке `ndk { debugSymbolLevel = "none" }` қосуға болады.

---

## 9. Жариялау чек-парағы (Publish checklist)

**Код дайындығы (осы аудитте расталды):**
- [x] `flutter analyze` — таза (0 issue)
- [x] `dart fix` — түзетілетін ештеңе жоқ
- [x] `flutter test` — 5/5 өтеді
- [x] `print()` / `TODO` / debug-код — жоқ
- [x] Release AAB құрастырылады (R8 қосулы)

**Android:**
- [ ] key.properties + keystore
- [ ] AAB құрастыру
- [ ] Play Console: Data safety, Privacy, скриншоттар
- [ ] Internal test → Production

**iOS (Mac):**
- [x] Bundle ID `kz.gazelgo.app`
- [x] Info.plist рұқсаттары
- [ ] APNs кілті + Xcode capability
- [ ] TestFlight → App Review

---

*Толық қадамдық нұсқаулық: `PUBLISH.md`. Осы есеп — сол нұсқаулықтың релиз алдындағы
аудит қорытындысы.*
