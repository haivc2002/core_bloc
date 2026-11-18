import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef _TouchEffect = ({
  Offset globalPoint,
  Offset pull,
  double scale,
  double glow,
  double release,
});

const _rest = (
  globalPoint: Offset.zero,
  pull: Offset.zero,
  scale: 1.0,
  glow: 0.0,
  release: 1.0,
);
const _pullLimit = 100.0;

Matrix4 _panelTransform(_TouchEffect effect) {
  // Scale each screen axis independently so diagonal pulls do not shear.
  final stretchX = effect.pull.dx.abs() / _pullLimit * 0.035;
  final stretchY = effect.pull.dy.abs() / _pullLimit * 0.035;
  return Matrix4.identity()
    ..setEntry(0, 0, effect.scale + stretchX)
    ..setEntry(1, 1, effect.scale + stretchY)
    ..setEntry(0, 3, effect.pull.dx * 0.075)
    ..setEntry(1, 3, effect.pull.dy * 0.075);
}

/// Adds elastic pull and touch lighting to a rounded surface.
class TouchReactiveSurface extends StatefulWidget {
  const TouchReactiveSurface({
    super.key,
    this.color,
    required this.borderRadius,
    required this.child,
    this.glowOpacity,
    this.rimOpacity,
  }) : assert(glowOpacity == null || (glowOpacity >= 0 && glowOpacity <= 1)),
       assert(rimOpacity == null || (rimOpacity >= 0 && rimOpacity <= 1));

  /// Surface fill. Defaults to a neutral shade that makes the light visible.
  final Color? color;
  final BorderRadius borderRadius;
  final Widget child;

  /// Peak opacity of the halo and ripple. Defaults to a theme-specific value.
  final double? glowOpacity;

  /// Peak opacity of the rim light. Defaults to a theme-specific value.
  final double? rimOpacity;

  @override
  State<TouchReactiveSurface> createState() => _TouchReactiveSurfaceState();
}

class _TouchReactiveSurfaceState extends State<TouchReactiveSurface>
    with SingleTickerProviderStateMixin {
  static const _releaseDuration = 0.73;
  static const _tapPulseDuration = 0.26;

  final _effect = ValueNotifier<_TouchEffect>(_rest);
  late final Ticker _ticker;
  ui.FragmentShader? _shader;
  Duration _lastTick = Duration.zero;

  int? _activePointer;
  Offset _touchOrigin = Offset.zero;
  Offset _initialPull = Offset.zero;
  Offset _targetPull = Offset.zero;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    unawaited(_loadLighting());
  }

  Future<void> _loadLighting() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'packages/core_bloc/shaders/touch_surface_light.frag',
      );
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } on Exception {
      // The Canvas gradients also work while the shader is unavailable.
    }
  }

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onDown(PointerDownEvent event) {
    if (_activePointer != null || (event.buttons & kPrimaryButton) == 0) return;
    _activePointer = event.pointer;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _touchOrigin = event.localPosition;
    _initialPull = _effect.value.pull;
    _onMove(event);
  }

  void _onMove(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    final current = _effect.value;
    final drag = event.localPosition - _touchOrigin;
    final pull = _initialPull + drag * (_pullLimit / (145 + drag.distance));
    final distance = pull.distance;
    _targetPull = distance > _pullLimit ? pull * (_pullLimit / distance) : pull;
    _effect.value = (
      globalPoint: event.position,
      pull: _reduceMotion ? Offset.zero : current.pull,
      scale: _reduceMotion ? 1.0 : current.scale,
      glow: 1.0,
      release: 1.0,
    );
    if (!_reduceMotion) _startTicker();
  }

  void _release(PointerEvent event, {required bool ripple}) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _targetPull = Offset.zero;
    if (_reduceMotion) {
      _effect.value = _rest;
      return;
    }

    final current = _effect.value;
    _effect.value = (
      globalPoint: ripple ? event.position : current.globalPoint,
      pull: current.pull,
      scale: current.scale,
      glow: current.glow,
      release: ripple ? 0.0 : 1.0,
    );
    _startTicker();
  }

  void _tick(Duration elapsed) {
    final delta = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    final current = _effect.value;
    final touching = _activePointer != null;
    final response = 1 - math.exp(-delta / (touching ? 0.087 : 0.115));
    final pullResponse = touching ? 1 - math.exp(-delta / 0.24) : response;
    final release = math.min(1.0, current.release + delta / _releaseDuration);
    final tapProgress = (release * _releaseDuration / _tapPulseDuration).clamp(
      0.0,
      1.0,
    );
    final tapPulse = 0.012 * math.sin(math.pi * tapProgress);
    final targetScale = touching ? 1.015 : 1.0 + tapPulse;

    var pull = Offset.lerp(current.pull, _targetPull, pullResponse)!;
    var scale = ui.lerpDouble(current.scale, targetScale, response)!;
    var glow = touching ? 1.0 : current.glow * math.exp(-delta / 0.12);

    if ((pull - _targetPull).distance < 0.08) pull = _targetPull;
    if ((scale - targetScale).abs() < 0.0003) scale = targetScale;
    if (glow < 0.003) glow = 0.0;

    _effect.value = (
      globalPoint: current.globalPoint,
      pull: pull,
      scale: scale,
      glow: glow,
      release: release,
    );

    if (pull == _targetPull &&
        scale == targetScale &&
        (touching || (glow == 0 && release == 1))) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    // Flutter can still dispatch events for a pointer that was already down.
    _activePointer = null;
    _ticker.dispose();
    _shader?.dispose();
    _effect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color =
        widget.color ??
        (dark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8)).withValues(
          alpha: 0.97,
        );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (event) => _release(event, ripple: true),
      onPointerCancel: (event) => _release(event, ripple: false),
      child: ValueListenableBuilder<_TouchEffect>(
        valueListenable: _effect,
        builder: (_, effect, child) => Transform(
          alignment: Alignment.center,
          transform: _panelTransform(effect),
          child: child,
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: ColoredBox(
            color: color,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: Builder(
                        builder: (paintContext) => CustomPaint(
                          painter: _TouchLighting(
                            _effect,
                            _shader,
                            paintContext: paintContext,
                            borderRadius: widget.borderRadius,
                            strength:
                                widget.glowOpacity ?? (dark ? 0.075 : 0.93),
                            rimStrength:
                                widget.rimOpacity ?? (dark ? 0.14 : 1.0),
                          ),
                          willChange: true,
                        ),
                      ),
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: Material(
                    type: MaterialType.transparency,
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TouchLighting extends CustomPainter {
  _TouchLighting(
    this.effect,
    this.shader, {
    required this.paintContext,
    required this.borderRadius,
    required this.strength,
    required this.rimStrength,
  }) : super(repaint: effect);

  static final _waveStops = List<double>.generate(
    13,
    (index) => index / 12,
    growable: false,
  );

  final ValueNotifier<_TouchEffect> effect;
  final ui.FragmentShader? shader;
  final BuildContext paintContext;
  final BorderRadius borderRadius;
  final double strength;
  final double rimStrength;
  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = effect.value;
    if ((frame.glow == 0 && frame.release == 1) || size.isEmpty) return;

    final center = size.center(Offset.zero);
    // Use the current transform so a sliding or stretched panel tracks the touch.
    final paintBox = paintContext.findRenderObject()! as RenderBox;
    final contact = paintBox.globalToLocal(frame.globalPoint) - center;
    // Project an outside contact back onto the panel so both lights stay visible.
    final extent = math.max(
      1.0,
      math.max(contact.dx.abs() / center.dx, contact.dy.abs() / center.dy),
    );
    final point = center + contact / extent;
    final radius = math.max(122.0, size.longestSide * 0.58);

    final lighting = shader;
    final bounds = Offset.zero & size;
    if (lighting != null) {
      lighting
        ..setFloat(0, point.dx)
        ..setFloat(1, point.dy)
        ..setFloat(2, radius)
        ..setFloat(3, frame.glow)
        ..setFloat(4, frame.release)
        ..setFloat(5, strength)
        ..setFloat(6, size.width)
        ..setFloat(7, size.height)
        ..setFloat(8, borderRadius.topLeft.x)
        ..setFloat(9, borderRadius.topRight.x)
        ..setFloat(10, borderRadius.bottomLeft.x)
        ..setFloat(11, borderRadius.bottomRight.x)
        ..setFloat(12, rimStrength);
      canvas.drawRect(bounds, _paint..shader = lighting);
      return;
    }

    if (frame.glow > 0) {
      final alpha = strength * frame.glow;
      _paint.shader = ui.Gradient.radial(
        point,
        radius * 1.6,
        [
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: alpha * 0.48),
          Colors.white.withValues(alpha: alpha * 0.09),
          const Color(0x00FFFFFF),
        ],
        const [0.0, 0.34, 0.68, 1.0],
      );
      canvas.drawCircle(point, radius * 1.6, _paint);
      if (!bounds.deflate(52).contains(point)) {
        const rimWidth = 1.5;
        final rimAlpha = frame.glow * rimStrength;
        final highlight = Colors.white.withValues(alpha: rimAlpha);
        _paint
          ..shader = ui.Gradient.radial(
            point,
            160,
            [
              highlight,
              highlight,
              Colors.white.withValues(alpha: 0.81 * rimAlpha),
              Colors.white.withValues(alpha: 0.42 * rimAlpha),
              Colors.white.withValues(alpha: 0.10 * rimAlpha),
              const Color(0x00FFFFFF),
            ],
            const [0.0, 0.375, 0.55, 0.72, 0.88, 1.0],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimWidth;
        canvas.drawRRect(
          borderRadius.toRRect(bounds).deflate(rimWidth / 2),
          _paint,
        );
        _paint.style = PaintingStyle.fill;
      }
    }
    final age = frame.release;
    if (age > 0 && age < 1) {
      final crest = radius * (0.08 + 1.85 * age);
      final width = radius * (0.54 + 0.48 * age);
      final outer = crest + width * 2.5;
      final peak = strength * 0.65 * math.min(age * 10, 1.0) * (1 - age);
      final colors = [
        for (var sample = 0; sample < 12; sample++)
          Colors.white.withValues(
            alpha:
                peak *
                math.pow(
                  2,
                  -1.65 * math.pow((outer * sample / 12 - crest) / width, 2),
                ),
          ),
        const Color(0x00FFFFFF),
      ];
      _paint.shader = ui.Gradient.radial(point, outer, colors, _waveStops);
      canvas.drawCircle(point, outer, _paint);
    }
  }

  @override
  bool shouldRepaint(_TouchLighting oldDelegate) =>
      strength != oldDelegate.strength ||
      rimStrength != oldDelegate.rimStrength ||
      borderRadius != oldDelegate.borderRadius ||
      shader != oldDelegate.shader ||
      effect != oldDelegate.effect;
}
