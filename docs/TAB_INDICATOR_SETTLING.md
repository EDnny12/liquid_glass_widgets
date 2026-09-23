# Bottom tab indicator elastic settling

## Baseline and scope

- Local baseline: `3ef22e55a2bc0857eaabfc39a2101847330ff249`, package `0.21.1`.
- Verified with Flutter `3.47.5` / Dart `3.13.4` on macOS.
- Scope: `GlassBottomBar`, `GlassSearchableBottomBar`, and the corresponding
  `GlassTabBar` variants. No changes to the package version, dependencies,
  global optics, shaders, global spring presets, or public parameters.
- No devices or emulators were run for this validation.

## Confirmed findings

1. Material retirement depended on an alignment distance `> 0.05`, without
   considering velocity or residual deformation. It could start while the
   indicator was still arriving or crossing its destination at speed.
2. Deformation was an instantaneous function of velocity magnitude. It
   disappeared when movement stopped, with no inertia of its own or recovery
   through the neutral shape. Synchronizing the material alone cannot address
   that limitation.
3. Masks used `maxDistortion: 0.8` for `standard` and `minimal` quality, while
   the lens capped both at `0.35`. Masking quality and material rendering
   quality are separate decisions.
4. The mask divided the width into tabs before applying 4 px padding. The
   indicator applies padding to the entire bar before dividing it. This
   produced different widths and transform centers. The mask also used a
   rounded rectangle instead of the indicator's superellipse.
5. The premium background remained outside the transform. It could reappear
   rigid during material retirement.
6. After a rejected drag or hybrid tap, the visual destination could differ
   from the application's committed index. On release, the visual destination
   now follows the committed selection without emitting additional callbacks.

## Implementation decisions

`TabIndicatorMotion` coordinates the two existing springs (position and material)
and adds one scalar shape state with its velocity using `SingleSpringController`.
Position retains the previous presets and custom spring support. Shape follows
a bounded demand derived from velocity, using a local 280 ms spring with bounce
0.4. When demand disappears, shape recovers without timers. These values are
package-specific tuning, not constants published by Apple.

Redirects preserve position, velocity, deformation, and deformation velocity.
Rest requires both small distance and low velocity: below 0.1 px and 1 px/s,
converted into the control's coordinate space. Both deformation value and
velocity are also checked, so crossing zero is not mistaken for rest. Values
then snap exactly to rest and the material retires.

`IndicatorDeformationScope`, internal and unexported, supplies a single effective
matrix to the lens and background; the same instance reaches both `JellyClipper`
objects. The matrix is retained while shape and quality remain unchanged. Each
representation applies it once around its expanded center. The background and
its existing blur follow the transform; no additional blur is introduced.
Consumers outside the bottom bars retain their previous behavior.

Animation rebuilds the existing indicator subtree. Content widgets received
from the parent are reused, and the outer bar does not call `setState` on each
tick. The background widget instance is retained between frames, with a test
checking its identity. A hidden indicator does not drive the new shape spring.
No captures, CPU readbacks, shaders, or `saveLayer` calls were added. Existing
masks and backdrop updates remain in place. Tickers stop at rest, respect
`TickerMode`, are disposed on unmount, and stop when Reduce Motion is enabled,
including during an active animation.

## Official references and their application

- [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/):
  touch response, flexibility, and coherence between motion and material inform
  the continuous transition, without assuming equivalence to the native engine.
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion):
  purposeful motion, restrained amplitude, and accessibility preferences.
- [Apple: What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/):
  Liquid Glass appearance continues to evolve and adapts in system components.
  The session does not specify the internal physics of the tab indicator.
- [Flutter: Performance best practices](https://docs.flutter.dev/perf/best-practices):
  limit rebuild work and avoid unnecessary rendering layers and costs.
- [Flutter: AnimatedBuilder](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html):
  reuse children that do not change with animation; notifications are confined
  to the subtree that depends on motion.
- [Flutter: Rendering performance](https://docs.flutter.dev/perf/rendering-performance):
  conclusions about UI/raster timings require measurements in `profile` mode.

## Reproducible validation

Final local results: static analysis reported no issues; **2,125 tests passed,
including 34 new tests**. Effective coverage: **91.37%** (8,458/9,257 lines,
excluding the renderer as CI does). Both new internal files have 100% line
coverage. `git diff --check` also passed. Coverage does not establish visual
correctness or measured rendering performance.

The new tests inspect intermediate frames, not just `pumpAndSettle`:

- Adjacent and distant transitions, reversals, destination crossings at speed,
  and shape recovery when position is already close to the destination.
- Identical effective matrices and matching screen-space geometry for the
  lens, background, and masks: premium, standard, and minimal; LTR/RTL with
  asymmetric expansion.
- Immediate callbacks, repeat taps, and rejected selections with/without masks
  and with the gesture mode used for PlatformViews.
- Unmounting, hiding, `TickerMode`, Reduce Motion enabled during animation,
  and no additional rebuilds at rest.

In the deterministic test of a 400 × 64 px bar with four tabs, the complete
animation until all tickers stop takes approximately 1.07 s for an adjacent tab
and 1.22 s from the first to the last tab. Samples were taken every 8 and 16 ms.
These durations include the numerical tail and material retirement; they are
not CPU/GPU timings or measurements of device frame performance. Peak recovery
beyond the neutral shape is approximately 0.7% and 1.9% of horizontal scale in
premium, respectively. Standard quality retains its lower distortion limit.

```sh
flutter analyze --fatal-warnings
flutter test test/widgets/surfaces/tab_indicator_motion_test.dart \
  test/widgets/surfaces/tab_indicator_geometry_test.dart
flutter test --coverage $(rg --files test -g '*_test.dart' \
  -g '!**/golden/**' -g '!**/renderer/**')
```

The last command selects the same files as CI: it excludes goldens and GPU
renderer tests. Effective coverage excludes `lib/src/renderer/*`, as CI does;
it does not imply validation of pixels rendered by Impeller.

## Device comparison still required

Reuse `example/lib/demos/indicator_parity_demo.dart`: it already includes four
tabs, premium/standard bars, and a searchable bar. No additional application
was created, and the scene's optical settings were not changed.

1. Run the same scene from the baseline commit and this implementation, using
   the same SDK, device, orientation, quality, and tuning-panel settings.
2. From `example/`, run
   `flutter run --profile -t lib/demos/indicator_parity_demo.dart`.
3. Record on iOS and Android: 0→1, 0→3, rapid changes, reversals, slow drags,
   overdrag, and cancellation. Repeat with search, a tap on the active tab,
   and Reduce Motion. For PlatformViews, also use the existing maps demo.
4. In DevTools, compare UI/raster timings (median and percentiles), frames over
   the device's frame budget, complete duration, and total animation work. A
   longer tail can consume more total work even if every frame remains smooth.
   Separate warmup from measured repetitions.
5. Record both versions at the same frame rate and compare arrival, recovery,
   material retirement, selection, and backdrop content updates.

No devices, emulators, or comparable native reference were run. Visual parity
with Apple and the absence of a measurable UI/raster regression remain pending
this comparison. Code review and local tests verify geometry, behavior,
lifecycle, and containment of the added animation work.
