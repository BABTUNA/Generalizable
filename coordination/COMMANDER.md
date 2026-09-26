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
