# Contract: renderer / Duo ↔ UI (L3c ↔ L3b)

> **DEMO ONLY.** This contract is owned by the Commander. To change it, add a line to "Changes" and tell the Commander. Don't edit it silently.

L3c (render + Duo, Bitrig account B) provides these names. L3b (UI, Bitrig account A) consumes them. Both lanes build on `App/Core` (`CaseBundle`, `CaseLayer`, `CaseFinding`, `CutPlane`, `HingeMapping`, `HingeSmoother`, `HingeAngleSource`) and must not modify it.

## Provided by L3c, in `App/Render/` and `App/Duo/`

```swift
enum SliceMode { case layers, ct }          // "what patients see" / "what doctors see"

struct SliceView: View {                      // App/Render/SliceView.swift
  init(bundle: CaseBundle,
       cut: CutPlane,
       mode: SliceMode,
       visibleLayerIDs: Set<Int>,
       selectedFinding: CaseFinding?,
       window: [Double])                      // [level, width] from meta.windowPresets
}

struct OverviewView: View {                   // 3D "peel" view: raymarched label volume, hidden layers transparent,
  init(bundle: CaseBundle, cut: Binding<CutPlane>, visibleLayerIDs: Set<Int>,   // cut plane clips the near side
       selectedFinding: CaseFinding?)         // vertical drag → cut.dragPivot along z; horizontal drag → orbit yaw
}

@Observable final class HingeTiltDriver {     // App/Duo/HingeTiltDriver.swift
  var isHingeAvailable: Bool { get }
  var lastHingeAngle: Double? { get }
  func bind(_ setTilt: @escaping (Double) -> Void)   // mapped via HingeMapping + HingeSmoother
  func start(); func stop()
}

struct DuoAdaptiveLayout<Slice: View, Controls: View>: View {   // App/Duo/DuoAdaptiveLayout.swift
  init(@ViewBuilder slice: () -> Slice, @ViewBuilder controls: () -> Controls)
  // table pose: slice on top, controls below the fold; book/regular: side by side; compact: stacked
}
```

## Rules

- **L3b owns** `Project.json`, `App/App.swift`, `App/ContentView.swift` and `App/UI/`.
- **L3c owns** `App/Render/` and `App/Duo/`. L3c doesn't edit `Project.json`: new folders under `App/` are picked up automatically, including `.metal` files.
- To test before integration, L3c may point `ContentView.swift` at its own `RenderTestView` **on its own branch only**. The Commander drops that change and keeps L3b's `ContentView`.
- Until L3c lands, L3b builds against a stub `SliceView` placed at `App/UI/Stubs/SliceViewStub.swift` under a different name, `SliceViewStub`. It swaps in the real `SliceView` after the merge.

## Changes

- 2026-09-26: created (Commander).
- 2026-09-26: OverviewView becomes a 3D peel raymarch, which shows peeling far better than a flat slice. Rendering parameters: `docs/viz/SPEC.md` (lane L4).
