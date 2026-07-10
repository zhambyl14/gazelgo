import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Жеңіл анти-бот тексеруі: пазл бөлшегін белгіленген ойыққа дейін
/// жылжытады (slide-to-verify).
///
/// ЕСКЕРТУ: бұл тек клиент жағындағы кедергі — сервер (edge function)
/// тексермейді, API-ды тікелей шақыратын скриптен қорғамайды. Мақсаты —
/// қосымша UI арқылы жаппай автоматты тіркеуді сәл қиындату, толық 2FA
/// емес.
class PuzzleCaptcha extends StatefulWidget {
  final ValueChanged<bool> onChanged;
  const PuzzleCaptcha({super.key, required this.onChanged});

  @override
  State<PuzzleCaptcha> createState() => _PuzzleCaptchaState();
}

class _PuzzleCaptchaState extends State<PuzzleCaptcha> {
  static const _trackHeight = 60.0;
  static const _pieceSize = 52.0;
  static const _slotSize = 34.0;
  static const _tolerance = 12.0;

  double _x = 0;
  double _targetFrac = 0.6;
  bool _dragging = false;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _randomizeTarget();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(false));
  }

  void _randomizeTarget() {
    _targetFrac = 0.45 + Random().nextDouble() * 0.4; // 0.45..0.85
  }

  void _reset() {
    setState(() {
      _x = 0;
      _verified = false;
      _randomizeTarget();
    });
    widget.onChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxX = constraints.maxWidth - _pieceSize;
      final targetX = _targetFrac * maxX;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _verified ? 'Тексерілді' : 'Пазлды белгіленген ойыққа жылжытыңыз',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _verified ? Gz.green : Gz.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: _trackHeight,
            clipBehavior: Clip.none,
            decoration: BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Gz.border, width: 1.4),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: targetX + (_pieceSize - _slotSize) / 2,
                  top: (_trackHeight - _slotSize) / 2,
                  child: Container(
                    width: _slotSize,
                    height: _slotSize,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Gz.textSecondary.withValues(alpha: 0.4),
                          width: 1.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  left: _x,
                  top: (_trackHeight - _pieceSize) / 2,
                  child: GestureDetector(
                    onHorizontalDragStart:
                        _verified ? null : (_) => setState(() => _dragging = true),
                    onHorizontalDragUpdate: _verified
                        ? null
                        : (d) => setState(
                            () => _x = (_x + d.delta.dx).clamp(0, maxX)),
                    onHorizontalDragEnd: _verified
                        ? null
                        : (_) {
                            final ok = (_x - targetX).abs() <= _tolerance;
                            setState(() {
                              _dragging = false;
                              _x = ok ? targetX : 0;
                              _verified = ok;
                              if (!ok) _randomizeTarget();
                            });
                            widget.onChanged(ok);
                          },
                    child: Container(
                      width: _pieceSize,
                      height: _pieceSize,
                      decoration: BoxDecoration(
                        color: _verified ? Gz.green : Gz.yellow,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (_verified ? Gz.green : Gz.yellow)
                                .withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _verified ? Icons.check_rounded : Icons.extension,
                        color: _verified ? Colors.white : Gz.ink,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_verified)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                onPressed: _reset,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Қайта тексеру',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ),
        ],
      );
    });
  }
}
