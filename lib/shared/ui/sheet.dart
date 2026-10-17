import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lang.dart';
import '../../core/theme.dart';
import 'bits.dart';

/// «Камерамен түсіру / Галереядан таңдау» — бүкіл қосымшада бір терезе
/// (заказ фотосы, хабарландыру суреті…). Бас тартса — `null`.
Future<ImageSource?> pickImageSource(BuildContext context) {
  return showGzSheet<ImageSource>(
    context,
    builder: (ctx) => GzSheetBody(
      title: t('Фото қосу'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GzListRow(
            icon: Icons.photo_camera_outlined,
            color: Gz.info,
            title: t('Камерамен түсіру'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          GzListRow(
            icon: Icons.photo_library_outlined,
            color: Gz.accent,
            title: t('Галереядан таңдау'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

/// Төменнен ашылатын терезе (bottom sheet) — бүкіл қосымшада БІР үлгі:
/// ақ фон, жоғарғы бұрыштары [Gz.rXl], ортасында тұтқа.
///
/// Бұрын әр экран `showModalBottomSheet`-ті өзінше шақыратын: бірінде
/// радиус 20, бірінде 26, бірінде тұтқа бар, бірінде жоқ — терезелер
/// «әр қосымшадан алынғандай» көрінетін.
Future<T?> showGzSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: Gz.surface,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Gz.rXl)),
    ),
    builder: builder,
  );
}

/// Терезенің жоғарғы ортасындағы тартуға арналған «тұтқа».
class GzHandle extends StatelessWidget {
  const GzHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        decoration: BoxDecoration(
          color: Gz.disabledBg,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Терезенің стандарт денесі: тұтқа → тақырып (+ ✕) → мазмұн.
///
/// Пернетақта ашылғанда мазмұн оның үстіне көтеріледі, ал төменгі жүйелік
/// жолақ (gesture bar) ескеріледі — әр экранда қолмен қайталаудың қажеті жоқ.
class GzSheetBody extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;

  /// Оң жақ жоғарыда «✕» батырмасы көрінсін бе.
  final bool showClose;
  final EdgeInsets padding;

  const GzSheetBody({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.showClose = false,
    this.padding = const EdgeInsets.fromLTRB(18, 0, 18, 18),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GzHandle(),
            if (title != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  4,
                  showClose ? 6 : padding.right,
                  12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: Gz.h2),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(subtitle!, style: Gz.bodyMuted),
                          ],
                        ],
                      ),
                    ),
                    if (showClose)
                      IconButton(
                        tooltip: t('Жабу'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Gz.surfaceAlt,
                          foregroundColor: Gz.textSecondary,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                  ],
                ),
              ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  title == null ? 4 : 0,
                  padding.right,
                  padding.bottom,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
