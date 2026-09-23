// ignore_for_file: public_member_api_docs
// Internal bottom-bar motion; segmented controls retain their existing physics.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../types/glass_quality.dart';
import '../../../utils/glass_spring.dart';
import '../../../widgets/shared/glass_accessibility_scope.dart';
import '../indicator_deformation_scope.dart';

/// Coordinates position, shape recovery and material retirement for tab bars.
class TabIndicatorMotion extends StatefulWidget {
  const TabIndicatorMotion({
    required this.target,
    required this.pressed,
    required this.dragging,
    required this.visible,
    required this.itemCount,
    required this.quality,
    required this.builder,
    this.releaseSpring,
    super.key,
  });

  final double target;
  final bool pressed;
  final bool dragging;
  final bool visible;
  final int itemCount;
  final GlassQuality quality;
  final SpringDescription? releaseSpring;
  final Widget Function(BuildContext, double, double, double, Matrix4) builder;

  @override
  State<TabIndicatorMotion> createState() => _TabIndicatorMotionState();
}

class _TabIndicatorMotionState extends State<TabIndicatorMotion>
    with TickerProviderStateMixin {
  static final _interactive = GlassSpring.interactive();
  static final _released = GlassSpring.snappy(
    duration: const Duration(milliseconds: 350),
  );
  static final _material = GlassSpring.snappy(
    duration: const Duration(milliseconds: 300),
  );
  // Only the shape uses this spring. Position presets and selection stay intact.
  static final _shape = GlassSpring.bouncy(
    duration: const Duration(milliseconds: 280),
    extraBounce: 0.1,
  );

  late final SingleSpringController _position;
  late final SingleSpringController _deformation;
  late final SingleSpringController _thickness;
  late final Listenable _animation;
  bool _reduceMotion = false;
  bool _updating = false;
  double _shapeTarget = 0;
  double _materialTarget = 0;
  double _pixelsPerAlignment = 1;
  double _pixelsPerDeformation = 1;
  double? _lastDeformation;
  GlassQuality? _lastQuality;
  late Matrix4 _transform;

  SpringDescription get _positionSpring =>
      widget.dragging ? _interactive : widget.releaseSpring ?? _released;

  @override
  void initState() {
    super.initState();
    _position = SingleSpringController(
      vsync: this,
      spring: _positionSpring,
      initialValue: widget.target,
    );
    _deformation = SingleSpringController(vsync: this, spring: _shape);
    _thickness = SingleSpringController(vsync: this, spring: _material);
    _animation = Listenable.merge([_position, _deformation, _thickness]);
    _position.addListener(_updateMotion);
    _deformation.addListener(_updateMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = GlassAccessibilityData.of(context).reduceMotion;
    if (_reduceMotion) {
      _snap();
    } else {
      _updateMotion();
    }
  }

  @override
  void didUpdateWidget(TabIndicatorMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_reduceMotion) {
      _snap();
      return;
    }
    _position.spring = _positionSpring;
    if (widget.target != oldWidget.target) {
      _position.animateTo(widget.target);
    }
    _updateMotion();
  }

  void _snap() {
    _updating = true;
    _position.setValue(widget.target);
    _deformation.setValue(0);
    _thickness.setValue(0);
    _shapeTarget = 0;
    _materialTarget = 0;
    _updating = false;
  }

  void _updateMotion() {
    if (_updating || _reduceMotion) return;
    _updating = true;

    // Express rest tolerances in logical pixels, including velocity. Crossing
    // the target (or the neutral shape) alone must never retire the material.
    final positionSettled =
        (_position.value - widget.target).abs() * _pixelsPerAlignment < 0.1 &&
            _position.velocity.abs() * _pixelsPerAlignment < 1.0;
    if (positionSettled &&
        (_position.value != widget.target || _position.velocity != 0)) {
      _position.setValue(widget.target);
    }

    final shapeTarget = positionSettled || !widget.visible
        ? 0.0
        : (_position.velocity.abs() / 10).clamp(0.0, 1.0);
    if (shapeTarget != _shapeTarget) {
      _shapeTarget = shapeTarget;
      // Redirect from the current shape AND its velocity, including reversals.
      _deformation.animateTo(shapeTarget);
    }
    final shapeSettled = _shapeTarget == 0 &&
        _deformation.value.abs() * _pixelsPerDeformation < 0.1 &&
        _deformation.velocity.abs() * _pixelsPerDeformation < 1.0;
    if (shapeSettled &&
        (_deformation.value != 0 || _deformation.velocity != 0)) {
      _deformation.setValue(0);
    }

    // Begin retiring the active lens as the pill arrives, while its final
    // position and shape recovery are still moving. Waiting for exact rest
    // leaves a visible hold at the destination before the material changes.
    final visuallyArriving =
        (_position.value - widget.target).abs() * _pixelsPerAlignment < 2.0 &&
            _position.velocity.abs() * _pixelsPerAlignment < 30.0 &&
            _deformation.value.abs() < 0.1;
    final materialTarget = widget.visible &&
            (widget.pressed || widget.dragging || !visuallyArriving)
        ? 1.0
        : 0.0;
    if (_materialTarget != materialTarget) {
      _materialTarget = materialTarget;
      _thickness.animateTo(materialTarget);
    }
    _updating = false;
  }

  @override
  void dispose() {
    _position.removeListener(_updateMotion);
    _deformation.removeListener(_updateMotion);
    _position.dispose();
    _deformation.dispose();
    _thickness.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(0.0, constraints.maxWidth - 8);
          final tabWidth = width / widget.itemCount;
          _pixelsPerAlignment = math.max(1, (width - tabWidth) / 2);
          // Half the pill width × horizontal scale coefficient × quality cap.
          _pixelsPerDeformation = math.max(
            1,
            tabWidth *
                0.25 *
                IndicatorDeformationScope.maxDistortionFor(widget.quality),
          );
          return ListenableBuilder(
            listenable: _animation,
            builder: (context, _) {
              if (_lastDeformation != _deformation.value ||
                  _lastQuality != widget.quality) {
                _lastDeformation = _deformation.value;
                _lastQuality = widget.quality;
                _transform = IndicatorDeformationScope.transformFor(
                  _deformation.value,
                  widget.quality,
                );
              }
              return IndicatorDeformationScope(
                transform: _transform,
                child: widget.builder(
                  context,
                  _position.value,
                  _position.velocity,
                  _thickness.value,
                  _transform,
                ),
              );
            },
          );
        },
      );
}
