# L3a-core handoff

- Task / state / UTC time: L3a-core non-visual Swift (CaseBundle + CutPlane). State: ready_for_integration. 2026-09-26, ~19:45 UTC.
- Objective and acceptance criteria: Implement `App/Core/CaseBundle.swift` and `App/Core/CutPlane.swift` per the Required API in the task brief and PRD A1/A2/A3/A4, with no SwiftUI/UIKit, matching field names Bitrig's views build against. Pass the iOS-simulator typecheck and a macOS self-test covering hinge mapping, cut-plane geometry, texture-coord round trip, and (if available in time) a real bundle load + Metal texture creation.
- Files changed:
  - `App/Core/CaseBundle.swift` (new): `CaseMeta`, `CaseLayer` (+ `rgba`), `CaseFinding` (+ `center`), `CaseBundle` class with `load`/`bundled`/`availableBundled`, `extentMM`/`centerMM`, `mm(forVoxel:)`, `textureCoord(forMM:)`, `hu(at:)`/`label(at:)`, `makeTextures(device:)` (CT `.r16Snorm`, labels `.r8Uint`, both `.type3D`).
  - `App/Core/CutPlane.swift` (new): `CutPlane`, `HingeMapping`, `HingeSmoother`, `HingeAngleSource` + `ManualOnlyHingeSource`.
- Checks run and result:
  - `xcrun -sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.0-simulator App/Core/*.swift` → **pass**, no output.
  - macOS self-test at `/private/tmp/claude-503/gz-selftest/` (compiled with `xcrun swiftc`, App/Core sources + a `main.swift` harness): **29/29 assertions pass**, including `HingeMapping` at 180/120/90/60/200 → 0/60/90/90/0, `CutPlane` normal/axes at tilt 0 and 90 (orthonormal frame after rotation too), `select()`/`dragPivot()`, a synthetic bundle's `textureCoord`/`hu`/`label` round trips, `makeTextures` on a synthetic bundle, **and** (sun bundle appeared during the poll) `CaseBundle.load` + `makeTextures` on the real `App/Cases/sun` bundle. Full output: `SELFTEST OK (0 failures)`.
- Evidence paths (previews, logs): `/private/tmp/claude-503/gz-selftest/main.swift`, `/private/tmp/claude-503/gz-selftest/selftest.out`.
- Interface notes for other lanes (**blocker for L2 / Commander, A4 clarification needed**):
  - L2's `App/Cases/{sun,circuit}/meta.json` ships a nested `"dtypes": {"ct": "...", "labels": "..."}` object, not the flat `ct_dtype`/`labels_dtype` keys the Required API names. A4 itself only says "dtypes" without pinning the shape.
  - L2's `findings.json` `id` is a semantic string (`"core"`, `"sunspot"`), not the `Int` the Required API specifies for `CaseFinding.id` (Identifiable).
  - **Fallback taken** (see below) rather than stalling on this — but A4 should be amended to pick one shape so Bitrig's views and future bundles don't drift further.
- Fallbacks taken / scope cut:
  - `CaseMeta` decodes either the flat or the nested `dtypes` shape; `CaseFinding.id` decodes an `Int` directly or derives a stable (non-randomized, FNV-1a based) `Int` from a string id. Swift-side property names/types Bitrig builds against are unchanged from the Required API in both cases — only JSON parsing is tolerant.
- Blockers / requests: None blocking integration. Requesting the Commander file an A4 addendum picking one `dtypes` shape and one `findings[].id` type so L2/L3a don't need per-bundle tolerance going forward.
- Next action (exact resumption step): None required for L3a. If A4 is amended, drop the tolerant-decode fallback in `CaseMeta`/`CaseFinding` in favor of the single agreed shape.

**Note (out of my lane, for the Commander):** the task brief for this run also said "building should be done in Bitrig — not all of it needs to be done there, but much of it should be, for the visualization," which matches `docs/ORCHESTRATION.md`'s existing "Where things get built" section. No action taken here since visualization is explicitly outside `App/Core/`.
