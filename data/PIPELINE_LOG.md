# Data pipeline log (L1-data)

Times are local (UTC-? not tracked precisely); order of operations below is authoritative.

## 0. Setup

- `uv venv --python 3.12 data/.venv` (Commander override: py3.12, system Python is 3.14).
- Installed: `idc-index nibabel SimpleITK numpy scipy pydicom dicom2nifti matplotlib`, then separately `torch TotalSegmentator` (both installed cleanly, no MPS issues).
- `df -h .` showed 309 GB free — plenty, no stop needed.
- `data/raw/`, `data/work/`, `data/out/`, `data/.venv/` are already in the repo's top-level `.gitignore` (not edited, per instructions).

## 1. Whole-body volume: Visible Human Male CT

- Queried IDC (`idc-index`) for `collection_id='nlm_visible_human_project'`. VHP-M has 9 CT series across 3 studies: "Frozen" (3 series, 444+425+118 MB) and "Normal" (fresh, 2 series: 219 MB / 417 slices, and 54.7 MB / 104 slices) plus 4 tiny (<1.1MB, single-instance) localizer series.
- Per the brief's own rule ("prefer normal/fresh over frozen") and its sanity check ("slice spacing about 1mm"), picked the **Normal (fresh)** study's two series (`...1174.2` and `...1174.5`).
- **Decision, not a strict brief fallback:** inspected both series' `ImagePositionPatient`/`PatientPosition`/`FrameOfReferenceUID`. Series `1174.5` (104 slices, 8.6 mm/slice, `PatientPosition=FFS`, a *different* `FrameOfReferenceUID` than `1174.2`) overlaps `1174.2`'s z-range almost entirely rather than extending it, and its spacing is far from the brief's "about 1 mm" expectation — it reads as a coarse companion/localizer series, not a body segment to stitch on. Different frame-of-reference UIDs also make naive z-stitching across the two series unsafe (their coordinate origins are not guaranteed to agree). **Used series `1174.2` alone** (417 slices, 0.898 mm in-plane): it alone spans head to mid-thigh (see quicklook), which already satisfies the brief's "download all body-region series and stitch" intent without the risk of cross-series misalignment. Noting this for review since it's an interpretation call, not an explicit brief step.
- `1174.2`'s slice spacing is **not uniform**: median 3.0 mm, but with runs at 1.0 mm and three 6.0 mm gaps (real artifact of a 1990s multi-protocol cadaver scan). SimpleITK's `ImageSeriesReader` assumes uniform spacing and warned "Non uniform sampling or missing slices detected" — using its naive uniform-spacing volume would have geometrically distorted the regions scanned at non-median spacing. Fixed by reading all DICOM slices with `pydicom`, sorting by true `ImagePositionPatient[2]`, and linearly resampling along z onto a uniform 1.0 mm grid (`scipy.interpolate.interp1d`) before building the NIfTI. No duplicate z positions found.
- Applied `RescaleSlope`/`RescaleIntercept` (1, -1024) per slice. HU range after conversion: -1024..3071 (air/background dominates the wide FOV, consistent with a cadaver in air). Reoriented to RAS canonical via `nibabel.as_closest_canonical`.
- Result: `data/work/body_ct.nii.gz`, RAS, 512x512x956, spacing (0.898, 0.898, 1.0) mm. Quicklook confirms head, neck, thorax (lungs, heart), abdomen (liver, spine), and pelvis/hips are all in frame.

## 2. Brain volume: CQ500 / Seg-CQ500

- Downloaded `Seg-CQ500.zip` (Zenodo 8063221, 2.46 GB) directly from Zenodo (`curl -C -`, resumable, ~19 min at ~1.4 MB/s — no faster mirror offered).
- **It already bundles the matching CT** for each of its 51 labeled cases (`data/volumes/<case>/CT.nii`, already NIfTI) plus `ICH_mask.nii.gz` and a bonus `brain.nii.gz` (their own brain-parenchyma mask, not used — TotalSegmentator's own `brain.nii.gz` was used instead for consistency with the body pipeline). **Skipped qure.ai entirely per the brief** ("If the Seg-CQ500 zip already contains the matching CT, use it and skip step 3").
  - Noted for the record: `headctstudy.qure.ai` does not resolve in DNS from this sandbox (other hosts, e.g. github.com, resolve fine — this is specific to that host). Never became a blocker since Seg-CQ500 had everything needed.
- `data/volumes/info.csv` gives each case's 3-reader consensus probabilities per hemorrhage subtype (ICH/IPH/IVH/SDH/EDH/SAH) plus mass-effect/midline-shift, but no slice-spacing column, so pulled headers for 12 candidate cases directly.
- Rejected `CQ500-CT-61` (only candidate with 3mm slices, i.e. not thin-slice). All other candidates were ~0.44–0.64mm z-spacing (thin-slice, matches the brief).
- **Picked `CQ500-CT-243`**: 512x512x256, 0.482x0.482x0.628mm, single dominant subtype (SDH consensus 0.93, ICH 0.98, other subtypes ≤0.1, mass effect 0.99, midline shift 0.99) → a large, unambiguous, clearly-visible subdural hemorrhage — good for a clean demo title and a dramatic visual. ICH mask: 470k voxels ≈ 69 mL.
- **Gantry tilt, not in the brief but discovered on inspection:** `CT.nii`'s affine has a real shear between the y and z axes (a ~4° gantry tilt from the original acquisition). SimpleITK's NIfTI reader outright refuses it ("ITK only supports orthonormal direction cosines"). A4's bundle format is strictly axis-aligned (no rotation matrix), so this had to be corrected, not just reoriented: resampled with the full affine (`scipy.ndimage.affine_transform`, general linear map, not just a diagonal one) onto a proper axis-aligned RAS grid before doing anything else. Verified the ICH mask voxel count survived the resample intact (472071 → 470026, a 0.4% difference from interpolation at the mask boundary).
- Ran TotalSegmentator `-ta total --fast --device mps` (skull, brain) and `-ta body --fast --device mps` (skin/scalp) on the de-tilted `brain_ct.nii.gz` — both succeeded with model output, no fallback needed for the brain case.
- Resampled to isotropic 0.8mm, cropped to (body ∪ skull ∪ brain) mask + 4-voxel margin → 225x256x216, all ≤256 per axis (no need for the brief's 1.0mm fallback).
- Finding: computed the bleed's centroid and equivalent-sphere radius from the mask. **Fix, not in the brief but necessary:** a subdural hemorrhage is crescent-shaped (concave), so its raw geometric centroid landed just outside the mask itself (in the crescent's "hollow", inside the brain). Anchored `center_mm` at the mask voxel closest to that centroid instead, so `verify.py`'s "finding lands on its label" check passes for real, not just approximately. Title "Subdural hemorrhage" taken from CQ500's reader-consensus columns for this case (see above), per A5.

## 3. Segmentation

- Body: ran TotalSegmentator `-ta total --fast --device mps` (fast/3mm model) on `body_ct.nii.gz`. Completed in under a minute on Apple M5 Pro/MPS, producing ~90 structure masks (individual vertebrae/ribs, major organs, some named muscles: autochthon, iliopsoas, gluteus_*).
- Ran `-ta body --fast --device mps` for `skin.nii.gz`/`body.nii.gz` (whole-body mask) — succeeded.
- Attempted `-ta tissue_types` for `subcutaneous_fat`/`skeletal_muscle`: **it does not support `--fast`**, so it was re-run without `--fast`; it then reported it needs an academic license (`https://backend.totalsegmentator.com/license-academic/`). Per the brief ("If this task asks for a license, skip it and use the HU fallback below"), skipped it and used the brief's documented HU-threshold fallback for **fat** (-190..-30 HU inside the body mask, excluding skin/bone/organ) and for **muscle** (30..150 HU inside the body, excluding bone/organ/skin), unioned for muscle with TotalSegmentator's own named muscle structures from the `total` task.
- Skin: used TotalSegmentator's `body` task `skin.nii.gz` directly (model succeeded, no fallback needed).
- Bone/organs (lungs, heart, liver, spleen, kidneys, stomach, aorta) and brain: all model output from the `total` task, no fallback needed.

## 4. Bundle build

- Resampled to isotropic 2.0 mm, cropped to the body mask (from the `body` task) plus a 4-output-voxel (8mm) margin, using an axis-aligned affine resample (`scipy.ndimage.affine_transform`; CT linear, labels nearest-neighbor). No rotation needed since both grids are RAS axis-aligned.
- Merge priority per A4: painted skin, then fat, then muscle, then bone, then organs/brain (later paints win on overlap), matching "finding > brain/organ > bone > muscle > fat > skin".
- `findings.json` for the body is `[]` — the brief explicitly says not to invent body findings, and A5 confirms Body CT is a findings-free anatomy explorer.

## 5. Verify

`python data/verify.py data/out/<body|brain>` passes for both bundles: byte layout round-trips correctly from `meta.json` alone, every label id in `labels.raw` is declared in `layers.json`, and the one finding (brain) lands inside its own label. See `coordination/handoffs/L1-data.md` for the full numbers and preview review notes.

## Non-clinical demo

This is a hackathon demo built on public open-source research data (Visible Human, CQ500/Seg-CQ500). Nothing here is a diagnosis. See `data/ATTRIBUTION.md`.
