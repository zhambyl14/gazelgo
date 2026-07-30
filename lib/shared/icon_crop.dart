/// Көлік иконкасын КЕСУ экраны (0050).
///
/// Модератор кез келген PNG/JPG таңдайды, суреттің КЕРЕК ЖЕРІН шаршы
/// рамкаға сүйреп/масштабтап дәл келтіреді, ал қалғаны — артық шеттері —
/// кесіліп тасталады. Нәтижесі әрқашан 512×512 МӨЛДІР фонды PNG: қосымша
/// ішіндегі басқа иконкалармен дәл бір өлшемде тұрады, өлшемін қолмен
/// келтірудің қажеті жоқ.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../core/lang.dart';
import '../core/theme.dart';

/// Дайын иконканың қабырғасы. Қосымшамен бірге келген суреттер де 512×512.
const int kVehicleIconSize = 512;

/// Кесілген суретті шаршының ішінде аздап «ауамен» тұрсын деп қалдырылатын
/// жиек — карусель карточкасында иконка рамкаға тығылып тұрмайды.
const int _kPadding = 8;

/// Сурет таңдау + кесу. Қайтарады: жүктеуге дайын PNG байттары
/// (пайдаланушы бас тартса — `null`).
Future<Uint8List?> pickAndCropIcon(BuildContext context) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // Кесу экранына АСА үлкен сурет келмеуі үшін (жады + жылдамдық).
    // Соңғы өлшемді бәрібір өзіміз келтіреміз.
    maxWidth: 2048,
    maxHeight: 2048,
  );
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return null;

  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => IconCropScreen(source: bytes)),
  );
}

// ---------------------------------------------------------------------------
// Кесу экраны
// ---------------------------------------------------------------------------

class IconCropScreen extends StatefulWidget {
  final Uint8List source;

  const IconCropScreen({super.key, required this.source});

  @override
  State<IconCropScreen> createState() => _IconCropScreenState();
}

class _IconCropScreenState extends State<IconCropScreen> {
  final _controller = TransformationController();

  /// Түпнұсқа суреттің өлшемі (пиксель) — кесу тіктөртбұрышын есептеу үшін.
  Size? _imageSize;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final d = await decodeImageFromList(widget.source);
    if (!mounted) return;
    setState(() =>
        _imageSize = Size(d.width.toDouble(), d.height.toDouble()));
    d.dispose();
  }

  void _reset() => _controller.value = Matrix4.identity();

  Future<void> _apply(double viewport) async {
    final size = _imageSize;
    if (size == null || _busy) return;
    setState(() => _busy = true);
    try {
      final rect = _sourceRect(size, viewport);
      final png = await _renderIcon(
        _CropJob(bytes: widget.source, rect: rect),
      );
      if (!mounted) return;
      Navigator.of(context).pop(png);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, errText(e), error: true);
    }
  }

  /// Экрандағы шаршы терезенің ТҮПНҰСҚА суреттегі орнын есептеу.
  ///
  /// Сурет терезеге `BoxFit.contain` тәсілімен салынған (яғни біркелкі
  /// кішірейтілген әрі ортаға қойылған), одан кейін [InteractiveViewer]
  /// оны тағы да `k` есе үлкейтіп, `t` шамасына жылжытқан. Осы екі
  /// түрлендіруді кері қайтарамыз.
  Rect _sourceRect(Size image, double viewport) {
    final m = _controller.value;
    final k = m.getMaxScaleOnAxis();
    final tx = m.getTranslation().x;
    final ty = m.getTranslation().y;

    // 1) InteractiveViewer-ді кері қайтару: терезенің төрт бұрышы
    //    масштабталмаған қабатта қайда тұр.
    final left = -tx / k;
    final top = -ty / k;
    final side = viewport / k;

    // 2) `contain` масштабы мен әріп-қорап (letterbox) шегінісі.
    final fit = math.min(viewport / image.width, viewport / image.height);
    final dx = (viewport - image.width * fit) / 2;
    final dy = (viewport - image.height * fit) / 2;

    // 3) Суреттің НАҚТЫ пиксельдеріне көшу.
    final x0 = (left - dx) / fit;
    final y0 = (top - dy) / fit;
    final w = side / fit;

    return Rect.fromLTWH(x0, y0, w, w);
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return Scaffold(
      backgroundColor: Gz.ink,
      appBar: AppBar(
        backgroundColor: Gz.ink,
        foregroundColor: Colors.white,
        title: Text(t('Иконканы кесу'), style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _reset,
            child: Text(t('Қалпына'),
                style: const TextStyle(color: Gz.yellow)),
          ),
        ],
      ),
      body: size == null
          ? const Center(child: CircularProgressIndicator(color: Gz.yellow))
          : LayoutBuilder(
              builder: (context, c) {
                // Шаршы терезе — экранның еніне (не биіктігіне) сыятын
                // ең үлкені, бірақ түсіндірме мен батырмаға орын қалады.
                final side = math.min(c.maxWidth - 32, c.maxHeight - 190)
                    .clamp(160.0, 420.0);
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      t('Керек жерін рамкаға келтіріңіз — қалғаны кесіледі'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Center(child: _window(side.toDouble(), size)),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed:
                              _busy ? null : () => _apply(side.toDouble()),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Gz.ink),
                                )
                              : const Icon(Icons.check),
                          label: Text(t('Дайын')),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Кесу терезесі: мөлдірлікті көрсететін шахмат фоны + сурет + рамка.
  Widget _window(double side, Size image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _CheckerPainter()),
            InteractiveViewer(
              transformationController: _controller,
              minScale: 0.5,
              maxScale: 8,
              // Терезеден шығып кетуге рұқсат: суреттің дәл ШЕТІН де
              // рамкаға әкелуге болады (әйтпесе жиегі қол жетпей қалады).
              boundaryMargin: EdgeInsets.all(side),
              clipBehavior: Clip.none,
              child: Image.memory(
                widget.source,
                width: side,
                height: side,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _FramePainter(), size: Size.square(side)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Кескіндеу
// ---------------------------------------------------------------------------

class _CropJob {
  final Uint8List bytes;
  final Rect rect;
  const _CropJob({required this.bytes, required this.rect});
}

/// Кесу + өлшемді келтіру. Нәтиже — [kVehicleIconSize] қабырғалы, МӨЛДІР
/// фонды, ортасында суреті бар PNG.
///
/// Кесу тіктөртбұрышы суреттен шығып тұрса (модератор рамканы шетке
/// апарса) — сол жағы жай ғана мөлдір болып қалады, қате шықпайды.
Future<Uint8List> _renderIcon(_CropJob job) async {
  final src = img.decodeImage(job.bytes);
  if (src == null) throw Exception('BAD_IMAGE');

  final side = math.max(1, job.rect.width.round());
  final rx = job.rect.left.round();
  final ry = job.rect.top.round();

  // Мөлдір «кенеп» — кесілген аймақ түгелдей суреттің ішінде болмаса да
  // (модератор рамканы шетке апарса) нәтиже ӘРҚАШАН шаршы болып шығады,
  // сыртта қалған жағы жай ғана мөлдір.
  final canvas = img.Image(width: side, height: side, numChannels: 4);

  // Рамка мен суреттің ҚИЫЛЫСЫ. Барлық координата осыдан кейін оң әрі
  // шектің ішінде — сол себепті `compositeImage` суретті созып жібермейді
  // (өлшемдерді АНЫҚ беру де сол үшін: әдепкі мәндері кенеп кішірек болса
  // суретті сығып жіберер еді).
  final x0 = math.max(0, rx);
  final y0 = math.max(0, ry);
  final x1 = math.min(src.width, rx + side);
  final y1 = math.min(src.height, ry + side);
  if (x1 <= x0 || y1 <= y0) throw Exception('EMPTY_CROP');

  final part = img.copyCrop(src,
      x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  img.compositeImage(
    canvas,
    part,
    dstX: x0 - rx,
    dstY: y0 - ry,
    dstW: part.width,
    dstH: part.height,
    srcW: part.width,
    srcH: part.height,
  );

  // Артық жиектерді қиямыз: модератор рамканы дәл келтірмесе де иконка
  // карточкада басқалармен бірдей «толықтықта» көрінеді. Алдымен мөлдір
  // жиек, ол ештеңе бермесе (мыс. JPEG — ақ фонды, мөлдірлігі жоқ сурет)
  // — бұрыш ТҮСІ бойынша.
  var content = img.trim(canvas, mode: img.TrimMode.transparent);
  if (content.width >= canvas.width && content.height >= canvas.height) {
    content = img.trim(canvas, mode: img.TrimMode.topLeftColor);
  }
  if (content.width < 2 || content.height < 2) content = canvas;

  const box = kVehicleIconSize - _kPadding * 2;
  final k = math.min(box / content.width, box / content.height);
  final fitted = img.copyResize(
    content,
    width: math.max(1, (content.width * k).round()),
    height: math.max(1, (content.height * k).round()),
    interpolation: img.Interpolation.cubic,
  );

  final out = img.Image(
      width: kVehicleIconSize, height: kVehicleIconSize, numChannels: 4);
  img.compositeImage(
    out,
    fitted,
    dstX: (kVehicleIconSize - fitted.width) ~/ 2,
    dstY: (kVehicleIconSize - fitted.height) ~/ 2,
  );

  return img.encodePng(out);
}

// ---------------------------------------------------------------------------
// Безендіру
// ---------------------------------------------------------------------------

/// Мөлдірлікті көрсететін шахмат фоны — модератор суреттің қай жері
/// мөлдір екенін бірден көреді.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final a = Paint()..color = const Color(0xFF2B3440);
    final b = Paint()..color = const Color(0xFF232B35);
    canvas.drawRect(Offset.zero & size, b);
    for (var y = 0; y < size.height / cell; y++) {
      for (var x = 0; x < size.width / cell; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(
              Rect.fromLTWH(x * cell, y * cell, cell, cell), a);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Кесу рамкасы: жиегі + үштен бір сызықтары (композицияны түзету үшін).
class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final d = size.width * i / 3;
      canvas.drawLine(Offset(d, 0), Offset(d, size.height), grid);
      canvas.drawLine(Offset(0, d), Offset(size.width, d), grid);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Gz.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
