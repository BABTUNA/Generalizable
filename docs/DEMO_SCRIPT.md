# Demo script (60–90 s)

> **DEMO ONLY: public open-source research data, not a diagnosis.** Say this aloud once, in beat 1.

This script follows the PRD "Pitch walkthrough" as amended by **A5**. The guided finding is the **Head CT bleed**, not the lung nodule. **Body CT** has no findings, so it is used for peeling. **The Sun** and **Circuit board** show that the viewer works on any volume.

**Hinge rule (A3):** say *"change the cut angle by folding"* only if the Duo hinge has been confirmed working on the demo device that day. Otherwise use the on-screen **angle slider** and say *"change the cut angle"*. Never say "at any angle."

**Current build (517a212):** the Overview pane renders empty at tilt 0, so point the audience at the slice pane. Update this note when the overview renders.

**Before going on stage:** launch the app once so the cases are warm, then return to the case list. Keep the `scripts/demo_tour.sh` output directory open on a laptop as the screenshot fallback.

---

### Beat 1 — Open the head (≈10 s)

- **Tap:** **Head CT** in the case list.
- **Say:** "This is a real, public head CT, case CQ500-CT-243 from the CQ500 research set. It's open data, and nothing here is a diagnosis."
- **Audience sees:** the live cross-section at the top, with the bleed tinted magenta and ringed in yellow. The demo banner is visible. The layer list (Skin, Skull, Brain, Bleed) and the angle slider are on the **Controls** tab below the slice.
- **If it fails:** "The live render is catching up. Here's the same view," and show `head_layers_t0.png`.

### Beat 2 — Select the bleed (≈15 s)

- **Tap:** the **Subdural hemorrhage** finding.
- **Say:** "Select a finding and everything moves to it at once: the 3D view, the slice, the marker and a plain-language explanation. This one is bleeding between the brain and the skull. Three radiologists agreed on it."
- **Audience sees:** the cut jumps to the bleed and a yellow ring marks it. The explanation appears with the finding.
- **If it fails:** relaunch with `-case head -select 1`, or show `head_layers_t0.png` and read the explanation aloud.

### Beat 3 — Peel and tilt (≈15 s)

- **Tap:** open the **Controls** tab and hide **Skin**, then **Skull**. Then tilt: **fold the Duo lid** (if the hinge works) or **drag the angle slider** up to about 60°.
- **Say:** "Peel away the colored layers until the bleed stands out. Then change the cut angle by folding." (Without the hinge: "…then change the cut angle.") "The cut rotates around the finding, so it stays in the centre."
- **Audience sees:** the skin and skull lose their color, but the bone stays visible in the grayscale underneath. The bleed stays ringed. As the angle climbs, the slice turns from a top-down view into a front-on one.
- **If it fails:** show `head_skin_bone_hidden.png` and `head_layers_t60.png` one after the other.

### Beat 4 — Patients vs doctors (≈10 s)

- **Tap:** switch **Layers → CT scan**, then switch back.
- **Say:** "This is the same cut in what a doctor sees, the grayscale CT. The position and angle don't change, so you're comparing like with like."
- **Audience sees:** the colored slice turns into a grayscale slice at the same angle, with the yellow ring still on the bleed.
- **If it fails:** show `head_layers_t60.png` next to `head_ct_t60.png`.

### Beat 5 — The body (≈15 s)

- **Tap:** back, then **Body CT**. Hide **Skin** and **Fat**.
- **Say:** "The same viewer on a whole body, the Visible Human scan. Peel the skin and fat and you reach the muscle, bone and organs: lungs, heart, liver, kidneys, aorta."
- **Audience sees:** a chest cross-section with the liver, heart, lungs and spine. The yellow fat outline and the skin tint disappear, and the organs stay colored.
- **If it fails:** show `body_all.png`, then `body_skin_fat_hidden.png`.

### Beat 6 — Any volume (≈10 s)

- **Tap:** back, then **The Sun**, then tap **The Core**. If there's time, open **Circuit board** and tap **A Via**.
- **Say:** "Nothing in this viewer is specific to medicine. Here it's the Sun, with the same layers, cut and points of interest. Here it's a circuit board. Any sliced volume works."
- **Audience sees:** the same UI on a very different subject: the Sun's nested zones with the core ringed, and the chip package ringed on the board.
- **If it fails:** show `sun.png` and `circuit.png`.

### Close (≈5 s)

- **Say:** "Generalizable is one viewer for anything you can slice. It's built on public research data, and it's a demo, not a diagnosis."
