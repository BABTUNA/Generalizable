# L7-mpr handoff
- Task / state / UTC time: Scan viewer mode (BodyMaps-style MPR). Done. 2026-09-26 ~21:05 UTC.
- Objective and acceptance criteria: add a "Scan" mode with linked axial/sagittal/coronal/3D
  panes, shared crosshair, window presets, organ legend; hook into ViewerView as an
  Explore/Scan toggle plus `-scan` launch arg; verify orientation on iPhone and iPad sims.
- Files changed:
  - `App/UI/Scan/ScanView.swift` (new) — layout (2x2 grid on regular/landscape, single pane +
    picker on compact portrait), show-organs toggle, window preset segmented control + L/W
    readout, mm+HU crosshair readout, organ legend (reuses `model.peelOrderedLayers` /
    `isVisible` / `setVisible`).
  - `App/UI/Scan/ScanPane.swift` (new) — wraps `SliceView` per pane with a tap/drag crosshair
    overlay. `ScanPaneFrame` mirrors `SliceMetalView.draw()`'s framing math (projectedHalfExtent
    + aspect-fit + view-centre) and `Slice.metal`'s NDC convention exactly, so the overlay lines
    up with what the shader draws.
  - `App/UI/ViewerView.swift` — added `ViewerScreen` enum + segmented toolbar picker
    (Explore/Scan), `-scan` launch-arg default, `Group { switch screen { ... } }`. No other
    lines touched.
  - `coordination/agents/cc-l7-mpr.json` (new registration).
- Checks run and result:
  - `SIM_DEVICE="iPhone 17 Pro Max" scripts/build_sim.sh /tmp/claude-503/l7-1.png -case head -scan`
    → BUILD OK, screenshot captured (compact portrait: single-pane + picker layout).
  - `SIM_DEVICE="iPad Air 11-inch (M4)" scripts/build_sim.sh /tmp/claude-503/l7-2.png -case body -scan`
    → BUILD OK, screenshot captured (2x2 grid).
  - Visual check: coronal and sagittal both head-up; sagittal shows face (anterior) on one side
    and spine (posterior) on the other — a true sagittal, no sign flip needed
    (`rotationDegrees: 90` was correct as specified). Axial/coronal patient-right-on-screen-left
    inherited unchanged from `CutPlane.uAxis` (not touched by this lane).
- Evidence paths (previews, logs): `/tmp/claude-503/l7-1.png`, `/tmp/claude-503/l7-2.png`
  (local sandbox paths, not committed).
- Interface notes for other lanes: only reuses existing contract surface (`SliceView`,
  `OverviewView`, `SliceMode`, `CutPlane`, `ViewerModel`'s existing properties). No changes to
  `docs/contracts/render-interface.md` or any file another lane owns, other than the additive
  toolbar/enum hook in `ViewerView.swift`.
- Fallbacks taken / scope cut:
  - Legend opacity is global only (per spec) — no per-organ opacity slider.
  - 3D pane in Scan mode binds `OverviewView` to the same `$model.cut` as Explore mode (shares
    tilt/orbit state); it does not get its own independent crosshair-only camera.
  - Crosshair overlay is a static SwiftUI `Path`, no visible "handle" — drag from anywhere in a
    pane to move it.
- Blockers / requests: none.
- Next action (exact resumption step): none required; mode defaults to Explore, Scan is opt-in
  via toolbar or `-scan`. If cases with a `subdural` (or other) extra window preset are added,
  no change needed — the segmented control already lists `meta.windowPresets.keys.sorted()`.
