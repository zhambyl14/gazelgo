/// Мекенжай мәтінін САЛЫСТЫРУ — қате жазуға төзімді іздеудің негізі.
///
/// НЕГЕ КЕРЕК: клиент мекенжайды асығыс, қате жазады — «толеби 59»,
/// «жельтоксан», «абаяя», латынмен «abaya 15», орысша жалғаумен «Сейфуллина»
/// (картада — «Сейфуллин көшесі»). Тегін геокодерлер (Nominatim) мұндай
/// сұранысқа НӨЛ нәтиже береді. Сол себепті атауларды бір «кілтке» келтіріп
/// (әріп түрі, тіл, жалғау, тип сөздер есепке алынбайды), 1–2 әріп қатесін
/// кешіретін ұқсастық бағасын есептейміз.
///
/// Тек таза Dart (Flutter-сіз) — `test/geo_text_test.dart` тексереді.
class GeoText {
  GeoText._();

  // ---------------------------------------------------------------------
  //  ӘРІПТЕРДІ БІР ТҮРГЕ КЕЛТІРУ
  // ---------------------------------------------------------------------

  /// Латын әріптерін кириллге айналдырады (қазақтың 2021 латын әліпбиі мен
  /// орысша транслитті қоса). Тек САЛЫСТЫРУ мен іздеу сұранысына арналған —
  /// «abaya 15» → «абая 15», «MEGA» → «мега».
  static String latinToCyrillic(String s) {
    final src = s.toLowerCase();
    final b = StringBuffer();
    var i = 0;
    while (i < src.length) {
      if (i + 1 < src.length) {
        final two = src.substring(i, i + 2);
        final d = _latinDigraphs[two];
        if (d != null) {
          b.write(d);
          i += 2;
          continue;
        }
      }
      final ch = src[i];
      b.write(_latinSingle[ch] ?? ch);
      i++;
    }
    return b.toString();
  }

  static const _latinDigraphs = {
    'sh': 'ш',
    'ch': 'ч',
    'zh': 'ж',
    'kh': 'х',
    'ts': 'ц',
    'ya': 'я',
    'yu': 'ю',
    'yo': 'ё',
    'ye': 'е',
    'ia': 'я',
    'iu': 'ю',
  };

  static const _latinSingle = {
    'a': 'а',
    'b': 'б',
    'c': 'к',
    'd': 'д',
    'e': 'е',
    'f': 'ф',
    'g': 'г',
    'h': 'х',
    'i': 'и',
    'j': 'ж',
    'k': 'к',
    'l': 'л',
    'm': 'м',
    'n': 'н',
    'o': 'о',
    'p': 'п',
    'q': 'к',
    'r': 'р',
    's': 'с',
    't': 'т',
    'u': 'у',
    'v': 'в',
    'w': 'у',
    'x': 'кс',
    'y': 'й',
    'z': 'з',
    // қазақ латын әліпбиі (2021) және диакритикалар
    'ä': 'ә',
    'ğ': 'ғ',
    'ñ': 'ң',
    'ö': 'ө',
    'ū': 'ұ',
    'ü': 'ү',
    'ı': 'ы',
    'ş': 'ш',
    'ç': 'ч',
    'é': 'е',
  };

  /// Латын әріптері кириллден көп пе (сұранысты кириллге айналдыру керек пе).
  static bool isMostlyLatin(String s) {
    var lat = 0, cyr = 0;
    for (final r in s.runes) {
      if ((r >= 0x61 && r <= 0x7A) || (r >= 0x41 && r <= 0x5A)) {
        lat++;
      } else if (r >= 0x0400 && r <= 0x04FF) {
        cyr++;
      }
    }
    return lat > cyr;
  }

  /// Салыстыру түрі: кіші әріп, латын → кирилл, қазақ әріптері орыс
  /// баламасына, й/ы → и, ё/э → е, ь/ъ алынады, қатар тұрған бірдей әріп
  /// біреуге қысқарады (лл → л), әріп пен цифрдан басқасы — бос орын.
  /// Сөздер бір бос орынмен бөлінеді.
  static String fold(String s, {bool collapse = true}) {
    final src = latinToCyrillic(s);
    final b = StringBuffer();
    String? prev;
    var space = true;
    for (final ch in src.split('')) {
      var m = _foldMap[ch] ?? ch;
      if (m.isEmpty) continue;
      final isAlnum = _alnum.hasMatch(m);
      if (!isAlnum) {
        if (!space) {
          b.write(' ');
          space = true;
        }
        prev = null;
        continue;
      }
      // «Сейфуллин» мен «Сейфулин», «Кассымов» пен «Касымов» — бір атау.
      if (collapse && m == prev && !_digit.hasMatch(m)) continue;
      b.write(m);
      prev = m;
      space = false;
    }
    return b.toString().trim();
  }

  static final _alnum = RegExp(r'[a-zа-я0-9]');
  static final _digit = RegExp(r'[0-9]');

  static const _foldMap = {
    'ә': 'а',
    'ғ': 'г',
    'қ': 'к',
    'ң': 'н',
    'ө': 'о',
    'ұ': 'у',
    'ү': 'у',
    'һ': 'х',
    'і': 'и',
    'ё': 'е',
    'э': 'е',
    'й': 'и',
    'ы': 'и',
    'ь': '',
    'ъ': '',
  };

  // ---------------------------------------------------------------------
  //  КӨШЕ АТАУЫНЫҢ ӨЗЕГІ
  // ---------------------------------------------------------------------

  /// Көше/аудан ТИПІН білдіретін сөздер (fold түрінде). Атауды салыстырғанда
  /// алынып тасталады: «Төле би көшесі» = «улица Толе би» = «толе би».
  static const streetTypeWords = {
    'ул',
    'улица',
    'кошеси',
    'косеси',
    'коше',
    'проспект',
    'пр',
    'пр-т',
    'просп',
    'прт',
    'дангили',
    'данг',
    'переулок',
    'пер',
    'тупик',
    'туиик',
    'тупиги',
    'бульвар',
    'бул',
    'булвар',
    'шоссе',
    'тас',
    'жоли',
    'жол',
    'проезд',
    'пр-д',
    'площад',
    'алани',
    'набережная',
    'наб',
    'аллея',
    'тракт',
    'линия',
    'квартал',
    'тураргин',
    'массив',
    'жк',
  };

  /// Шағын аудан екенін АЙҚЫН білдіретін сөздер — нөмірмен бірге «мкр + нөмір»
  /// болып біріктіріледі («6 мкр», «мкр. 6», «6-й микрорайон», «6 шағын
  /// ауданы» — бәрі «мкр6»).
  static const _microStrong = {
    'мкр',
    'микрораион',
    'микр',
    'мкрн',
    'шагин',
    'шагинаудан',
    'шагинаудани',
    'икшам',
    'икшамаудан',
    'икшамаудани',
    'молтек',
    'молтекаудан',
    'молтекаудани',
  };

  /// Шағын аудан атауында ғана алынатын қосымша сөздер («ш/а» қысқартуы,
  /// «ауданы»). Жалғыз өзі шағын аудан белгісі емес.
  static const _microWeak = {'ш', 'а', 'аудан', 'аудани', 'шагинауд'};

  /// Нөмір жалғаулары: «6-й», «6-шы», «6-ші», «2-я».
  static final _ordinal = RegExp(r'^(\d+)(и|ши|я|ая|ои|ии|ш)?$');

  /// Дефиспен бөлінген реттік жалғау («6-й» → «6», «и»).
  static const _ordinalSuffix = {'и', 'ши', 'я', 'ая', 'ои', 'ии', 'ш'};

  /// Атаудың салыстыру ӨЗЕГІ: тип сөздерсіз, бос орынсыз.
  ///   «Төле би көшесі»        → «толеби»
  ///   «улица Наурызбай Батыра» → «наурызбаибатира»
  ///   «6-й микрорайон»         → «мкр6»
  static String streetCore(String name) => streetTokens(name).join();

  /// [w] тип сөзі ме — қате жазылса да («набережмая», «шағын ауан»).
  static bool _isTypeWord(String w) {
    if (streetTypeWords.contains(w)) return true;
    if (w.length < 6) return false;
    for (final t in _longTypeWords) {
      if ((t.length - w.length).abs() <= 1 && distance(w, t, max: 1) <= 1) {
        return true;
      }
    }
    return false;
  }

  static bool _isMicroWord(String w) {
    if (_microStrong.contains(w) || _microWeak.contains(w)) return true;
    if (w.length < 4) return false;
    for (final t in _microLong) {
      if ((t.length - w.length).abs() <= 1 && distance(w, t, max: 1) <= 1) {
        return true;
      }
    }
    return false;
  }

  static final _longTypeWords = [
    for (final w in streetTypeWords)
      if (w.length >= 6) w,
  ];
  static final _microLong = [
    for (final w in {..._microStrong, ..._microWeak})
      if (w.length >= 4) w,
  ];

  /// [streetCore]-дің сөздері (бос орынсыз біріктірілмеген түрі).
  static List<String> streetTokens(String name, {bool collapse = true}) {
    final raw = fold(
      name,
      collapse: collapse,
    ).split(' ').where((w) => w.isNotEmpty).toList();
    final hasMicro =
        raw.any(_microStrong.contains) || raw.any((w) => w.startsWith('мкр'));
    final out = <String>[];
    String? microNo;
    var prevNumeric = false;
    for (final w in raw) {
      final numeric = RegExp(r'^\d+$').hasMatch(w);
      if (prevNumeric && _ordinalSuffix.contains(w)) {
        prevNumeric = false;
        continue;
      }
      prevNumeric = numeric;
      if (_isTypeWord(w)) continue;
      if (hasMicro) {
        if (_isMicroWord(w)) continue;
        final m = _ordinal.firstMatch(w);
        if (m != null && microNo == null) {
          microNo = m.group(1);
          continue;
        }
        if (w.startsWith('мкр') && w.length > 3) {
          // «мкр6» не «мкрсамал» түрінде бірге жазылған
          final rest = w.substring(3);
          if (RegExp(r'^\d+$').hasMatch(rest) && microNo == null) {
            microNo = rest;
          } else {
            out.add(rest);
          }
          continue;
        }
      }
      out.add(w);
    }
    if (microNo != null && out.isEmpty) return ['мкр$microNo'];
    if (microNo != null) return [...out, microNo];
    return out;
  }

  // ---------------------------------------------------------------------
  //  ҰҚСАСТЫҚ
  // ---------------------------------------------------------------------

  /// Damerau–Levenshtein (OSA нұсқасы): кірістіру, өшіру, ауыстыру және
  /// көршілес екі әріптің орын алмасуы — әрқайсысы 1 қате.
  /// [max]-тан асса ерте тоқтап, `max + 1` қайтарады.
  static int distance(String a, String b, {int max = 3}) {
    if (a == b) return 0;
    final n = a.length, m = b.length;
    if ((n - m).abs() > max) return max + 1;
    if (n == 0) return m;
    if (m == 0) return n;
    var prev2 = List<int>.filled(m + 1, 0);
    var prev = List<int>.generate(m + 1, (j) => j);
    var cur = List<int>.filled(m + 1, 0);
    for (var i = 1; i <= n; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        if (ins < v) v = ins;
        final sub = prev[j - 1] + cost;
        if (sub < v) v = sub;
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          final tr = prev2[j - 2] + 1;
          if (tr < v) v = tr;
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > max) return max + 1;
      final t = prev2;
      prev2 = prev;
      prev = cur;
      cur = t;
    }
    return prev[m];
  }

  /// Сұраныс ұзындығына қарай кешірілетін қате саны: қысқа сөзде (≤3) —
  /// қате жоқ, 4–5 әріп — 1, ұзынырақ — 2.
  static int allowedTypos(int len) => len <= 3 ? 0 : (len <= 5 ? 1 : 2);

  /// Сұраныс өзегі [q] мен атау [name] қаншалықты ұқсас: 0 (мүлдем емес)
  /// … 1 (дәл сол). Атау толық жазылмаса да (теріп жатқанда) сәйкес келеді.
  static double similarity(String q, String name) =>
      similarityKey(NameKey.query(q), NameKey(name));

  /// [similarity]-дің алдын ала есептелген кілттермен нұсқасы (көп атауды
  /// бір сұраныспен салыстырғанда — әр атауды қайта талдамау үшін).
  ///
  /// ЕКІ түрде салыстырылады — қос әріп қысқартылған және қысқартылмаған:
  /// «Сейфулина» ~ «Сейфуллин» біріншісінде, ал «Раат» ~ «Рахат» (қысқарса
  /// «рат» болып кетеді) екіншісінде табылады.
  ///
  /// [words] — сұраныстың БІР БӨЛІГІ бойынша да салыстыру («абай туран» →
  /// «Тұран көшесі»). Әдепкі өшірулі: тек толық сұраныс ештеңеге ұқсамаса
  /// қосылады (әйтпесе «Кабанбай батыр» деген қате сұраныста жай
  /// «Кабанбай» көшесі дұрыс нәтижені ығыстырып жібереді).
  static double similarityKey(NameKey q, NameKey n, {bool words = false}) {
    var best = _bothForms(q.core, q.coreRaw, n);
    if (!words || best >= 0.8) return best;
    // Сұраныста БІРНЕШЕ атау болуы мүмкін: «абай туран» — аудан мен көше
    // бір жолда. Сөздердің бір бөлігі бойынша да салыстырамыз (әр алынған
    // сөзге айыппұл; басындағы сөз әдетте аудан — сәл көбірек айыппұл).
    final qt = q.tokens, qr = q.tokensRaw;
    if (qt.length < 2 || qt.length != qr.length) return best;
    for (var len = qt.length - 1; len >= 1; len--) {
      for (var st = 0; st + len <= qt.length; st++) {
        final w = qt.sublist(st, st + len).join();
        if (w.length < 4 || RegExp(r'^\d+$').hasMatch(w)) continue;
        final pen = 0.08 * (qt.length - len) + (st == 0 ? 0.01 : 0);
        final v = _bothForms(w, qr.sublist(st, st + len).join(), n) - pen;
        if (v > best) best = v;
      }
    }
    return best;
  }

  static double _bothForms(String c, String cr, NameKey n) {
    final a = _tokensScore(c, n.tokens);
    if (a >= 1) return a;
    final b = _tokensScore(cr, n.tokensRaw);
    return a > b ? a : b;
  }

  /// Шағын аудан белгісі ме — қазақша түрі («шағын ауданы»: атауы АЛДЫНДА)
  /// не орысша («мкр», «микрорайон»: атауы КЕЙІН). Белгі емес — null.
  static bool? microMarkerIsKazakh(String foldedWord) {
    final w = foldedWord;
    if (w.isEmpty) return null;
    for (final k in _microKz) {
      if (w == k || (w.length >= 5 && distance(w, k, max: 1) <= 1)) {
        return true;
      }
    }
    if (_microRu.contains(w) ||
        (w.length >= 8 && distance(w, 'микрораион', max: 2) <= 2)) {
      return false;
    }
    return null;
  }

  static const _microKz = {
    'шагин',
    'шагинаудан',
    'шагинаудани',
    'икшам',
    'икшамаудан',
    'икшамаудани',
    'молтек',
    'молтекаудан',
    'молтекаудани',
  };
  static const _microRu = {'мкр', 'мкрн', 'микр', 'микрораион', 'мкр-н'};

  /// «ауданы», «аудан», «ш», «а» — шағын аудан белгісінің жалғасы.
  static bool isMicroTail(String foldedWord) => _microWeak.contains(foldedWord);

  /// Көше типі сөзі ме (қате жазылса да).
  static bool isTypeWord(String foldedWord) => _isTypeWord(foldedWord);

  /// Реттік жалғау («6-й» → «й»).
  static bool isOrdinalSuffix(String foldedWord) =>
      _ordinalSuffix.contains(foldedWord);

  static double _tokensScore(String q, List<String> tokens) {
    if (q.isEmpty || tokens.isEmpty) return 0;
    var best = 0.0;
    // Атаудың әр сөзінен басталатын «құйрықтары»: «Ахмета Байтурсынова»
    // деген атауды «байтурсынова» деп іздегенде де табу үшін.
    for (var i = 0; i < tokens.length; i++) {
      final c = tokens.sublist(i).join();
      final penalty = i == 0 ? 0.0 : 0.06;
      final s = _coreScore(q, c) - penalty;
      if (s > best) best = s;
      if (best >= 1) break;
    }
    return best < 0 ? 0 : best;
  }

  static const _endings = {'а', 'я', 'у', 'и', 'е', 'о'};

  static double _coreScore(String q, String c) {
    if (c.isEmpty) return 0;
    if (q == c) return 1;
    final ql = q.length;
    // Теріп жатыр: «желто» → «желтоксан».
    if (c.startsWith(q)) {
      if (ql < 2) return 0;
      if (ql == 2) return 0.62;
      return 0.82 + 0.15 * (ql / c.length);
    }
    // Орысша жалғау: «сеифуллина» → «сеифуллин», «кабанбаибатира» →
    // «кабанбаибатир». Тек БІР дауысты әріп — әйтпесе «Алтын Аам» «Алтын»
    // көшесіне тартылып кетеді.
    if (ql == c.length + 1 &&
        c.length >= 4 &&
        q.startsWith(c) &&
        _endings.contains(q[ql - 1])) {
      return 0.88;
    }
    final allow = allowedTypos(ql);
    if (allow == 0) return 0;
    // Толық атауға 1–2 қатемен.
    final d = distance(q, c, max: allow);
    var best = d <= allow ? 0.8 - 0.07 * d : 0.0;
    // Теріп жатыр ЖӘНЕ қате бар: «жилто» → «желто…».
    if (c.length > ql) {
      for (final len in [ql, ql + 1]) {
        if (len > c.length) continue;
        final dp = distance(q, c.substring(0, len), max: allow);
        if (dp <= allow) {
          final s = 0.74 - 0.08 * dp;
          if (s > best) best = s;
        }
      }
    }
    return best;
  }
}

/// Атаудың салыстыру кілттері (бір рет есептеліп, қайта қолданылады).
class NameKey {
  /// Сөздер (қос әріп қысқартылған).
  final List<String> tokens;

  /// Сөздер (қос әріп қысқартылмаған).
  final List<String> tokensRaw;

  /// Біріктірілген өзек (екі түрде).
  final String core;
  final String coreRaw;

  NameKey(String name)
    : tokens = GeoText.streetTokens(name),
      tokensRaw = GeoText.streetTokens(name, collapse: false),
      core = '',
      coreRaw = '';

  /// Сұраныс кілті: біріктірілген өзек + сөздері (бір бөлігі бойынша
  /// салыстыру үшін).
  NameKey.query(String text)
    : this._q(
        GeoText.streetTokens(text),
        GeoText.streetTokens(text, collapse: false),
      );

  NameKey._q(this.tokens, this.tokensRaw)
    : core = tokens.join(),
      coreRaw = tokensRaw.join();
}

/// Клиент жазған мекенжай сұранысының бөлшектері.
class AddressQuery {
  /// Клиент жазған түрі.
  final String raw;

  /// Геокодерге жіберілетін мәтін (латын болса — кириллге айналған).
  final String text;

  /// Көше/нысан бөлігі (үй нөмірінсіз, қала атынсыз) — геокодерге.
  final String street;

  /// [street]-тің салыстыру өзегі ([GeoText.streetCore]).
  final String core;

  /// Үй нөмірі: «15», «15а», «15/2» (болса).
  final String? house;

  /// Шағын аудан (клиент жазса): «Абай», «Самал 2», «6». Көше одан бөлек
  /// ізделеді, ал аудан бір атаулы көшелердің ішінен дұрысын таңдауға
  /// көмектеседі.
  final String? district;

  /// [district]-тің салыстыру өзегі («абаи», «самал2», «мкр6»).
  final String? districtCore;

  AddressQuery({
    required this.raw,
    required this.text,
    required this.street,
    required this.core,
    required this.house,
    this.district,
    this.districtCore,
  });

  /// Басқаша бөлу нұсқалары: «мкр ұлы дала 5» — аудан «ұлы», көше «дала»
  /// ма, әлде аудан «ұлы дала» ма? Көше тізімі ([StreetIndex]) шешеді.
  List<AddressQuery> get alternatives => _alternatives;
  final List<AddressQuery> _alternatives = [];

  static final _houseRe = RegExp(
    r'^\d{1,4}[а-яәғқңөұүһіa-z]?(/\d{1,4}[а-яa-z]?)?$',
  );

  /// Сұранысты талдайды. [city] берілсе, сұраныстағы қала атауы алынады
  /// («абая 15 тараз» → көше «абая», үй «15»).
  factory AddressQuery.parse(String input, {String? city}) {
    final raw = input.trim();
    final text = GeoText.isMostlyLatin(raw)
        ? GeoText.latinToCyrillic(raw)
        : raw;
    final parts = text
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    // Қала атауы (қате жазылса да) — көше емес.
    final cityKey = city == null ? null : GeoText.streetCore(city);
    var kept = <String>[];
    for (final p in parts) {
      if (cityKey != null && cityKey.length >= 3) {
        final pk = GeoText.fold(p).replaceAll(' ', '');
        if (pk == cityKey ||
            (pk.length >= 4 && GeoText.distance(pk, cityKey, max: 1) <= 1)) {
          continue;
        }
      }
      kept.add(p);
    }
    // «Тараз даңғылы» — қала атымен аталған көше: қала атын алып тастасақ,
    // тек тип сөзі қалады. Ондайда атауды өзгеріссіз қалдырамыз.
    if (kept.length < parts.length &&
        GeoText.streetCore(
          kept.where((p) => !_houseRe.hasMatch(p.toLowerCase())).join(' '),
        ).isEmpty) {
      kept = List.of(parts);
    }
    // Үй нөмірі — СОҢҒЫ нөмірлі сөз («Самал-2, 15» → 15; «6 мкр 12» → 12).
    // Бөлек тұрған бір әріп алдыңғы нөмірге жалғанады («15 а» → «15а»).
    String? house;
    var houseAt = -1;
    for (var i = kept.length - 1; i >= 0; i--) {
      final w = kept[i].toLowerCase().replaceAll(RegExp(r'^№'), '');
      if (_houseRe.hasMatch(w)) {
        house = w;
        houseAt = i;
        if (i + 1 < kept.length &&
            RegExp(r'^[а-яәa-z]$').hasMatch(kept[i + 1].toLowerCase())) {
          house = '$w${kept[i + 1].toLowerCase()}';
          kept.removeAt(i + 1);
        }
        break;
      }
    }
    final streetWords = [
      for (var i = 0; i < kept.length; i++)
        if (i != houseAt) kept[i],
    ];
    // Нөмір жалғыз болып, көше сөзі қалмаса — ол үй емес, атаудың бөлігі.
    final street = streetWords.join(' ').trim();
    if (house != null && GeoText.streetCore(street).isEmpty) {
      return AddressQuery(
        raw: raw,
        text: text,
        street: text,
        core: GeoText.streetCore(text),
        house: null,
      );
    }
    final splits = _splitDistrict(text, streetWords);
    if (splits == null) {
      return AddressQuery(
        raw: raw,
        text: text,
        street: street,
        core: GeoText.streetCore(street),
        house: house,
      );
    }
    final variants = [
      for (final sp in splits) _withDistrict(raw, text, house, sp),
    ];
    return variants.first.._alternatives.addAll(variants.skip(1));
  }

  static AddressQuery _withDistrict(
    String raw,
    String text,
    String? house,
    (List<String>, List<String>) split,
  ) {
    final (dWords, sWords) = split;
    final dText = dWords.join(' ');
    final dCore = RegExp(r'^\d+$').hasMatch(dText)
        ? 'мкр$dText'
        : GeoText.streetCore(dText);
    // Көше жазылмаса — ізделетін нысан аудан ӨЗІ («мкр Самал 2, 15»).
    final sText = sWords.join(' ').trim();
    final streetText = GeoText.streetCore(sText).isEmpty
        ? (RegExp(r'^\d+$').hasMatch(dText) ? '$dText мкр' : dText)
        : sText;
    return AddressQuery(
      raw: raw,
      text: text,
      street: streetText,
      core: GeoText.streetCore(sText).isEmpty
          ? dCore
          : GeoText.streetCore(sText),
      house: house,
      district: dText,
      districtCore: dCore,
    );
  }

  /// Сұраныстағы ШАҒЫН АУДАНДЫ көшеден бөледі. Аудан белгісі жоқ болса —
  /// null (бүкіл сұраныс көше саналады).
  ///
  /// Қазақтар мекенжайды әртүрлі жазады:
  ///   «Абай шағын ауданы, Тұран көшесі, 15» — үтірмен бөліктер;
  ///   «микрорайон абай тұран 15», «мкр абай туран 15» — орысша белгі,
  ///     аудан аты белгіден КЕЙІН;
  ///   «абай мкр туран 15», «Самал-2 шағын ауданы» — аты белгіден БҰРЫН;
  ///   «6 мкр 12» — нөмірлі шағын аудан.
  static List<(List<String>, List<String>)>? _splitDistrict(
    String text,
    List<String> streetWords,
  ) {
    // Үтірмен бөлінген болса — бөлік бойынша: белгісі бар бөлік — аудан.
    final segments = text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final words = <String>[
      for (final w in streetWords) ...w.split(RegExp(r'[\s\-–—]+')),
    ].where((w) => w.isNotEmpty).toList();
    final folded = [for (final w in words) GeoText.fold(w)];
    final marker = <int, bool>{}; // индекс → қазақша белгі ме
    for (var i = 0; i < folded.length; i++) {
      final f = folded[i];
      final kz = GeoText.microMarkerIsKazakh(f);
      if (kz != null) {
        marker[i] = kz;
      } else if (f.startsWith('мкр') && f.length > 3) {
        // «мкр6», «мкрсамал» — бірге жазылған
        words[i] = words[i].substring(3);
        folded[i] = f.substring(3);
        words.insert(i, 'мкр');
        folded.insert(i, 'мкр');
        marker[i] = false;
        i++;
      }
    }
    if (marker.isEmpty) return null;

    bool isNumAt(int i) =>
        i >= 0 && i < folded.length && RegExp(r'^\d+$').hasMatch(folded[i]);
    // «12-ші», «6-й» — нөмірден кейінгі реттік жалғау: жеке сөз емес.
    bool isSuffix(int i) =>
        isNumAt(i - 1) && GeoText.isOrdinalSuffix(folded[i]);
    bool isName(int i) =>
        i >= 0 &&
        i < folded.length &&
        folded[i].isNotEmpty &&
        !marker.containsKey(i) &&
        !isSuffix(i) &&
        !GeoText.isMicroTail(folded[i]) &&
        !GeoText.isTypeWord(folded[i]);
    bool isNum(int i) => isName(i) && isNumAt(i);

    final taken = <int>{...marker.keys};
    for (var i = 0; i < folded.length; i++) {
      if (isSuffix(i)) taken.add(i);
    }
    // Белгінің жалғасы («шағын ауданы», «ш. а.»).
    for (final m in marker.keys) {
      var j = m + 1;
      while (j < folded.length && GeoText.isMicroTail(folded[j])) {
        taken.add(j);
        j++;
      }
    }

    // Үтір бөліктері: аудан белгісі тұрған бөліктің аттары — аудан.
    if (segments.length > 1) {
      final dist = <int>[];
      var pos = 0;
      for (final seg in segments) {
        final n = seg
            .split(RegExp(r'[\s\-–—]+'))
            .where((w) => w.isNotEmpty)
            .length;
        final idx = [for (var k = pos; k < pos + n && k < words.length; k++) k];
        if (idx.any(marker.containsKey)) {
          dist.addAll(idx.where((k) => !taken.contains(k) && isName(k)));
        }
        pos += n;
      }
      if (dist.isNotEmpty) return [_build(words, dist, taken)];
    }

    // Белгі бойынша: орысша — аты кейін, қазақша — аты бұрын.
    final m = marker.keys.reduce((a, b) => a < b ? a : b);
    var end = m;
    while (taken.contains(end + 1)) {
      end++;
    }
    // [greedy] — көп сөзді атау («Ұлы Дала», «Алтын Орда»): белгінің
    // жанындағы БАРЛЫҚ атауларды алады. Әйтпесе — бір сөз (+ нөмірі):
    // «мкр абай туран» → аудан «абай», көше «туран». Қайсысы дұрыс екенін
    // көше тізімі шешеді (сондай шағын аудан бар ма) — екеуі де қайтады.
    List<int> after({bool greedy = false}) {
      final out = <int>[];
      var k = end + 1;
      if (!isName(k)) return out;
      out.add(k);
      if (greedy) {
        k++;
        while (isName(k)) {
          out.add(k);
          k++;
        }
        return out;
      }
      // «Самал 2» — аттан кейінгі нөмір де аудан атына кіреді, бірақ
      // нөмір ғана болса («мкр 6»), келесі сөз — көше.
      if (!isNum(k)) {
        k++;
        while (isNum(k)) {
          out.add(k);
          k++;
        }
      }
      return out;
    }

    List<int> before({bool greedy = false}) {
      final out = <int>[];
      var k = m - 1;
      while (taken.contains(k) && !marker.containsKey(k)) {
        k--; // реттік жалғау («12-ші шағын ауданы»)
      }
      while (isNum(k)) {
        out.insert(0, k);
        k--;
      }
      if (isName(k) && !isNum(k)) {
        out.insert(0, k);
        k--;
        while (greedy && isName(k)) {
          out.insert(0, k);
          k--;
        }
      }
      // «Тұран көшесі мкр Абай»: белгінің алдындағы сөз — КӨШЕ (оның
      // алдында/артында көше типі тұр), аудан емес.
      if (out.isNotEmpty &&
          ((k >= 0 && GeoText.isTypeWord(folded[k])) ||
              (out.last + 1 < m && GeoText.isTypeWord(folded[out.last + 1])))) {
        return const [];
      }
      return out;
    }

    // Қазақша белгі — аты алдында; орысша — алдында сөз болса соны
    // («абай мкр», «Самал-2 мкр»), белгі басында тұрса — кейінгісін
    // («мкр абай»).
    final kz = marker[m]!;
    List<int> pick({required bool greedy}) {
      var d = before(greedy: greedy);
      if (d.isEmpty) d = after(greedy: greedy);
      if (!kz && m == 0) d = after(greedy: greedy);
      return d;
    }

    final dist = pick(greedy: false);
    if (dist.isEmpty) return null;
    final wide = pick(greedy: true);
    return [
      _build(words, dist, taken),
      if (wide.length > dist.length) _build(words, wide, taken),
    ];
  }

  static (List<String>, List<String>) _build(
    List<String> words,
    List<int> dist,
    Set<int> taken,
  ) {
    final d = [for (final k in dist) words[k]];
    final rest = [
      for (var k = 0; k < words.length; k++)
        if (!taken.contains(k) && !dist.contains(k)) words[k],
    ];
    return (d, rest);
  }
}
