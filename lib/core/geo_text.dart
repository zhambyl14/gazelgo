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
  static double similarityKey(NameKey q, NameKey n) {
    final a = _tokensScore(q.core, n.tokens);
    if (a >= 1) return a;
    final b = _tokensScore(q.coreRaw, n.tokensRaw);
    return a > b ? a : b;
  }

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

  /// Сұраныс кілті: тек біріктірілген өзек керек.
  NameKey.query(String text)
    : tokens = const [],
      tokensRaw = const [],
      core = GeoText.streetTokens(text).join(),
      coreRaw = GeoText.streetTokens(text, collapse: false).join();
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

  const AddressQuery({
    required this.raw,
    required this.text,
    required this.street,
    required this.core,
    required this.house,
  });

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
    return AddressQuery(
      raw: raw,
      text: text,
      street: street,
      core: GeoText.streetCore(street),
      house: house,
    );
  }
}
