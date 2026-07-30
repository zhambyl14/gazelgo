import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/features/legal/legal_screen.dart';

/// Заңдық құжаттардың ҚҰРЫЛЫМЫН тексеру.
///
/// Құжат экраны мәтінді ЖОЛМА-ЖОЛ талдап, «5. ТЫЙЫМ САЛЫНҒАН ЖҮКТЕР»
/// тәрізді жолдарды бөлім тақырыбы деп таниды. Ал заказ бетіндегі «Тізім»
/// сілтемесі [kProhibitedCargoSection] нөмірі бойынша сол бөлімге скролл
/// жасайды.
///
/// Бұл байланыс ҮНСІЗ сынғыш: мәтінде нөмір өзгерсе не бос орын жоғалса,
/// скролл ЕШТЕҢЕ ІСТЕМЕЙДІ — қате де шықпайды, қолданушы жай ғана
/// құжаттың басында қалады. Сол себепті инвариантты тест ұстауы керек.
void main() {
  // Экрандағы талдағышпен ДӘЛ БІРДЕЙ: нөмір + нүкте + БОС ОРЫН + мәтін.
  final reSection = RegExp(r'^(\d+)\.\s+(.+)$');

  List<int> sectionNumbers(String doc) => [
        for (final line in doc.trim().split('\n'))
          if (reSection.firstMatch(line.trim()) case final m?)
            int.parse(m.group(1)!),
      ];

  const docs = {
    'kTermsText (kk)': kTermsText,
    'kTermsTextRu (ru)': kTermsTextRu,
    'kPrivacyText (kk)': kPrivacyText,
    'kPrivacyTextRu (ru)': kPrivacyTextRu,
  };

  test('әр құжатта бөлімдер 1-ден бастап ҮЗІЛІССІЗ нөмірленген', () {
    docs.forEach((name, doc) {
      final nums = sectionNumbers(doc);
      expect(nums, isNotEmpty, reason: '$name: бірде-бір бөлім танылмады');
      expect(
        nums,
        List.generate(nums.length, (i) => i + 1),
        reason: '$name: бөлім нөмірлері үзіліссіз 1..N болуы керек',
      );
    });
  });

  test('«Тізім» сілтемесі апаратын бөлім ЕКІ ТІЛДЕ де бар', () {
    for (final name in ['kTermsText (kk)', 'kTermsTextRu (ru)']) {
      expect(
        sectionNumbers(docs[name]!),
        contains(kProhibitedCargoSection),
        reason: '$name ішінде $kProhibitedCargoSection-бөлім жоқ — '
            'заказ бетіндегі «Тізім» сілтемесі ешқайда апармайды',
      );
    }
  });

  test('келісімнің қазақша және орысша нұсқасы бірдей құрылымды', () {
    expect(
      sectionNumbers(kTermsText),
      sectionNumbers(kTermsTextRu),
      reason: 'Екі тілдегі бөлім нөмірлері сәйкес келмейді — құжаттағы '
          'өзара сілтемелер («5-бөлім», «раздел 5») бұзылады',
    );
    expect(sectionNumbers(kPrivacyText), sectionNumbers(kPrivacyTextRu));
  });

  test('әр құжат атаумен және «соңғы жаңартылуы» жолымен басталады', () {
    docs.forEach((name, doc) {
      final lines = doc.trim().split('\n');
      expect(lines.first.trim(), isNotEmpty, reason: '$name: атауы жоқ');
      // Талдағыш күнді ДӘЛ осы префикстер бойынша ажыратады.
      expect(
        lines[1].trim().startsWith('Соңғы жаңартылуы') ||
            lines[1].trim().startsWith('Последнее обновление'),
        isTrue,
        reason: '$name: екінші жол «Соңғы жаңартылуы»/«Последнее обновление» '
            'болуы керек — әйтпесе күн қарапайым абзац болып салынады',
      );
    });
  });
}
