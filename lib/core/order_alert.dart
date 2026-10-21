import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';

/// Лентада ЖАҢА заказ шыққандағы дыбыс пен діріл.
///
/// Бір ғана [AudioPlayer] қайта қолданылады; дыбыс жиі қайталанбайды
/// (3 с ішінде бір рет). Музыка/навигатор ойнап тұрса — тоқтатылмайды,
/// тек сәл бәсеңдейді (duckOthers).
class OrderAlert {
  OrderAlert._();

  static const _asset = 'sounds/new_order.wav';
  static const _minGap = Duration(seconds: 3);

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

  /// Дыбыс + діріл. [force] — батырманы қосқанда үлгі ретінде ойнату.
  static Future<void> play({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastAt != null && now.difference(_lastAt!) < _minGap) {
      return;
    }
    _lastAt = now;
    HapticFeedback.mediumImpact();
    if (!soundOn.value) return;
    try {
      final p = _player ??= await _create();
      await p.stop();
      await p.play(AssetSource(_asset), volume: 0.9);
    } catch (_) {
      // Дыбыс ойнамаса (браузер автоойнатуды бұғаттады т.б.) — лента
      // жұмысына әсер етпейді.
    }
  }

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
