/// Тіркелу/профиль атына жеңіл тексеру: тым қысқа, тек цифр/белгі, бір
/// әріп қайталанған spam («дддд») немесе ұятсыз сөз болмауы керек. Толық
/// қорғаныс емес — тек ең анық өтірік/спам аттарды сүзеді (мыс. «д», «дл»,
/// «...», «asdf123»). Аты-жөні форматы (кемінде 2 сөз) талап етіледі —
/// тіркелу өрісінің «Аты-жөніңіз» деген белгісіне сай.
class NameGuard {
  static const _profanity = [
    'бляд', 'сука', 'хуй', 'хуе', 'пизд', 'ебан', 'ёбан', 'муда', 'гандон',
    'долбо', 'мразь', 'скотина', 'уебок', 'уёбок', 'залуп', 'сучка',
    'fuck', 'shit', 'bitch', 'asshole', 'cunt',
    'қотақ', 'сігіл', 'сикт', 'аңқа', 'малмын',
  ];

  static final _lettersOnly = RegExp(r'^[\p{L}\s\-]+$', unicode: true);
  static final _repeatedChar = RegExp(r'^(.)\1*$', unicode: true);

  /// null болса — жарамды, әйтпесе пайдаланушыға көрсетілетін қате мәтіні.
  static String? validate(String raw) {
    final v = raw.trim();
    if (v.length < 4) return 'Атыңызды толық жазыңыз';
    if (!_lettersOnly.hasMatch(v)) {
      return 'Атта тек әріптер болуы керек (цифр/белгі жарамсыз)';
    }
    final words =
        v.split(RegExp(r'[\s\-]+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || words.any((w) => w.length < 2)) {
      return 'Аты-жөніңізді толық жазыңыз (мыс: Асхат Серіков)';
    }
    if (words.any((w) => _repeatedChar.hasMatch(w))) {
      return 'Атыңызды дұрыс жазыңыз';
    }
    final lower = v.toLowerCase();
    for (final bad in _profanity) {
      if (lower.contains(bad)) return 'Аты-жөнде рұқсат етілмеген сөз бар';
    }
    return null;
  }
}
