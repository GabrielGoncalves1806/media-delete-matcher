import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

enum SwipeDirection { delete, keep }

/// Carta arrastável: ← apaga, → mantém.
///
/// Os botões da tela disparam o mesmo movimento via [SwipeCardState.swipe],
/// usando uma GlobalKey.
class SwipeCard extends StatefulWidget {
  const SwipeCard({super.key, required this.child, required this.onSwiped});

  final Widget child;
  final ValueChanged<SwipeDirection> onSwiped;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 230),
  )..addListener(() => setState(() => _offset = _tween.evaluate(_curve)));
  late final CurvedAnimation _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOut);

  Tween<Offset> _tween = Tween(begin: Offset.zero, end: Offset.zero);
  Offset _offset = Offset.zero;
  bool _leaving = false;

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  double get _width => context.size?.width ?? 360;

  /// Animação de saída disparada por botão ou por gesto.
  Future<void> swipe(SwipeDirection direction) async {
    if (_leaving) return;
    _leaving = true;
    final sign = direction == SwipeDirection.delete ? -1 : 1;
    await _animateTo(Offset(sign * _width * 1.5, _offset.dy + 40));
    if (mounted) widget.onSwiped(direction);
  }

  Future<void> _animateTo(Offset target) {
    _tween = Tween(begin: _offset, end: target);
    return _anim.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_leaving) return;
    setState(() => _offset += Offset(d.delta.dx, d.delta.dy * 0.3));
  }

  void _onPanEnd(DragEndDetails d) {
    if (_leaving) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    final passed = _offset.dx.abs() > _width * 0.28 || vx.abs() > 900;
    if (passed) {
      final goingLeft = _offset.dx.abs() > _width * 0.28 ? _offset.dx < 0 : vx < 0;
      swipe(goingLeft ? SwipeDirection.delete : SwipeDirection.keep);
    } else {
      _animateTo(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_offset.dx / (_width * 0.28)).clamp(-1.0, 1.0);
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _offset,
        child: Transform.rotate(
          angle: _offset.dx / _width * (math.pi / 10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              Positioned(
                top: 56,
                right: 18,
                child: _Stamp(
                  label: 'APAGAR',
                  color: AppColors.delete,
                  angle: 0.2,
                  opacity: math.max(0, -progress),
                ),
              ),
              Positioned(
                top: 56,
                left: 18,
                child: _Stamp(
                  label: 'MANTER',
                  color: AppColors.keep,
                  angle: -0.2,
                  opacity: math.max(0, progress),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.angle,
    required this.opacity,
  });

  final String label;
  final Color color;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.toDouble(),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
