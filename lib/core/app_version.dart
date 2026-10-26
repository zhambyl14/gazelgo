/// Минималды нұсқа шегі: модератор «build нөмірін» (`29`) НЕМЕСЕ дүкенде
/// көрінетін нұсқаны (`1.0.11`, не `1.0.11+35`) жаза алады.
library;

/// Модератор жазған шек: [build] (0 = жоқ) және [version] ('' = жоқ).
class MinVersion {
  final int build;
  final String version;
  const MinVersion(this.build, this.version);

  /// Өріске қайта жазылатын мәтін: `1.0.11+35`, `1.0.11`, `29` не `0`.
  String get text => version.isEmpty
      ? '$build'
      : (build > 0 ? '$version+$build' : version);
}

/// `29` → build; `1.0.11` → версия; `1.0.11+35` → екеуі де. Бос жол → 0.
/// Танылмайтын жазу (әріп, артық нүкте) → null — сақтамай, қате көрсету үшін.
MinVersion? parseMinVersion(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return const MinVersion(0, '');
  if (RegExp(r'^\d+$').hasMatch(s)) return MinVersion(int.parse(s), '');
  final m = RegExp(r'^(\d+(?:\.\d+){1,3})(?:\+(\d+))?$').firstMatch(s);
  if (m == null) return null;
  return MinVersion(int.tryParse(m[2] ?? '') ?? 0, m[1]!);
}

/// `1.0.11` пен `1.0.9` салыстыру: теріс — a < b, 0 — тең, оң — a > b.
/// Сандық (1.0.11 > 1.0.9); жетпеген бөлік 0 саналады (`1.0` = `1.0.0`).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0,
  ];
  final x = parts(a);
  final y = parts(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Қосымша осы шектен ЕСКІ ме. [myVersion] — `1.0.8`, [myBuild] — `29`
/// (0 = белгісіз → build бойынша бұғаттамаймыз, fail-open).
bool isBelowMin({
  required String myVersion,
  required int myBuild,
  required int minBuild,
  required String minVersion,
}) {
  if (minBuild > 0 && myBuild > 0 && myBuild < minBuild) return true;
  if (minVersion.isNotEmpty &&
      myVersion.isNotEmpty &&
      compareVersions(myVersion, minVersion) < 0) {
    return true;
  }
  return false;
}
