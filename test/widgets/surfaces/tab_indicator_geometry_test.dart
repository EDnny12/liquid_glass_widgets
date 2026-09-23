import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/widgets/shared/indicator_deformation_scope.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/shared/tab_bar_bottom_internal.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/shared/tab_bar_searchable_internal.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/shared/tab_indicator_motion.dart';

class _Harness {
  _Harness({required this.quality, required this.searchable});
  final GlassQuality quality;
  final bool searchable;
  int selected = 0;
  bool reject = false;
  bool platformView = false;
  TextDirection direction = TextDirection.ltr;
  MaskingQuality masking = MaskingQuality.high;
  final changes = <int>[];
  late StateSetter update;

  Widget build() => MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          void onChanged(int index) {
            changes.add(index);
            if (!reject) update(() => selected = index);
          }

          final tabs = List.generate(
              4,
              (i) => GlassTab(
                    label: 'Tab $i',
                    icon: const Icon(Icons.circle),
                  ));
          return Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(
                width: 400,
                height: 100,
                child: searchable
                    ? GlassTabBar.searchable(
                        tabs: tabs,
                        selectedIndex: selected,
                        onTabSelected: onChanged,
                        quality: quality,
                        maskingQuality: masking,
                        platformViewBackdrop: platformView,
                        indicatorExpansion:
                            const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 4),
                        searchConfig:
                            GlassSearchBarConfig(onSearchToggle: (_) {}),
                      )
                    : GlassTabBar.bottom(
                        tabs: tabs,
                        selectedIndex: selected,
                        onTabSelected: onChanged,
                        quality: quality,
                        maskingQuality: masking,
                        platformViewBackdrop: platformView,
                        indicatorExpansion:
                            const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 4),
                      ),
              ),
            ),
          );
        }),
      );
}

void _verifyGeometry(WidgetTester tester) {
  final scope = tester.widget<IndicatorDeformationScope>(
    find.byType(IndicatorDeformationScope),
  );
  final masks =
      find.byWidgetPredicate((w) => w is ClipPath && w.clipper is JellyClipper);
  expect(masks, findsNWidgets(2));
  final forward = masks.evaluate().firstWhere(
      (e) => !((e.widget as ClipPath).clipper! as JellyClipper).inverse);
  final clipper = (forward.widget as ClipPath).clipper! as JellyClipper;
  for (final element in masks.evaluate()) {
    final mask = (element.widget as ClipPath).clipper! as JellyClipper;
    expect(identical(mask.transform, scope.transform), isTrue);
  }
  final clipBox = forward.renderObject! as RenderBox;
  final maskPath = clipper
      .getClip(clipBox.size)
      .transform(clipBox.getTransformTo(null).storage);
  final maskBounds = maskPath.getBounds();

  for (final element in find.byType(AnimatedGlassIndicator).evaluate()) {
    final indicator = element.widget as AnimatedGlassIndicator;
    final transforms = find.descendant(
      of: find.byWidget(indicator),
      matching: find.byWidgetPredicate(
          (w) => w is Transform && identical(w.transform, scope.transform)),
    );
    expect(transforms, findsWidgets);
    // The final Transform is the shared lens/background body (the optional
    // resting frost has its own Transform using the same matrix).
    final render = tester.renderObject<RenderTransform>(transforms.last);
    final body = render.child!;
    final path = LiquidRoundedSuperellipse(
      borderRadius: indicator.borderRadius * 2,
    ).getOuterPath(Offset.zero & body.size);
    final worldPath = path.transform(body.getTransformTo(null).storage);
    final bounds = worldPath.getBounds();
    expect(bounds.left, closeTo(maskBounds.left, 0.001));
    expect(bounds.top, closeTo(maskBounds.top, 0.001));
    expect(bounds.right, closeTo(maskBounds.right, 0.001));
    expect(bounds.bottom, closeTo(maskBounds.bottom, 0.001));
    // Compare the silhouette near its corners as well as its bounding box.
    // A rounded rectangle and a superellipse can have identical bounds.
    for (final x in [.03, .08, .2, .5, .8, .92, .97]) {
      for (final y in [.03, .08, .2, .5, .8, .92, .97]) {
        final point = Offset(
          bounds.left + x * bounds.width,
          bounds.top + y * bounds.height,
        );
        if (maskPath.contains(point) != worldPath.contains(point)) {
          // Paths use float coordinates. A probe exactly on the contour may
          // round differently when translated before vs. after construction.
          // Both outlines must cross the same 0.01px neighborhood.
          const neighbors = [
            Offset(.01, 0),
            Offset(-.01, 0),
            Offset(0, .01),
            Offset(0, -.01),
          ];
          expect(neighbors.map((d) => maskPath.contains(point + d)).toSet(),
              {true, false});
          expect(neighbors.map((d) => worldPath.contains(point + d)).toSet(),
              {true, false});
        }
      }
    }
    expect(indicator.alignment, clipper.alignment);
    expect(indicator.thickness, clipper.thickness);
  }
}

void main() {
  for (final searchable in [false, true]) {
    for (final quality in GlassQuality.values) {
      for (final direction in TextDirection.values) {
        testWidgets(
            '$quality searchable=$searchable $direction shares geometry '
            'through travel, reverse and rest', (tester) async {
          final harness = _Harness(quality: quality, searchable: searchable)
            ..direction = direction;
          await tester.pumpWidget(harness.build());
          await tester.pumpAndSettle();
          _verifyGeometry(tester);
          harness.update(() => harness.selected = 3);
          await tester.pump();
          final backgroundFinder = find.byWidgetPredicate(
              (w) => w is RepaintBoundary && w.child is AdaptiveGlass);
          expect(backgroundFinder, findsOneWidget);
          final background = tester.widget(backgroundFinder);
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            _verifyGeometry(tester);
            expect(
                identical(tester.widget(backgroundFinder), background), isTrue,
                reason: 'motion must reuse the static background');
          }
          harness.update(() => harness.selected = 1);
          await tester.pump();
          for (var i = 0; i < 70; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            _verifyGeometry(tester);
          }
          await tester.pumpAndSettle();
          _verifyGeometry(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final platformView in [false, true]) {
      for (final masking in MaskingQuality.values) {
        testWidgets(
            'selection and rejected drag searchable=$searchable '
            'platformView=$platformView masking=$masking', (tester) async {
          final harness = _Harness(
            quality: GlassQuality.standard,
            searchable: searchable,
          )
            ..platformView = platformView
            ..masking = masking;
          await tester.pumpWidget(harness.build());
          await tester.pumpAndSettle();
          final bar =
              find.byType(searchable ? SearchableTabIndicator : TabIndicator);
          final rect = tester.getRect(bar);
          final first = Offset(rect.left + rect.width / 8, rect.center.dy);
          final last = Offset(rect.right - rect.width / 8, rect.center.dy);
          await tester.tapAt(last);
          await tester.pump();
          expect(harness.changes, [3],
              reason: 'selection must not await settling');
          expect(harness.selected, 3);
          await tester.pumpAndSettle();
          await tester.tapAt(last);
          await tester.pumpAndSettle();
          expect(harness.changes, [3, 3],
              reason: 'repeat tap callback preserved');

          harness.reject = true;
          await tester.tapAt(first);
          await tester.pumpAndSettle();
          expect(harness.changes, [3, 3, 0]);
          expect(harness.selected, 3);
          expect(
              tester
                  .widget<TabIndicatorMotion>(find.byType(TabIndicatorMotion))
                  .target,
              1);

          final drag = await tester.startGesture(last);
          await tester.pump();
          await drag.moveTo(first);
          await tester.pump(const Duration(milliseconds: 80));
          await drag.up();
          await tester.pumpAndSettle();
          expect(harness.selected, 3);
          final indicators = tester.widgetList<AnimatedGlassIndicator>(
            find.byType(AnimatedGlassIndicator),
          );
          for (final indicator in indicators) {
            expect(indicator.alignment.x, 1);
            expect(indicator.thickness, 0);
          }
          // Starting another press must not revive the last rejected drag.
          final repeat = await tester.startGesture(last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          for (final indicator in tester.widgetList<AnimatedGlassIndicator>(
            find.byType(AnimatedGlassIndicator),
          )) {
            expect(indicator.alignment.x, 1);
          }
          await repeat.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
        'cancelled drag searchable=$searchable reaches stable selection',
        (tester) async {
      final harness = _Harness(
        quality: GlassQuality.standard,
        searchable: searchable,
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      final bar =
          find.byType(searchable ? SearchableTabIndicator : TabIndicator);
      final rect = tester.getRect(bar);
      final start = Offset(rect.left + rect.width / 8, rect.center.dy);
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveBy(Offset(rect.width * .65, 0));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.cancel();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(harness.changes, hasLength(1));
      expect(harness.selected, harness.changes.single);
      for (final indicator in tester.widgetList<AnimatedGlassIndicator>(
        find.byType(AnimatedGlassIndicator),
      )) {
        expect(indicator.thickness, 0);
        expect(indicator.alignment.x,
            closeTo(-1 + 2 * harness.selected / 3, 1e-9));
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
