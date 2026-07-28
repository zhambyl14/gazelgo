import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Қосымша ӘРҚАШАН тік (9:16) форматта салынады.
///
/// Android/iOS-та бұрылысты жүйенің өзі бұғаттайды (AndroidManifest
/// `screenOrientation="portrait"`, Info.plist тек `Portrait`), сол себепті
/// онда бұл жақтау ешқашан іске қосылмайды.
///
/// Бірақ ВЕБТЕ (браузер терезесі, ноутбук, планшет) бұрылысты бұғаттау
/// мүмкін емес — терезе кең болса, экрандар (карта, төменгі панельдер,
/// хабарландыру карточкалары) созылып бұзылатын. Сол себепті терезе
/// 9:16-дан КЕҢ болса, қосымша дәл сол пропорциядағы тік «телефон»
/// аймағында, ортада салынады, шеттері бейтарап фонға қалады.
///
/// МАҢЫЗДЫ: MediaQuery-дің `size`-ы да сол аймаққа қиылады — әйтпесе ішкі
/// экрандар терезенің НАҚТЫ енін алып, есептеулері (карта биіктігі,
/// адаптив кестелер) қате шығатын еді.
class PortraitFrame extends StatelessWidget {
  /// Ені/биіктігі — тік телефон форматы.
  static const double aspect = 9 / 16;

  final Widget child;
  const PortraitFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final maxWidth = size.height * aspect;

    // Кәдімгі тік телефон — ештеңе өзгертпейміз (артық widget та қоспаймыз).
    if (size.width <= maxWidth + 0.5) return child;

    return ColoredBox(
      color: Gz.ink,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          height: size.height,
          child: ClipRect(
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(maxWidth, size.height),
                // Бүйірдегі жүйелік шегіністер (ноутбуктың «құлағы», кең
                // экранның қауіпсіз аймағы) енді жақтаудан тыс қалды.
                padding: mq.padding.copyWith(left: 0, right: 0),
                viewPadding: mq.viewPadding.copyWith(left: 0, right: 0),
                viewInsets: mq.viewInsets.copyWith(left: 0, right: 0),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
