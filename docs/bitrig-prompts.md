# Bitrig prompts: lanes L3b (UI) and L3c (render + Duo)

> **DEMO ONLY: 3-hour hackathon build. Uses public open-source research data. Not a diagnosis.**
> The visualization is built **in Bitrig**, in two parallel tracks on two accounts:
> - **Track A** (account A) = L3b UI, branch `agent/bitrig/l3b`
> - **Track B** (account B) = L3c render + Duo, branch `agent/bitrig/l3c-duo`
>
> Both tracks import `machmoon/Generalizable` from the `demo/addenda-and-pipeline` branch and then work on their own branch. **Neither ever works on `main`.** Send one prompt at a time, run the app on the simulator, and check the acceptance line before sending the next.
> All four cases (`head`, `body`, `sun`, `circuit`) are committed in `App/Cases/` (A8 ruling). The interface between the tracks is `docs/contracts/render-interface.md`.

**Context (paste at the top of every prompt; set LANE, AGENT and BRANCH for your track):**

> This is Generalizable, a 3-hour hackathon demo. Read `AGENTS.md`, `docs/ORCHESTRATION.md` and `docs/contracts/render-interface.md`. You are registered agent AGENT, lane LANE, on branch BRANCH (never `main`). Spec: `docs/PRD.md` Addenda A1–A4, A7 and A8. Edit only your lane's paths. Never modify `App/Core/`, `App/Cases/`, `data/`, `docs/`, or another agent's files in `coordination/`. Build on the existing `App/Core` API: `CaseBundle`, `CaseLayer`, `CaseFinding`, `CutPlane`, `HingeMapping`, `HingeSmoother`, `HingeAngleSource`.

**Footer (paste at the end of every prompt):**

> When done, update `coordination/handoffs/LANE.md` using the handoff template in `docs/ORCHESTRATION.md`: what you built, what you ran on the simulator, and any blockers. Keep `coordination/agents/AGENT.json` `status` current. Commit to BRANCH.

| Track | AGENT | LANE | BRANCH |
|---|---|---|---|
| A | `bitrig-l3b` | `L3b-ui` | `agent/bitrig/l3b` |
| B | `bitrig-l3c-duo` | `L3c-render-duo` | `agent/bitrig/l3c-duo` |

---

## Both tracks: Prompt 0 (Register, then stop)

Read `AGENTS.md`. Update `coordination/agents/AGENT.json`:
- `status` → `active`
- `model` → the model you run on
- `branch` → BRANCH
- `registered_utc` → now

Create `coordination/handoffs/LANE.md` from the template with state `in_progress`. Commit only those two files to BRANCH. Change no code.

*Acceptance:* the commit touches exactly those two files.

---

## Track B (L3c render + Duo)

### B1: Duo + Metal proof (de-risk first)

Select the iOS 27.1 SDK (Xcode 27.1) and run on the iPhone Duo simulator. If either is unavailable, say so and continue on a normal iPhone simulator using the slider.

1. Create `App/Render/RenderTestView.swift` and `App/Render/Slice.metal`. Load `CaseBundle.bundled("sun")` and upload it with `bundle.makeTextures(device:)`:
   - CT is `r16Snorm`, sampled with linear filtering; HU = value × 32767.
   - Labels are `r8Uint`, read with `texture.read`, never filtered.
2. Use an `MTKView` in a `UIViewRepresentable`. It draws a full-screen quad whose fragment shader samples on the `CutPlane`: mm = `originMM` + u·`uAxis` + v·`vAxis`, then `bundle.textureCoord(forMM:)` (do the same math in the shader). Colour pixels with the `layers.json` colours over dimmed CT, and draw black outside the volume.
3. Add a tilt slider (0–90°) bound to `cut.tiltDegrees`, a readout "Hinge <raw>° → Tilt <tilt>°", and the permanent label "Demo only — not a diagnosis."
4. In `App/Duo/HingeTiltDriver.swift`, behind `if #available(iOS 27.1, *)`, use Apple's iPhone Duo hinge-angle API (look it up in the 27.1 SDK; see https://developer.apple.com/iphone-duo/). Map it through `HingeMapping.tilt(forHingeAngle:)`, then `HingeSmoother`, into the same tilt value the slider drives. When updates stop, keep the last tilt.
5. On this branch only, point `ContentView` at `RenderTestView` so it can be run.

End with a **REPORT**:
- the Xcode, SDK and simulator actually used
- the exact hinge API names, and their units and range. What does it read flat, in table pose and closed? Is 180 flat?
- how the simulator changes the hinge angle
- any Metal validation errors with `r16Snorm` / `r8Uint` 3D textures
- the pose-detection API names
- the frame rate while folding
- anything that contradicts tilt = 180 − hinge angle

*Acceptance:* moving the hinge re-slices the Sun continuously. Flat gives concentric rings (axial); at 90° you get the front-facing cut. The slider reproduces the same image.

### B2: SliceView and OverviewView per the contract

Turn the renderer into `SliceView` and `OverviewView`, with exactly the signatures in `docs/contracts/render-interface.md`:
- `SliceMode.ct` draws grayscale windowed CT; `.layers` draws the coloured layers over dimmed CT.
- Hidden layer IDs are masked out.
- Draw a marker ring at `selectedFinding` when it lies within its radius of the plane.
- `OverviewView` shows a mid-sagittal slice with the cut drawn as a line and a drag handle that calls `cut.dragPivot`.

Test it in `RenderTestView` on `head` (select its finding) and on `body`.

*Acceptance:* on Head CT the magenta bleed ring stays centred while the tilt changes, and switching `ct` ↔ `layers` keeps the same geometry.

### B3: DuoAdaptiveLayout

Build `DuoAdaptiveLayout` per the contract:
- **Table pose:** slice on the upper area, controls on the lower area, clear of the fold.
- **Book pose / regular width:** side by side.
- **Compact iPhone:** stacked, with a segmented switch.

State must survive every pose change and resize. Make `HingeTiltDriver.isHingeAvailable` false wherever there's no Duo.

*Acceptance:* folding through table, book and flat keeps the same cut and selection.

---

## Track A (L3b UI)

### A1: Wiring, case picker and credits

Update `Project.json` so that `App/Cases` is copied into the app as a **folder reference**, keeping the `Cases/<name>/` subpaths (the cases share file names like `ct.raw`), and exclude it from the normal source group.

Build the root screen:
- title "Generalizable"
- a permanent banner: **"Demo only — public open-source research data. Not a diagnosis."**
- the cases from `CaseBundle.availableBundled()`, shown as Head CT, Body CT, The Sun and Circuit board
- loading happens off the main thread
- a credits sheet listing every case's `meta.source` and `meta.license`

*Acceptance:* all four cases open and show their layer count.

### A2: Viewer screen (A7 must-list), using `SliceViewStub` until track B merges

Create `App/UI/Stubs/SliceViewStub.swift`, with the same parameters as the contract's `SliceView`, that draws the case name and cut values. Then build the viewer:

- **Layer toggles:** in `peelOrder` order, with colour swatches and blurbs. Toggling never moves the cut.
- **Mode switch:** "Layers — what patients see" / "CT scan — what doctors see".
- **Findings list:** titled "Findings" for head/body and "Points of interest" otherwise. Tapping one calls `cut.select`, and the panel shows the title, the size (2 × `radiusMM`) and the explanation.
- **Tilt slider:** 0–90°, readout "Cut tilt 60°".
- **Slice slider:** bound to `sliceOffsetMM`, readout in mm, with a "Return to finding" button.
- **Reset View**, and a **window-preset picker** from `meta.windowPresets`.
- **Hinge:** if a `HingeTiltDriver` exists after the merge, bind it to the same tilt. Until then, only the slider drives tilt.
- **VoiceOver:** labels for the tilt, slice, selected finding and layer toggles.

*Acceptance:* every control changes the stub's readout, and switching modes keeps the cut values.

### A3: Swap in the real renderer (after the Commander says track B is merged)

Pull the demo branch. Replace `SliceViewStub` with `SliceView` and wrap the viewer in `DuoAdaptiveLayout`. Delete the stub.

*Acceptance:* the full rehearsal checklist below passes on the Duo simulator.

---

## Rehearsal checklist (A7), after both tracks are merged

1. The Head CT opens offline.
2. Peel skin, then bone, and the bleed stays visible.
3. Select the bleed.
4. Tilt 0 → 60° by hinge, and by slider.
5. Switch CT ↔ Layers, and the position is kept.
6. Show the Body CT briefly.
7. Show the Sun or Circuit board.
8. The demo banner is visible throughout.
