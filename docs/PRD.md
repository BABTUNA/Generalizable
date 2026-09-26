# Generalizable — Product Requirements Document

- **Status:** Draft for the Bitrig Hacks iPhone Duo pitch demo
- **Date:** September 26, 2026
- **Lead platform:** iPhone Duo
- **Additional layouts:** iPhone and iPad
- **Addenda:** see [Addenda](#addenda) at the end. They clarify or extend this document; read them before implementing. Agents: **register in `coordination/agents/` first (see `AGENTS.md`)**, then add new addenda there rather than editing the sections above. **This is a 3-hour hackathon demo** (A7).

## Product summary

Generalizable helps someone understand the inside of a 3D subject. It pairs a source scan or model with named, colored layers and short explanations. The first demonstration is a doctor explaining a patient CT scan: the doctor points to a prepared finding, then folds iPhone Duo to change the angle of a cross-section through that same location. Two shorter examples, a circuit board and the Sun, show that the interaction can explain other subjects.

This release is a **synthetic, educational pitch demo**, not a diagnostic tool. All findings, labels, and explanations are authored for the demo. It does not analyze a scan or identify abnormalities on its own.

## Problem and audience

CT images contain rich spatial information but are difficult for a patient to interpret without guidance. A clinician needs a quick way to show where a finding is, what body structures surround it, and how it appears in more than one plane. The pitch audience also needs to see why the physical fold is a meaningful input rather than a decorative effect. CT image volumes can be reformatted into multiple planes and 3D views; the demo uses that property to explain a finding spatially. [RadiologyInfo: Body CT](https://www.radiologyinfo.org/en/info/bodyct)

Primary demo user: a clinician explaining a prepared finding to a patient. Secondary users: an educator or presenter explaining a circuit board or scientific model.

## Goals

1. Make one finding understandable in a 60–90 second live demonstration.
2. Make the Duo hinge visibly and continuously control the cut angle while the selected location stays fixed.
3. Keep the underlying scan or model available for comparison with the explanatory layers.
4. Show that one viewer supports three subjects by changing the content package.
5. Preserve the same essential exploration controls on iPhone and iPad without a hinge.

## Pitch walkthrough

1. Open **Patient CT**. The viewer shows a body overview and a list of four prepared findings.
2. Select **Lung nodule**. The overview, slice, marker, and explanation all move to the same location.
3. Peel back visible layers until the lungs and nearby anatomy are clear. The selected finding remains highlighted.
4. Lift the Duo lid. The cross-section tilts through the selected location; its angle readout changes with the hinge. Dragging the cut line moves its position, and a separate slice control moves through the volume.
5. Switch between **Layers — what patients see** and **CT scan — what doctors see**. The view stays at the same position and angle so the comparison is meaningful.
6. Open **Circuit board** and **The Sun** briefly. Their named regions and points of interest use the same viewer and controls.

The patient case contains these synthetic teaching annotations from the pitch artifact: lung nodule (14 mm, right upper lobe), widened artery (abdominal aortic aneurysm, 4.4 cm), liver cyst (2.4 cm), and kidney stone (9 mm). The lung nodule is the guided path; the other three must be selectable but need less narrative depth for the first demo.

## Functional requirements

### Shared viewer

- Load one of three bundled, synthetic cases: Patient CT, Circuit board, and The Sun. The demo works offline.
- Render an overview with a visible cut plane and a corresponding cross-section. Changing either view updates the other without losing the selected point of interest.
- Show named regions as colored layers that people can hide or reveal. The patient case offers Skin, Fat, Muscle, Bone, Lungs, Organs, and Blood. Layer visibility is an explanatory overlay, not a claim that every region is a perfectly nested physical shell.
- Offer an immediate comparison with the source-style grayscale CT in the patient case. Keep cut position, angle, and finding marker aligned when switching views.
- Show a concise title, measurement when relevant, location, and plain-language explanation for the selected point. Use **findings** for the patient case and **points of interest** for the other subjects.
- Provide Reset View and a visible angle and slice-position readout.

### iPhone Duo interaction

- In the partially folded pose, the hinge controls the tilt of the virtual cut plane. For the pitch mapping, 180° device angle means a flat cut, 120° means a 60° tilt, and 90° means a front-facing cut. This mapping is a demo interaction to validate on a Duo device, not a medical orientation convention.
- Selecting a finding places the cut through its anchor. Hinge motion rotates the cut around that anchor so the finding remains the focus.
- A draggable cut-line handle on the lower/overview surface translates the cut. A distinct slice slider or scroll region advances through slice levels, avoiding two competing drag gestures in the same touch area.
- An on-screen angle control provides a precise fallback and supports devices without a hinge. A separate rotation control is needed for cuts outside the hinge's single axis; the pitch should say **“change the cut angle by folding”** rather than **“at any angle.”**
- Keep the current case, selected finding, and view state when the app resizes between Duo displays. On a table pose, place the explanation and manipulable overview on the lower area and the live slice on the upper area. In a book pose, present the overview and slice side by side. Keep controls clear of the fold and reserved regions, following [Apple's Duo guidance](https://developer.apple.com/iphone-duo/).

### Other layouts and accessibility

- On a regular iPhone, show one primary canvas at a time with an obvious way to switch between overview and cross-section. On iPad, show them side by side when space permits.
- Every fold-driven action must also be possible through labeled touch controls. Expose the selected finding, layer state, angle, and slice position to VoiceOver. Support Dynamic Type, sufficient contrast, and Reduce Motion.

## Content interface and work split

Each case supplies a volume or equivalent 3D representation, spatial scale and orientation, named regions, points of interest anchored in that same space, and explanation copy. The viewer owns navigation, layer visibility, cut-plane geometry, rendering, and input mapping. Domain-specific content owns what the regions mean and which locations are highlighted.

The body-scan workstream is handed off to the teammate. Its first handoff should establish a representative synthetic or appropriately cleared teaching volume, coordinate and scale conventions, layer definitions, and reviewed annotation copy. The app can proceed with synthetic placeholder volumes while that handoff is underway. Circuit board and Sun content can stay intentionally small as long as they demonstrate the same data interface.

## Out of scope for the pitch demo

- Importing hospital scans, connecting to clinical systems, or storing patient data.
- Automatically detecting, measuring, or diagnosing abnormalities.
- Treating generated colors or explanations as a substitute for the source scan or a clinician's interpretation.
- A full set of arbitrary 3D rotations driven by the hinge alone.

Real patient data would require a separate privacy, security, and clinical-validation phase. DICOM's confidentiality guidance notes that identifying information can exist in metadata and in image pixels. [DICOM PS3.15](https://dicom.nema.org/medical/dicom/current/output/html/part15.html)

## Acceptance criteria

- A presenter can complete the patient walkthrough offline without editing data or navigating a setup flow.
- Selecting any of the four patient findings moves the overview, cross-section, marker, and explanation to a consistent location.
- The CT/layers switch preserves the selected position and angle; layer visibility changes do not move the cut.
- Folding through the supported demo range changes the cross-section continuously and visibly. The same result is reachable with the manual angle control.
- The cut-line drag and slice-level control can be operated independently and show their current values.
- All three cases open in the same viewer, and the key controls remain usable on compact iPhone and iPad layouts.
- The app labels synthetic content as a demo and never presents its authored findings as a live diagnosis.

## Dependencies and milestones

1. **Viewer foundation:** build the synthetic case format, layer controls, finding selection, paired overview and cross-section, and manual cut controls.
2. **Duo interaction:** integrate hinge angle and adapt the partially folded layout; test continuity across closed, partially open, and flat poses.
3. **Pitch polish:** complete the scripted patient journey, source-scan comparison, two short generality examples, accessibility pass, and live-demo rehearsal.

The current project uses the iOS 26.5 SDK. Duo hinge APIs and the Duo simulator require the iOS 27.1 SDK, so milestone 2 depends on selecting Xcode 27.1 in Bitrig and relaunching it. Milestone 1 can be built and reviewed now on available iPhone and iPad simulators.

## Decisions to validate during prototyping

- Whether the patient demo should show all four finding cards at once or reveal them after the guided lung-nodule moment.
- Whether the source-style CT view should occupy the full canvas or appear alongside the colored explanation on the larger inner display.
- How much physical hinge travel feels comfortable during a live presentation; adjust the angle mapping only after testing on Duo hardware or simulator.

## Addenda

Append-only. Each addendum has an ID, date, author, and status (**Adopted** = implement as written; **Proposed** = default until someone objects; **Open** = needs a decision before the dependent work starts). When an addendum is superseded, mark it so; don't delete it.

### A1: Cut-plane geometry (Proposed, 2026-09-26, Daniel via Claude Code)

The PRD names four controls that move the cut: hinge, cut-line drag, slice control, and a rotation control. Unless they share one model, they overlap: on a tilted plane, "move the cut line" and "move through the slices" can mean the same motion. The viewer should use this model:

- The cut plane is a **pivot point P** plus two angles: **tilt** (about the case's left–right axis) and **rotation** (about its vertical axis).
- **Selecting a finding** sets P to that finding's anchor and the slice offset to 0. Tilt and rotation stay as they are.
- The **hinge** and the **manual angle control** set tilt only, and the plane pivots around P. Both drive the same value, so the readout never disagrees with the plane.
- **Cut-line drag** moves P within the overview's plane, which changes where the cut sits in the body.
- The **slice control** moves the plane along its own normal by an offset from P. The readout shows the offset in the case's units, and "Return to finding" resets it to 0.
- **Rotation** is only an on-screen control. The hinge never drives it (PRD out-of-scope: hinge-only arbitrary rotation).
- The **angle readout** shows the cut tilt, not the device's hinge angle.

### A2: Hinge-to-tilt mapping (Proposed, 2026-09-26, Daniel via Claude Code)

The PRD's three sample points fit `tilt = 180° − hingeAngle`: 180° → 0°, 120° → 60°, 90° → 90°. Implement that as the default mapping and keep it in one function so it can be retuned after testing on hardware (see the validation list above).

- Clamp the hinge angle to 90°–180°. Below 90°, tilt stays at 90°.
- Smooth raw hinge samples lightly so the slice doesn't jitter, but keep the cut visibly continuous while the lid moves (acceptance criterion).
- When the device is closed or the hinge value is unavailable, keep the last tilt and let the manual control take over. Never snap the tilt back to a default.
- Reduce Motion: skip animated transitions between tilts. Still apply the tilt that the hinge sets directly.

### A3: SDK and deployment target (Proposed, 2026-09-26, Daniel via Claude Code)

`Project.json` targets iOS 26.0, but Duo hinge APIs need the iOS 27.1 SDK. Build with the 27.1 SDK when it's selected, and keep the **deployment target at 26.0**. Put hinge code behind `#available` / `@available` checks so milestone 1 keeps running on iPhone and iPad simulators without the Duo runtime. All hinge input goes through one adapter that outputs a tilt value. Without the Duo runtime, that adapter supplies no value, and the manual control remains the only way to set tilt.

### A4: Case bundle format and rendering (Adopted, 2026-09-26, Daniel via Claude Code)

Source: the body-scan data pipeline brief (the "Layer Lens data pipeline" prompt, which still uses the project's old name). It defines the "Content interface" section's format. Every case, including Circuit board and The Sun, ships as one bundle directory with these files:

| File | Contents |
|---|---|
| `ct.raw` | int16 little-endian HU values with no header. Ordered **x fastest, then y, then z**, with z increasing toward the head. |
| `labels.raw` | uint8 label IDs on the same grid and in the same order. 0 = background. |
| `meta.json` | `dims`, `spacing_mm`, `origin_mm`, `orientation: "RAS"`, dtypes, `window_presets` (soft, bone, brain, lung as `[level, width]`), `source`, `license` |
| `layers.json` | Layers ordered outside to inside: `id` (matches the label ID), `name`, `group` (`skin, fat, muscle, bone, organ, brain, finding`), `color`, `peel_order`, `blurb` |
| `findings.json` | `id`, `label_id`, `title`, `center_mm`, `radius_mm`, `explanation` |

- **Rendering:** a Metal shader samples `ct.raw` and `labels.raw` as 3D textures and slices them along the cut plane. Texture width = x, height = y, depth = z. Sample labels with nearest-neighbor filtering (never interpolate label IDs). Sample CT with linear filtering.
- **Coordinates:** RAS, so +x = patient left, +y = anterior, +z = superior. Voxel ijk → mm is `origin_mm + ijk * spacing_mm` (axis-aligned, with no rotation matrix in the bundle). A finding's `center_mm` is its anchor and becomes pivot P in A1. Tilt rotates about the x (left–right) axis, and rotation turns about z. The cut plane is flat, or axial, at tilt 0°.
- **CT / layers view switch:** the grayscale "what doctors see" view windows `ct.raw` using `window_presets`. The colored view overlays `labels.raw` using `layers.json` colors. Both views use the same cut geometry, which satisfies the PRD's alignment requirement.
- **Peeling:** a layer is hidden by masking its label ID in the shader. Hiding a layer never moves the cut.
- **Sizes:** body is about 2.0 mm isotropic (≤ ~130 MB `ct.raw`), and brain is about 0.8 mm (≤ 256 voxels per axis). Bundle both in the app so it works offline. The data pipeline's `data/verify.py` is the reference loader for byte layout.
- **Circuit board and The Sun:** use the same five files with synthetic volumes. `ct.raw` holds an arbitrary int16 density (`meta.json` provides window presets that suit it), and the findings array holds points of interest.

### A5: Cases, layers, and findings reconciled with the pipeline (Proposed, 2026-09-26, Daniel via Claude Code)

The pipeline produces two real medical volumes, not the one synthetic patient case the PRD describes:

- **Body:** Visible Human Male CT, a 1990s cadaver scan. `findings.json` is **empty**, and the pipeline is told not to invent findings.
- **Brain:** a CQ500 head CT with a real intracranial bleed, segmented by Seg-CQ500. It has **one finding**, whose title comes from the CQ500 radiologist reads.

Proposed changes:

- The case list becomes **Body CT**, **Head CT (bleed)**, **Circuit board**, and **The Sun**.
- The PRD's four synthetic patient findings (lung nodule, aneurysm, liver cyst, kidney stone) don't exist in either volume. **The Head CT bleed replaces the lung nodule as the guided finding** (walkthrough step 2). The Body CT stays a findings-free anatomy explorer.
- The PRD layer names map to pipeline groups:
  - Skin → skin
  - Fat → fat
  - Muscle → muscle
  - Bone → bone
  - Lungs → an organ layer
  - Organs → the other organ layers
  - Blood → the aorta organ layer on the body; the bleed `finding` layer on the head
  - Brain is new.

  The UI shows `layers.json` names, not hard-coded PRD names.
- Acceptance criterion "Selecting any of the four patient findings…" becomes "Selecting any finding in any case…".
- The layer list may contain HU-threshold fallbacks where TotalSegmentator failed on the cadaver scan. `PIPELINE_LOG.md` records which ones. The UI doesn't need to distinguish them.

### A6 ruling (Adopted, 2026-09-26, Daniel)

Daniel's ruling: *"The data we are using is open source. This isn't an issue."* Items 1 and 2 below are closed. The app and pitch say **"Demo only — public open-source research data (Visible Human, CQ500). Not a diagnosis."** The in-app credits screen lists each dataset's licence. Item 3 (whether data bundles go in git) defaults to **not committed**: `data/out/` stays local and is copied into the app bundle at build time until someone decides otherwise.

### A7: Three-hour demo scope (Adopted, 2026-09-26, Daniel)

**This is a hackathon demo with a hard 3-hour budget. It is not a product.** When a requirement conflicts with the clock, cut it. Priority order:

1. **Must work on stage:**
   - Head CT and Body CT load offline.
   - Peel layers.
   - Cut plane with the manual angle slider.
   - CT/layers switch.
   - Select the bleed finding.
   - The "Demo only" label.
2. **Should:** the hinge drives the tilt (A2/A3), if the 27.1 SDK and the Duo simulator are available in Bitrig.
3. **Cut first:**
   - Circuit board and The Sun (one of them at most, as a tiny synthetic volume).
   - iPad layout polish.
   - The VoiceOver pass beyond basic labels.
   - Optional cryosection colour data.
   - The rotation control.

Agents doing the work follow `docs/ORCHESTRATION.md`.

### A8: Getting CT bundles into Bitrig (Open, 2026-09-26, Daniel via Claude Code)

This addendum supersedes the A6 ruling's "not committed" default wherever Bitrig is involved. Bitrig builds from the Git repo, so gitignored bundles never reach the app it builds. Options:

- **(a) Commit demo-sized bundles.** Downsample so every file is under ~50 MB (GitHub rejects files over 100 MB). Proposed targets:
  - Head: 1.0 mm (about 256³ → ~33 MB CT + 16 MB labels).
  - Body: 3.0 mm (~40 MB CT).

  Cost: about 100 MB of permanent repo history. Git LFS could shrink that, but whether Bitrig supports LFS is unknown.
- **(b) Download the bundles on first launch** from a GitHub Release. This breaks the PRD's offline requirement unless the simulator is warmed up before the demo.
- **(c) Build the CT cases only locally in Xcode.** This contradicts the rule that the app is built in Bitrig.

The Commander recommends **(a)**. It's reversible only by rewriting history.

**Ruling (Adopted, 2026-09-26, Daniel):** *"Do whatever works best. The demo needs to work on Bitrig, so data needs to be there. We will only be demoing a few cases."* → **Option (a).**

- `scripts/make_demo_bundles.py` resamples `data/out/{body,brain}` into `App/Cases/{body,head}` so that every file stays under 45 MB, and those bundles are committed.
- `data/out/` itself stays gitignored.
- The only cases are Head CT, Body CT, the Sun and Circuit board. Nothing further is added.

### A6: Real de-identified data and licensing (Open → see A6 ruling above, 2026-09-26, Daniel via Claude Code)

The PRD says all findings are authored for the demo and that real patient data needs a separate privacy phase. The pipeline instead uses **public, de-identified research scans**. These decisions need an explicit ruling before the pitch:

1. **Framing:** CQ500 findings are real radiologist reads, not authored copy. The "synthetic content" label and the out-of-scope section need rewording along the lines of "public de-identified research data, shown for education; not a diagnosis." Only the pipeline's non-clinical-demo statement is settled so far.
2. **Licence:** CQ500 is **CC BY-NC-SA 4.0**. That is fine for a hackathon demo, but it rules out commercial use of the head case, and derived bundles must carry the same licence. Visible Human (NLM T&C), Seg-CQ500 (CC BY 4.0), and TotalSegmentator (Apache-2.0) require attribution. Show credits in-app from `meta.json` `source`/`license` and `data/ATTRIBUTION.md`.
3. **Repo:** decide whether the bundles (hundreds of MB) are committed, stored with Git LFS, or kept out of git and dropped into the app locally. The pipeline already gitignores only `data/raw/` and `data/work/`, not `data/out/`.

### A9: Who builds the visualization code (Adopted, 2026-09-26, Commander under Daniel's goal "do not stop until the working demo is done")

Every Bitrig step needs Daniel to paste the prompt, and Bitrig's permission rules block repository bootstrap commands. To make sure a demo exists:

- **Commander Sonnet subagents write the L3b UI and L3c render code in the repo,** in the same paths and against the same contract (`docs/contracts/render-interface.md`).
- They verify it locally with `scripts/build_sim.sh`. It generates `Generalizable.xcodeproj` from `Project.json` with XcodeGen (gitignored), builds for an iOS 27.0 / 26.5 simulator, launches the app and takes a screenshot.
- **Bitrig remains the demo host.** It imports the branch, builds and runs it, and owns the **Duo hinge integration**, because the iOS 27.1 SDK and the Duo simulator exist only there. It also polishes the result.
- `Project.json` now copies `App/Cases` as a folder reference, so the cases keep their `Cases/<name>/` paths.
