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
    apiKey: 'AIzaSyBqtCbYQzeJq3s3qsAsIWTBgQ4ce0bG0ss',
    appId: '1:602555256548:android:f2c0ec323efe1c074626f1',
    messagingSenderId: '602555256548',
    projectId: 'gazelgo',
    storageBucket: 'gazelgo.firebasestorage.app',
  );

  // Firebase Console → Project settings → General → Your apps → iOS (Apple)
  // → SDK setup and configuration → «Config»-тен көшіріңіз.
  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBIA0Pep5HT6D3fKamUsIIrD_h-sNtR7V0',
    appId: '1:602555256548:ios:8de93fcd8452b4084626f1',
    messagingSenderId: '602555256548',
    projectId: 'gazelgo',
    storageBucket: 'gazelgo.firebasestorage.app',
    iosBundleId: 'kz.gazelgo.app',
  );

  // Веб push (міндетті емес) — Firebase Console → Your apps → Web.
  static const web = FirebaseOptions(
    apiKey: 'AIzaSyC2EKnEwJLG7-FjGPbPsxFNe5YBcmkmjNs',
    appId: '1:602555256548:web:38f380e638a33d0f4626f1',
    messagingSenderId: '602555256548',
    projectId: 'gazelgo',
    authDomain: 'gazelgo.firebaseapp.com',
    storageBucket: 'gazelgo.firebasestorage.app',
  );
}
