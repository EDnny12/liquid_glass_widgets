// Internal geometry shared by the bottom-bar lens, resting pill and masks.
// Not exported from liquid_glass_widgets.dart.
import 'package:flutter/widgets.dart';

import '../../types/glass_quality.dart';

/// The effective deformation for one bottom-bar animation update.
class IndicatorDeformationScope extends InheritedWidget {
  const IndicatorDeformationScope({
    required this.transform,
    required super.child,
    super.key,
  });

  /// The matrix applied once around the expanded indicator's center.
  final Matrix4 transform;

  /// Returns the shared transform, or `null` for other indicator consumers.
  static Matrix4? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<IndicatorDeformationScope>()
      ?.transform;

  /// Resolves the existing distortion ceiling for the rendering path.
  static double maxDistortionFor(GlassQuality quality) =>
      quality == GlassQuality.premium ? 0.8 : 0.35;

  /// Builds a bounded horizontal squash with a small signed recovery.
  static Matrix4 transformFor(double deformation, GlassQuality quality) {
    final amount = (deformation.isFinite ? deformation : 0.0).clamp(-1.0, 1.0) *
        maxDistortionFor(quality);
    if (amount == 0) {
      // Keep the transform layer mounted, as in buildJellyTransform.
      return Matrix4.translationValues(0.0001, 0, 0);
    }
    return Matrix4.diagonal3Values(1 - amount * 0.5, 1 + amount * 0.3, 1);
  }

  @override
  bool updateShouldNotify(IndicatorDeformationScope oldWidget) =>
      transform != oldWidget.transform;
}
