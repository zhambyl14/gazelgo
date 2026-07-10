import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase баптаулары — толтырылмаған (placeholder) күйде тұр.
///
/// Мұнда `google-services.json`/`GoogleService-Info.plist` файлдарын Xcode-қа
/// қосудың ОРНЫНА, мәндерді Firebase Console-дан қолмен көшіріп, осы жерге
/// саласыз (Mac/Xcode қажет ЕМЕС — тек веб-браузерден консольге кіру
/// жеткілікті). Толық нұсқау: supabase/APPLY.md → «Push-хабарландырулар».
///
/// Толтырылмаса — [FirebaseOpts.isConfigured] false қайтарады, [Push.init]
/// үнсіз өшірулі күйде қалады, қосымша бұзылмайды.
class FirebaseOpts {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  /// Кез келген платформа толтырылған ба? (Android/iOS біреуі жеткілікті —
  /// пайдаланушы бір платформадан бастауы мүмкін.)
  static bool get isConfigured =>
      android.apiKey.isNotEmpty || ios.apiKey.isNotEmpty;

  // Firebase Console → Project settings → General → Your apps → Android
  // → SDK setup and configuration → «Config»-тен көшіріңіз.
  static const android = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
  );

  // Firebase Console → Project settings → General → Your apps → iOS (Apple)
  // → SDK setup and configuration → «Config»-тен көшіріңіз.
  static const ios = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
    iosBundleId: 'kz.gazelgo.app',
  );

  // Веб push (міндетті емес) — Firebase Console → Your apps → Web.
  static const web = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    authDomain: '',
    storageBucket: '',
  );
}
