# Layer Lens — Product Requirements Document

- **Status:** Draft for the Bitrig Hacks iPhone Duo pitch demo
- **Date:** September 26, 2026
- **Lead platform:** iPhone Duo
- **Additional layouts:** iPhone and iPad

## Product summary

Layer Lens helps someone understand the inside of a 3D subject. It pairs a source scan or model with named, colored layers and short explanations. The first demonstration is a doctor explaining a patient CT scan: the doctor points to a prepared finding, then folds iPhone Duo to change the angle of a cross-section through that same location. Two shorter examples, a circuit board and the Sun, show that the interaction can explain other subjects.

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
