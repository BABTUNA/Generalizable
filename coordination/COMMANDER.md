# Commander bulletin

> **DEMO ONLY: 3-hour budget, starting 2026-09-26 afternoon.**

- **Commander:** Daniel's Claude Code session on the demo branch `demo/addenda-and-pipeline`.
- **Contract:** PRD addendum A4. Scope order: A7.
- **Machine facts:**
  - Xcode 27.0 with the iOS 27.0 SDK. There is **no 27.1 SDK and no Duo simulator**, so the hinge stays a stub (A3).
  - No xcodegen; Bitrig builds the project.
  - Python 3.14 is the default. Data work uses Python 3.12 through `uv`.
  - About 300 GB of disk is free.
- **A8 ruled (option a).** Commit the downsampled CT bundles, produced by `scripts/make_demo_bundles.py` with every file under 45 MB. The script's resampler is self-tested: bounds are kept and label centroids shift by less than one voxel.
- **Duplicate-work risk:** the PRD hands the body-scan workstream to a teammate. If they are already running the data-pipeline brief, stop L1 and use their output.

## Progress: 2026-09-26 ~19:55 UTC (update 1)

- **Integrated on `demo/addenda-and-pipeline`:**
  - L2: the `sun` and `circuit` bundles in `App/Cases/`. `data/synth/verify_synth.py` passes.
  - L3a: `App/Core/CaseBundle.swift` and `CutPlane.swift`. The iOS simulator typecheck and the macOS self-test pass. **The blind review is still pending**, and fixes may follow in a later update. Don't edit `App/Core`; report problems to the Commander.
- **In progress:** L1 CT data. The Head CT and Body CT bundles aren't in the app yet; the Commander adds them in a later update, downsampled per A8.
- **Bitrig lanes split into two tracks:** L3b UI (account A, `agent/bitrig/l3b`) and L3c render + Duo (account B, `agent/bitrig/l3c-duo`). Both branches now exist on GitHub at this commit.
  - Start with Prompt 0 (register) in `docs/bitrig-prompts.md`.
  - The interface between the tracks is `docs/contracts/render-interface.md`.
- **Until the CT bundles land,** Bitrig tracks test with `sun` and `circuit`.

## Progress: 2026-09-26 ~20:05 UTC (update 2)

- **Goal (Daniel):** keep going until the working demo is done. PRD A9: Commander Sonnet subagents write the UI and render code, and Bitrig hosts the demo and adds the Duo hinge.
- **Local build path:** `scripts/build_sim.sh [shot.png] [launch args]`, which uses XcodeGen and the iOS simulator. `Project.json` now copies `App/Cases` as a folder reference.
- **Running now:**
  - `cc-l3c-render`: Metal `SliceView`, 3D peel `OverviewView`, `DuoAdaptiveLayout`, `HingeTiltDriver`. Worktree, branch `agent/cc/l3c-render`.
  - `cc-l3b-ui`: case picker, viewer controls and banner, built against stubs. Worktree, branch `agent/cc/l3b-ui`.
  - `cc-l4-viz`: label cleanup and `docs/viz/SPEC.md`.
  - `cc-l1-data`: Head CT (CQ500 + Seg-CQ500).
- **Body CT bundle:** built locally (39 MB CT, 20 MB labels). It gets committed after the L4 label cleanup.
- **Contract change:** `OverviewView` is a 3D peel raymarch (see `docs/contracts/render-interface.md`).
- **Bitrig:** registration is blocked by Bitrig's permission rules on repository bootstrap. A non-destructive merge (`--allow-unrelated-histories -X theirs`) was sent to it.

## Progress: 2026-09-26 ~20:35 UTC (update 3)

- **All four cases are committed in `App/Cases`:**
  - `head`: CQ500-CT-243 with a subdural hemorrhage finding.
  - `body`: Visible Human, with cleaned labels plus Intestines, Pancreas and Bladder.
  - `sun` and `circuit`.
  - `data/verify.py` passes on every one.
- **Raw data, NIfTI volumes, TotalSegmentator masks and model weights** are on the orphan branch `data/assets`, chunked to under 95 MB. Restore with `unpack.sh`.
- **Orientation fix (7ee77ea):** `CutPlane` now uses the radiological convention. RAS +x is the patient's RIGHT; A4 is corrected.
- **Next:** merge the L3c render and L3b UI branches, swap the stubs, and build and screenshot with `scripts/build_sim.sh`. Bitrig then fetches `agent/bitrig/l3c-duo` from GitHub by URL (see `coordination/inbox/bitrig-l3c-duo.md`).

## Bitrig status: 2026-09-26 ~20:40 UTC

- `bitrig-l3c-duo` **registered** (Bitrig commit 0344e82). The Commander imported its registration and handoff from Bitrig's checkout (b4bd5a5).
- In Bitrig, the app builds and launches on the iPhone and iPad simulators.
- **Blocked:** there's no Xcode 27.1 / iOS 27.1 SDK and no Duo simulator on this machine. The hinge API names come from Bitrig's Duo guide: SwiftUI `.onHingeChange(isEnabled:_:)` passes a `DeviceHingeContext` (`.hinge?.status` / `.angle`); UIKit has `UIHingeInteraction` and `UIHinge`. Units and range are unconfirmed.
- The demo therefore uses the manual tilt slider (A3 fallback, A7 "should" tier). `DuoHingeSource.swift` gets written once Xcode 27.1 is installed and selected in Bitrig.
