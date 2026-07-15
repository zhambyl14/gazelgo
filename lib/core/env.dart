/// GazelGo ортасының конфигі.
///
/// Supabase проектісі: xibxaqcrdpgyzohfplda
/// ANON KEY-ді Dashboard → Settings → API бетінен алып қойыңыз,
/// немесе build кезінде беріңіз:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xibxaqcrdpgyzohfplda.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhpYnhhcWNyZHBneXpvaGZwbGRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNDA0NzEsImV4cCI6MjA5ODkxNjQ3MX0.S3N1A6f4NtYKFheXVq0otdEVIi0_Z6-cBu-URPB9pvk',
  );

  static bool get isConfigured => !supabaseAnonKey.startsWith('PASTE_');

  /// Қолдау қызметінің WhatsApp нөмірі (құпиясөзді қалпына келтіру т.б.).
  /// Тек цифрлар, елдік кодпен: 7XXXXXXXXXX. Өз нөміріңізге ауыстырыңыз!
  static const supportWhatsApp = '77474005347';

  /// Тіркелуде телефонды растайтын Telegram боттың username-і (@-сыз).
  /// Пайдаланушы `t.me/<осы>?start=<токен>` арқылы ботқа өтіп, нөмірін
  /// бөліседі. Ботты BotFather-де құрып, вебхукын `telegram-webhook` edge
  /// функциясына қосу керек (supabase/APPLY.md → «Telegram верификация»).
  static const telegramBot = 'tasuappbot';
}
