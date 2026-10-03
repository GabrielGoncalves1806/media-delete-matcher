import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

enum SwipeDirection { delete, keep, compress }

/// Carta arrastável: ← apaga, → mantém e, se [canCompress], ↑ comprime.
///
/// Os botões da tela disparam o mesmo movimento via [SwipeCardState.swipe],
/// usando uma GlobalKey.
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.child,
    required this.onSwiped,
    this.canCompress = false,
  });

  final Widget child;
  final ValueChanged<SwipeDirection> onSwiped;
  final bool canCompress;

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

  /// Direção que já passou do ponto de decisão no arrasto atual
  /// (pra vibrar uma vez só a cada vez que cruza).
  SwipeDirection? _armed;

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  double get _width => context.size?.width ?? 360;
  double get _height => context.size?.height ?? 600;
  double get _sideThreshold => _width * 0.28;
  double get _upThreshold => _height * 0.18;

  /// Animação de saída disparada por botão ou por gesto.
  Future<void> swipe(SwipeDirection direction) async {
    if (_leaving) return;
    if (direction == SwipeDirection.compress && !widget.canCompress) return;
    _leaving = true;
    direction == SwipeDirection.delete ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    final target = switch (direction) {
      SwipeDirection.delete => Offset(-_width * 1.5, _offset.dy + 40),
      SwipeDirection.keep => Offset(_width * 1.5, _offset.dy + 40),
      SwipeDirection.compress => Offset(_offset.dx, -_height * 1.3),
    };
    await _animateTo(target);
    if (mounted) widget.onSwiped(direction);
  }

  Future<void> _animateTo(Offset target) {
    _tween = Tween(begin: _offset, end: target);
    return _anim.forward(from: 0);
  }

  /// Pra onde o arrasto atual decidiria, se soltasse agora.
  SwipeDirection? get _pointing {
    final up = widget.canCompress && -_offset.dy > _upThreshold && -_offset.dy > _offset.dx.abs();
    if (up) return SwipeDirection.compress;
    if (_offset.dx.abs() > _sideThreshold) {
      return _offset.dx < 0 ? SwipeDirection.delete : SwipeDirection.keep;
    }
    return null;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_leaving) return;
    // Pra cima anda livre quando dá pra comprimir; senão o vertical é amortecido.
    final dy = widget.canCompress && _offset.dy + d.delta.dy < 0 ? d.delta.dy : d.delta.dy * 0.3;
    setState(() => _offset += Offset(d.delta.dx, dy));
    final pointing = _pointing;
    if (pointing != null && pointing != _armed) HapticFeedback.selectionClick();
    _armed = pointing;
  }

  void _onPanEnd(DragEndDetails d) {
    _armed = null;
    if (_leaving) return;
    final v = d.velocity.pixelsPerSecond;
    final pointing = _pointing ??
        (widget.canCompress && v.dy < -900 && v.dy.abs() > v.dx.abs()
            ? SwipeDirection.compress
            : v.dx.abs() > 900
                ? (v.dx < 0 ? SwipeDirection.delete : SwipeDirection.keep)
                : null);
    pointing == null ? _animateTo(Offset.zero) : swipe(pointing);
  }

  @override
  Widget build(BuildContext context) {
    final side = (_offset.dx / _sideThreshold).clamp(-1.0, 1.0);
    final up = widget.canCompress ? (-_offset.dy / _upThreshold).clamp(0.0, 1.0) : 0.0;
    // O carimbo de cima só aparece se o movimento for mais vertical que lateral.
    final upOpacity = -_offset.dy > _offset.dx.abs() ? up : 0.0;
    final sideOpacity = upOpacity > 0 ? 0.0 : 1.0;
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
                  opacity: math.max(0, -side) * sideOpacity,
                ),
              ),
              Positioned(
                top: 56,
                left: 18,
                child: _Stamp(
                  label: 'MANTER',
                  color: AppColors.keep,
                  angle: -0.2,
                  opacity: math.max(0, side) * sideOpacity,
                ),
              ),
              Positioned(
                bottom: 90,
                left: 0,
                right: 0,
                child: Center(
                  child: _Stamp(
                    label: 'COMPRIMIR',
                    color: AppColors.accent,
                    angle: 0,
                    opacity: upOpacity,
                  ),
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
