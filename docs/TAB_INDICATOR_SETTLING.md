# Bottom tab indicator elastic settling

## Baseline and scope

- Upstream baseline: `4d3f4dfe4e6188a82c200b1e3a4a2645ccb54d12`, package `1.7.2`.
- Verified with Flutter `3.47.5` / Dart `3.13.4` on macOS.
- Scope: the shared indicator in `GlassTabBar.bottom`,
  `GlassTabBar.searchable`, and `GlassTabBar.minimizable`. No changes to the package version, dependencies,
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
   produced different widths and transform centers. Some mask call sites also
   doubled the radius, unlike the indicator's current rounded rectangle.
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
0.4. It stretches horizontally during travel and contracts as it arrives.
When demand disappears, shape recovers without timers. These values are
package-specific tuning, not constants published by Apple.

Redirects preserve position, velocity, deformation, and deformation velocity.
Rest requires both small distance and low velocity: below 0.1 px and 1 px/s,
converted into the control's coordinate space. Both deformation value and
velocity are also checked, so crossing zero is not mistaken for rest. Values
then snap exactly to rest. The active material starts retiring as the position
arrives (within 2 px at under 30 px/s, with under 0.1 shape deformation),
overlapping the final movement. Waiting for exact rest left a visible pause at
the destination. Presses, drags, and fast crossings keep the material active.

`IndicatorDeformationScope`, internal and unexported, supplies a single effective
matrix to the lens and background; the same instance reaches both `JellyClipper`
objects. The matrix is retained while shape and quality remain unchanged. Each
representation applies it once around its expanded center. Masks use the same
rounded rectangle and radius as the indicator, while preserving the upstream
overdrag guard that keeps edge icons visible. The background and
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

Final local results: **2,889 tests passed, including 36 regression tests for
this change**. Static analysis reported no issues. Effective line coverage is
**94.38%** (11,713/12,411 lines, excluding engine/renderer as CI does).
Formatting and `git diff --check` against the upstream baseline passed.
`dart doc --dry-run` reported no errors and nine unresolved-reference warnings
in unchanged upstream files. Coverage does not establish visual
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
- Version 1.7.2 custom indicator radii and independent background quality.

In the deterministic test of a 400 × 64 px bar with four tabs, the complete
animation until all tickers stop takes approximately 0.81 s for an adjacent tab
and 0.85 s from the first to the last tab. Samples were taken every 8 and 16 ms.
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
renderer tests. Effective coverage excludes `lib/src/engine/*` and `lib/src/renderer/*`, as CI does;
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
