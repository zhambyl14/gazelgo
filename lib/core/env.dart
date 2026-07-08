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

  /// 2GIS геокодер кілті (адрес → координата). Қазақстанда адресті дәл табады.
  /// Тегін кілт: https://dev.2gis.com/ → «Каталог / Geocoder API».
  /// Осында қойыңыз немесе build кезінде:
  ///   flutter build apk --dart-define=TWOGIS_KEY=...
  /// Кілт болмаса — қосымша Nominatim (OSM) арқылы жұмыс істейді.
  static const twogisKey = String.fromEnvironment(
    'TWOGIS_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => !supabaseAnonKey.startsWith('PASTE_');

  /// 2GIS геокодері қосулы ма (кілт бар ма).
  static bool get has2gis => twogisKey.trim().isNotEmpty;
}
