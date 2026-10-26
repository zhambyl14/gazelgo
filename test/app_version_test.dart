import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/core/app_version.dart';

void main() {
  group('parseMinVersion', () {
    test('бүтін сан — build', () {
      final v = parseMinVersion('29')!;
      expect((v.build, v.version), (29, ''));
    });

    test('1.0.11 — дүкен нұсқасы', () {
      final v = parseMinVersion(' 1.0.11 ')!;
      expect((v.build, v.version), (0, '1.0.11'));
      expect(v.text, '1.0.11');
    });

    test('1.0.11+35 — нұсқа да, build те', () {
      final v = parseMinVersion('1.0.11+35')!;
      expect((v.build, v.version), (35, '1.0.11'));
      expect(v.text, '1.0.11+35');
    });

    test('бос — 0; қате жазу — null', () {
      expect(parseMinVersion('')!.build, 0);
      expect(parseMinVersion('abc'), isNull);
      expect(parseMinVersion('1..0'), isNull);
      expect(parseMinVersion('1.0.x'), isNull);
    });
  });

  test('compareVersions сандық: 1.0.11 > 1.0.9', () {
    expect(compareVersions('1.0.11', '1.0.9') > 0, isTrue);
    expect(compareVersions('1.0.8', '1.0.11') < 0, isTrue);
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('1.0.11+35', '1.0.11'), 0);
  });

  group('isBelowMin', () {
    bool below(String my, int build, int minB, String minV) => isBelowMin(
      myVersion: my,
      myBuild: build,
      minBuild: minB,
      minVersion: minV,
    );

    test('нұсқа бойынша', () {
      expect(below('1.0.8', 29, 0, '1.0.11'), isTrue);
      expect(below('1.0.11', 35, 0, '1.0.11'), isFalse);
      expect(below('1.1.0', 40, 0, '1.0.11'), isFalse);
    });

    test('build бойынша (бұрынғы мінез)', () {
      expect(below('1.0.8', 29, 30, ''), isTrue);
      expect(below('1.0.8', 30, 30, ''), isFalse);
      expect(below('1.0.8', 0, 30, ''), isFalse); // build белгісіз — өткізеді
    });

    test('шек жоқ — бұғаттамайды', () {
      expect(below('0.0.1', 1, 0, ''), isFalse);
    });
  });
}
