# L2-synth handoff

- Task / state / UTC time: GZ-002, ready_for_integration, 2026-09-26T19:35Z (approx)
- Objective and acceptance criteria: Produce two A4-format synthetic case bundles (Sun, Circuit board) as early fixtures for the app lane, each under 2 MB, using the exact A4 file set (ct.raw, labels.raw, meta.json, layers.json, findings.json).
- Files changed:
  - `data/synth/make_synth.py` (generator, numpy only)
  - `data/synth/verify_synth.py` (reference-loader verifier)
  - `App/Cases/sun/{ct.raw,labels.raw,meta.json,layers.json,findings.json}`
  - `App/Cases/circuit/{ct.raw,labels.raw,meta.json,layers.json,findings.json}`
- Checks run and result:
  - `cd /Users/dqi26/Generalizable && uv run --python 3.12 --with numpy python data/synth/make_synth.py` → pass. Sun bundle 1,538,352 bytes (1.467 MiB); Circuit bundle 886,771 bytes (0.846 MiB). Neither uses `data/.venv`.
  - `cd /Users/dqi26/Generalizable && uv run --python 3.12 --with numpy python data/synth/verify_synth.py` → pass, full output:
    ```
    --- Sun (App/Cases/sun) ---
      size check ok: dims=[80, 80, 80] ct=1024000B labels=512000B
      bundle size ok: 1538352 bytes (1.467 MiB) < 2 MiB
      label ids ok: used=[1, 2, 3, 4, 5, 6] subset of layers.json ids=[1, 2, 3, 4, 5, 6]
      finding 'core' ok: ijk=[40, 40, 40] label=1
      finding 'sunspot' ok: ijk=[63, 53, 55] label=5
      Sun: ALL CHECKS PASSED
    --- Circuit board (App/Cases/circuit) ---
      size check ok: dims=[96, 96, 32] ct=589824B labels=294912B
      bundle size ok: 886771 bytes (0.846 MiB) < 2 MiB
      label ids ok: used=[1, 2, 3, 4, 5] subset of layers.json ids=[1, 2, 3, 4, 5]
      finding 'chip' ok: ijk=[48, 48, 14] label=3
      finding 'via' ok: ijk=[20, 48, 3] label=5
      Circuit board: ALL CHECKS PASSED

    All bundles verified OK.
    ```
- Evidence paths (previews, logs): no PNG preview generated (out of scope for this lane; L1's gate requires previews, L2's gate per ORCHESTRATION.md is only the byte-layout checks above plus the 2 MB cap, both met).
- Interface notes for other lanes:
  - Sun: 80³ grid, 10 mm isotropic spacing (~800 mm scale model), orientation RAS. Layers (outside→inside): coronal loop, photosphere, sunspot, convective zone, radiative zone, core. `window_presets` keys are `soft` and `density` (not bone/brain/lung — not applicable to a synthetic star). Findings: `core`, `sunspot`.
  - Circuit board: 96×96×32 grid, spacing [1.0, 1.0, 0.25] mm (96×96 mm footprint, 8 mm tall thin slab). Layers: chip package, solder balls, via, copper traces, substrate. Findings: `chip`, `via`.
  - Both: `source` = "Synthetic (generated for Generalizable demo)", `license` = "CC0". No PRD/A6 licensing concerns apply to this lane's data.
  - **Build location note for other lanes/Commander:** per ORCHESTRATION.md, most of the visualization (SwiftUI views, Metal shader, layouts, hinge) is built in Bitrig and the app runs from Bitrig — not all of it needs to happen there, but the visualization work in particular should be. This lane's synthetic bundles are plain data files reaching Bitrig through git (push the demo branch, then pull in Bitrig); no Swift/Bitrig work was done or needed in this lane.
- Fallbacks taken / scope cut: None needed — both bundles generated and verified on the first pass, well under the 2 MB cap (1.47 MiB and 0.85 MiB), leaving headroom.
- Blockers / requests: None.
- Next action (exact resumption step): Commander/app lane can point `CaseBundle` fixtures at `App/Cases/sun/` and `App/Cases/circuit/` as-is. If a preview PNG is wanted for the demo gate, run a small oblique-slice script against `ct.raw`/`meta.json` (not built here, out of L2 scope).
