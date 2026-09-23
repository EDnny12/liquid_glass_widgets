import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/types/glass_quality.dart';
import 'package:liquid_glass_widgets/widgets/shared/indicator_deformation_scope.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/shared/tab_indicator_motion.dart';

class _Sample {
  _Sample(this.position, this.velocity, this.thickness, Matrix4 transform)
      : deformation = (1 - transform.entry(0, 0)) / 0.4;

  final double position;
  final double velocity;
  final double thickness;
  final double deformation;
}

class _Harness {
  double target = -1;
  bool pressed = false;
  bool dragging = false;
  bool visible = true;
  bool reduceMotion = false;
  bool tickersEnabled = true;
  SpringDescription? spring;
  late StateSetter update;
  late _Sample sample;
  int builds = 0;

  Widget build() => StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TickerMode(
              enabled: tickersEnabled,
              child: Center(
                child: SizedBox(
                  width: 400,
                  height: 64,
                  child: TabIndicatorMotion(
                    target: target,
                    pressed: pressed,
                    dragging: dragging,
                    visible: visible,
                    itemCount: 4,
                    quality: GlassQuality.premium,
                    releaseSpring: spring,
                    builder: (_, position, velocity, thickness, transform) {
                      builds++;
                      sample =
                          _Sample(position, velocity, thickness, transform);
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      });
}

void main() {
  test('distortion ceilings preserve premium and both lightweight paths', () {
    for (final quality in GlassQuality.values) {
      final cap = quality == GlassQuality.premium ? 0.8 : 0.35;
      expect(IndicatorDeformationScope.maxDistortionFor(quality), cap);
      final matrix = IndicatorDeformationScope.transformFor(10, quality);
      expect(matrix.entry(0, 0), 1 - cap * 0.5);
      expect(matrix.entry(1, 1), 1 + cap * 0.3);
      final recovery = IndicatorDeformationScope.transformFor(-10, quality);
      expect(recovery.entry(0, 0), 1 + cap * 0.5);
      expect(recovery.entry(1, 1), 1 - cap * 0.3);
      for (final value in [0.0, double.nan, double.infinity]) {
        final neutral = IndicatorDeformationScope.transformFor(value, quality);
        expect(neutral.entry(0, 0), 1);
        expect(neutral.entry(1, 1), 1);
      }
    }
  });

  for (final target in [-1 / 3, 1.0]) {
    for (final frameMs in [8, 16]) {
      testWidgets('travel to $target at ${frameMs}ms recovers then stops',
          (tester) async {
        final harness = _Harness();
        await tester.pumpWidget(harness.build());
        expect(tester.binding.transientCallbackCount, 0);
        harness.update(() => harness.target = target);
        await tester.pump();
        final samples = <_Sample>[];
        var elapsed = 0;
        while (tester.binding.hasScheduledFrame && elapsed < 2400) {
          await tester.pump(Duration(milliseconds: frameMs));
          elapsed += frameMs;
          samples.add(harness.sample);
        }
        expect(samples.any((s) => s.deformation > 0.01), isTrue);
        expect(samples.any((s) => s.deformation < -0.01), isTrue,
            reason: 'shape must recover through neutral, not only track speed');
        expect(
            samples.any((s) =>
                (s.position - target).abs() < 0.001 &&
                s.deformation.abs() > 0.001 &&
                s.thickness > 0.95),
            isTrue,
            reason: 'lens remains active during residual shape recovery');
        expect(harness.sample.position, target);
        expect(harness.sample.deformation, 0);
        expect(harness.sample.thickness, 0);
        expect(elapsed, lessThan(1400));
        expect(tester.binding.transientCallbackCount, 0);
        final builds = harness.builds;
        await tester.pump(const Duration(seconds: 1));
        expect(harness.builds, builds, reason: 'no additional work at rest');
      });
    }
  }

  testWidgets('rapid reverse preserves position, velocity and deformation',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    harness.update(() => harness.target = 1);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = harness.sample;
    harness.update(() => harness.target = -1);
    await tester.pump();
    expect(harness.sample.position, before.position);
    expect(harness.sample.velocity, closeTo(before.velocity, 1e-9));
    expect(harness.sample.deformation, before.deformation);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
        (harness.sample.deformation - before.deformation).abs(), lessThan(.2));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(harness.sample.position, -1);
    expect(harness.sample.deformation, 0);
    expect(harness.sample.thickness, 0);
  });

  testWidgets('crossing destination at speed does not retire the lens',
      (tester) async {
    final harness = _Harness()
      ..spring = SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 350),
        bounce: 0.5,
      );
    await tester.pumpWidget(harness.build());
    harness.update(() => harness.pressed = true);
    await tester.pumpAndSettle();
    harness.update(() {
      harness.pressed = false;
      harness.target = 1;
    });
    await tester.pump();
    var crossed = false;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final sample = harness.sample;
      if ((sample.position - 1).abs() < .05 && sample.velocity.abs() > .3) {
        crossed = true;
        expect(sample.thickness, greaterThan(.95));
      }
    }
    expect(crossed, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('press and dragging over selected tab keep the lens active',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    harness.update(() => harness.pressed = true);
    await tester.pumpAndSettle();
    expect(harness.sample.thickness, 1);
    harness.update(() {
      harness.pressed = false;
      harness.dragging = true;
    });
    await tester.pumpAndSettle();
    expect(harness.sample.thickness, 1);
    harness.update(() => harness.dragging = false);
    await tester.pumpAndSettle();
    expect(harness.sample.thickness, 0);
  });

  testWidgets('Reduce Motion snaps an active animation and future changes',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    harness.update(() => harness.target = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    harness.update(() => harness.reduceMotion = true);
    await tester.pump();
    expect(harness.sample.position, 1);
    expect(harness.sample.deformation, 0);
    expect(harness.sample.thickness, 0);
    expect(tester.binding.transientCallbackCount, 0);
    harness.update(() => harness.target = -1 / 3);
    await tester.pump();
    expect(harness.sample.position, -1 / 3);
    expect(tester.binding.transientCallbackCount, 0);
    harness.update(() => harness.reduceMotion = false);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('TickerMode mutes work and animation settles after resuming',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    harness.update(() => harness.target = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    harness.update(() => harness.tickersEnabled = false);
    await tester.pump();
    final builds = harness.builds;
    await tester.pump(const Duration(seconds: 1));
    expect(harness.builds, builds);
    expect(tester.binding.transientCallbackCount, 0);
    harness.update(() => harness.tickersEnabled = true);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(harness.sample.position, 1);
    expect(harness.sample.deformation, 0);
    expect(harness.sample.thickness, 0);
  });

  testWidgets('hidden material retires and disposal cancels all tickers',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    harness.update(() {
      harness.target = 1;
      harness.pressed = true;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    harness.update(() => harness.visible = false);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(harness.sample.thickness, 0);
    harness.update(() {
      harness.visible = true;
      harness.target = -1;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden indicator does not drive shape recovery', (tester) async {
    final harness = _Harness()..visible = false;
    await tester.pumpWidget(harness.build());
    harness.update(() => harness.target = 1);
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(harness.sample.deformation, 0);
      expect(harness.sample.thickness, 0);
    }
    expect(harness.sample.position, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
