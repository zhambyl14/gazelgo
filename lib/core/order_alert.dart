import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';

/// Лентада ЖАҢА заказ шыққандағы дыбыс пен діріл.
///
/// Жаңа заказда дыбыс [_repeats] (5) рет қатарынан қайталанады: телефонда
/// хабарландыру өшірулі болса, push дыбысы шықпайды — лентадағы осы
/// дабыл орындаушының заказды байқауының жалғыз жолы. Бір ғана [AudioPlayer]
/// қайта қолданылады; дабыл жүріп жатқанда жаңа дабыл қосылмайды.
/// Музыка/навигатор ойнап тұрса — тоқтатылмайды, тек сәл бәсеңдейді
/// (duckOthers).
class OrderAlert {
  OrderAlert._();

  static const _asset = 'sounds/new_order.wav';
  static const _minGap = Duration(seconds: 3);

  /// Жаңа заказда дыбыс неше рет қайталанады және қайталаулар арасы.
  static const _repeats = 5;
  static const _repeatGap = Duration(milliseconds: 350);

  /// Дыбыс қосулы ма ([Prefs.orderSound]) — лентадағы батырма тыңдайды.
  static final ValueNotifier<bool> soundOn = ValueNotifier(true);

  /// Лента ашық болғанда орнатады: берілген заказ туралы лента ӨЗІ дабыл
  /// бере ме (экранда тұр, заказды әлі көрмеген).
  static bool Function(String orderId)? feedProbe;

  /// Жаңа заказ push-ын қосымша ішінде көрсетпеуге бола ма — лента оны
  /// өзі көрсетеді (дыбыс екі рет естілмесін). Бұрыннан көрген заказдың
  /// қайта ескертуі (escalation) әдеттегідей шығады.
  static bool feedWillAlert(String? orderId) =>
      orderId != null && (feedProbe?.call(orderId) ?? false);

  static AudioPlayer? _player;
  static DateTime? _lastAt;
  static bool _loaded = false;

  /// Дабыл сериясының нөмірі: жаңа серия (не үлгі) ескісін тоқтатады.
  static int _run = 0;
  static bool _playing = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    soundOn.value = await Prefs.orderSound();
  }

  static Future<void> setSound(bool v) async {
    soundOn.value = v;
    await Prefs.setOrderSound(v);
    if (v) await play(force: true);
  }

  /// Дыбыс + діріл. Әдетте [_repeats] рет қайталанады; [force] — батырманы
  /// қосқанда үлгі ретінде БІР рет ойнату (жүріп жатқан сериясын үзеді).
  static Future<void> play({bool force = false}) async {
    final now = DateTime.now();
    if (!force && (_playing || _inGap(now))) return;
    _lastAt = now;
    HapticFeedback.mediumImpact();
    if (!soundOn.value) return;
    final run = ++_run;
    _playing = true;
    try {
      final p = _player ??= await _create();
      final times = force ? 1 : _repeats;
      for (var i = 0; i < times; i++) {
        if (run != _run || !soundOn.value) break;
        await p.stop();
        // Аяқталуын алдын ала тыңдаймыз; браузерде оқиға келмесе — тайм-аут.
        final done = p.onPlayerComplete.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
        await p.play(AssetSource(_asset), volume: 0.9);
        await done;
        if (i < times - 1) {
          HapticFeedback.mediumImpact();
          await Future<void>.delayed(_repeatGap);
        }
      }
    } catch (_) {
      // Дыбыс ойнамаса (браузер автоойнатуды бұғаттады т.б.) — лента
      // жұмысына әсер етпейді.
    } finally {
      if (run == _run) _playing = false;
    }
  }

  static bool _inGap(DateTime now) =>
      _lastAt != null && now.difference(_lastAt!) < _minGap;

  static Future<AudioPlayer> _create() async {
    final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    if (!kIsWeb) {
      await p.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.duckOthers).build(),
      );
    }
    return p;
  }
}
