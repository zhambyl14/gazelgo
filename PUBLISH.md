# GazelGo — публикация чек-листі

## 0. Алдын ала (міндетті)

- [ ] `supabase/APPLY.md` орындалған (миграциялар + edge function), соның
      ішінде **0030** (тариф/Kaspi/мәжбүрлі жаңарту баптаулары)
- [ ] `lib/core/env.dart` — anon key қойылған
- [ ] Модератор құпиясөзі ауыстырылған (телефон `+7 700 000 00 01`)
- [ ] Kaspi нөмірі мен тариф бағасы — Модератор → **Баптаулар** табынан
      жазылған (SQL Editor қажет емес, [1-бөлімді](#0-1-тариф-баға-мен-kaspi-нөмірін-ауыстыру) қараңыз)
- [ ] Нақты құрылғыда тексеру: тіркелу → өтінім → модерация → тариф → заказ → пікір

## 0.1 Тариф бағасын және Kaspi нөмірін ауыстыру

Модератор аккаунтпен кіріп, **Баптаулар** табын ашыңыз (ModeratorShell-дің
соңғы табы) — тариф бағасы, Kaspi нөмірі/аты, минималды толтыру сомасы
осы жерден өзгертіледі, «Сақтау» батырмасы дереу серверге жазады. Ешбір
код өзгертпей, кез келген уақытта, кез келгенше рет ауыстыра аласыз.

## 0.2 Мәжбүрлі жаңарту («force update»)

App Store/Play Market-ке жаңа нұсқа шығарған сайын, ЕСКІ нұсқадағы
пайдаланушыларды жаңартуға мәжбүрлеу үшін:

1. `pubspec.yaml`-дағы `version:` жолын көтеріңіз (мыс. `1.0.0+1` →
   `1.0.1+2`) — `+` таңбасынан кейінгі сан **build нөмірі**.
2. Жаңа build-ті App Store Connect/Play Console-ге жүктеп, шолудан
   өткізіп, жарияланғанша күтіңіз.
3. Модератор → **Баптаулар** → «Мәжбүрлі жаңарту» бөлімінде **Минималды
   build нөмірін** жаңа мәнге көтеріңіз (мыс. `2`), Play/App Store
   сілтемелерін толтырыңыз (алғаш рет — 1-бөлімге қараңыз), «Сақтау».
4. Содан кейін build нөмірі осыдан төмен барлық құрылғыда қосымша
   ашылмайды — тек «Жаңарту» экраны, дүкенге апаратын батырмамен.

**Ескерту**: жаңа build дүкенде әлі шолудан өтпей жатқанда минималды
санды көтермеңіз — пайдаланушылар жаңа нұсқаны әлі жүктей алмай, тек
жабық экранды көреді. Алдымен дүкенде жарияланғанын растаңыз, содан
кейін ғана санды көтеріңіз. Минималды build = `0` болса — тексеру толық
өшеді (әдепкі күй).

## 1. Android (Google Play)

### Қол қою кілті (бір-ақ рет)

```powershell
keytool -genkey -v -keystore %USERPROFILE%\gazelgo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gazelgo
```

`android/key.properties` жасаңыз (git-ке қоспаңыз!):
```
storePassword=...
keyPassword=...
keyAlias=gazelgo
storeFile=C:/Users/taraz/gazelgo-upload.jks
```

`android/app/build.gradle.kts` ішіне signing config қосыңыз
(қазір release уақытша debug кілтпен қол қояды — тестке жарайды,
Play-ге жарамайды):

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    // ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

### Құрастыру және жүктеу

```bash
flutter build appbundle --release   # Play Store үшін .aab
```

- [ ] [Play Console](https://play.google.com/console) аккаунты ($25, бір рет)
- [ ] Жаңа қосымша: аты **GazelGo**, тіл: қазақша, тегін
- [ ] `build/app/outputs/bundle/release/app-release.aab` жүктеу
- [ ] Скриншоттар (телефоннан), сипаттама, 512×512 иконка (`assets/icon/icon.png`)
- [ ] Privacy Policy сілтемесі (локация + фото жиналады — міндетті).
      Қарапайым нұсқаны GitHub Pages-те жариялауға болады
- [ ] Data safety: локация (заказ үшін), фото (құжаттар), email/телефон (аккаунт)
- [ ] Internal testing → тексеру → Production

## 2. iOS (кейін, Mac табылғанда)

- Apple Developer аккаунты ($99/жыл), Xcode
- `ios/Runner` bundle id: `kz.gazelgo.app` қойыңыз
- `ios/Runner/Info.plist`-ке рұқсат мәтіндері керек (баптары дайын тұр):
  `NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`,
  `NSPhotoLibraryUsageDescription`, `UIBackgroundModes`(remote-notification)
- `flutter build ipa` → App Store Connect → TestFlight
- Әзірге iPhone-да тексеру үшін web-нұсқаны қолданыңыз (README қараңыз)

### 2.1 Push-хабарландыруды iOS-та қосу (Android-та бұрыннан жұмыс істейді)

Firebase кілттері екі платформа үшін де толтырылған, Dart коды да
платформа-тәуелсіз (`lib/core/push.dart`) — бірақ iOS-та push жеткізілу
үшін тағы **екі қадам** қажет, екеуі де тек Mac/Xcode/Apple Developer
арқылы жасалады:

1. **APNs кілті**: [Apple Developer](https://developer.apple.com) →
   Certificates, IDs & Profiles → Keys → жаңа кілт (Apple Push
   Notifications service) жасап, `.p8` файлды жүктеп алыңыз. Содан кейін
   Firebase Console → Project settings → Cloud Messaging → **Apple app
   configuration** → осы `.p8` кілтін (Key ID + Team ID-мен бірге)
   жүктеңіз. Бұл қадамсыз FCM токен алынғанмен, хабарлама іс жүзінде
   ЖЕТКІЗІЛМЕЙДІ.
2. **Xcode capability**: `Runner.xcworkspace`-ті Xcode-та ашып, Runner
   target → Signing & Capabilities → **+ Capability** → «Push
   Notifications» қосыңыз (бұл автоматты `Runner.entitlements` файлын
   жасап, жобаға қосады). `UIBackgroundModes` Info.plist-те дайын тұр.

Осы екеуі жасалмайынша iOS қолданушылары push АЛМАЙДЫ (Android бұрыннан
жұмыс істейді). Mac табылғанда осы бөлімді орындаңыз.

## 3. Web (қазір-ақ жариялауға болады)

```bash
flutter build web --release
```

`build/web` папкасын кез келгеніне жүктеңіз:
- **Netlify Drop** (ең оңай): https://app.netlify.com/drop — папканы сүйреп тастайсыз
- **Vercel**: `npx vercel build/web`
- **GitHub Pages**: репо → Settings → Pages

Жарияланған соң iPhone Safari → «Add to Home Screen» = PWA қосымша.

## 4. Кейінгі жақсартулар (ұсыныс)

- Kaspi API интеграциясы (қолмен растаудың орнына автоматты толтыру)
- Орындаушының live-локациясын клиентке көрсету

## 5. Көлік түрі иконкаларын SVG-ге ауыстыру (міндетті емес)

Қазір көлік түрлері (газель, кран, экскаватор…) Material Icons жиынымен
көрсетіледі. Газель/фургон/КамАЗ/погрузчик/минивэн/трактор нақты сәйкес,
ал кран/манипулятор/ассенизатор/экскаватор — Material-де дәл сол техника
белгісі жоқ болғандықтан ең жақын машина/механизм белгісімен беріледі.
Пиксельге дәл, App Store деңгейіндегі техника суреттерін қаласаңыз:

1. `flutter pub add flutter_svg`.
2. [Tabler Icons](https://tabler.io/icons) не [Lucide](https://lucide.dev)
   сайтынан 10 түрдің SVG-лерін жүктеп, `assets/vehicles/<type>.svg` деп
   сақтаңыз (аты `VehicleType.name`-мен бірдей: `gazelle.svg`, `crane.svg`…).
   Тегін, SVG Repo-да арнайы техника (excavator, forklift) көп.
3. `pubspec.yaml` → `flutter: assets:` бөліміне `assets/vehicles/` қосыңыз.
4. `lib/core/models.dart`-тағы `VehicleTypeX.icon` (IconData) орнына
   `String get asset => 'assets/vehicles/$name.svg';` қосып,
   `VehicleTypeCarousel` мен тегтерде `Icon(...)` → `SvgPicture.asset(...)`
   деп ауыстырыңыз (`colorFilter`-мен таңдалған/таңдалмаған түсті беріңіз).

Бұл тек көрнекілік — қосымшаның логикасы (заказ түрін сүзу) иконкаға
тәуелсіз, `vehicle_type` мәтіндік кілт арқылы жұмыс істейді.
