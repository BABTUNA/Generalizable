# Data pipeline brief (lane L1)

> **DEMO ONLY.** This is Daniel's brief, kept verbatim below the overrides; it still uses the project's old name, Layer Lens. The Commander added these overrides:
> - Use Python **3.12** via `uv` (`uv venv --python 3.12 data/.venv`). The system Python is 3.14, which torch/TotalSegmentator may not support.
> - The whole demo has **3 hours**, so this lane gets at most ~100 minutes. Take fallbacks early.
> - Skip section 6 (cryosections) entirely.
> - Report through `coordination/handoffs/L1-data.md` using the template in `docs/ORCHESTRATION.md`, as well as the final report the brief asks for.
> - The bundle format is PRD addendum A4 (which is this brief's section 4).

---

You are setting up the data for **Layer Lens**, an iPhone Duo (iOS Simulator) hackathon app. The app shows a CT scan as named layers you peel away (skin, fat, muscle, bone, organs, brain), and the phone's hinge angle sets a tilted cutting plane through the volume. A Metal shader samples a 3D texture, so what I need from you is **two small, preprocessed 3D volumes plus label maps and JSON metadata**. Do not write any app or Swift code. Your job is download, convert, segment, verify, report.

Hard deadline: the demo is at 6 PM today. Your whole job should finish in about 90 minutes. Favor speed and a working result over completeness. If a step stalls for more than 10 minutes, take the fallback listed for it and tell me.

## 0. Setup

- Work in `./data/` inside the current directory. Layout:
  ```
  data/
    raw/            # untouched downloads (gitignored)
    work/           # intermediate NIfTI, TotalSegmentator output (gitignored)
    out/body/       # final bundle for the whole-body volume
    out/brain/      # final bundle for the brain volume
    previews/       # PNG sanity checks
    ATTRIBUTION.md
    PIPELINE_LOG.md # what you did, commands run, decisions, sizes
  ```
- Add `data/raw/` and `data/work/` to `.gitignore`.
- Check free disk space first (`df -h .`). Need about 25 GB free. If less, stop and tell me.
- Use a Python venv at `./data/.venv`. Install: `idc-index nibabel SimpleITK numpy scipy pydicom dicom2nifti matplotlib TotalSegmentator`. Also `pip install torch` if TotalSegmentator does not pull it. This is an Apple Silicon Mac, so TotalSegmentator should run with `--device mps`.
- Run long downloads in the background with resume support (`curl -C -` or `wget -c`), and start the downloads in sections 1 and 2 at the same time so they overlap.
- Log every command and decision to `PIPELINE_LOG.md` as you go.

## 1. Whole-body volume: Visible Human Male CT

Source: NLM Visible Human Project, mirrored as DICOM in NCI Imaging Data Commons (IDC), collection id `nlm_visible_human_project`. No license agreement needed (NLM Terms and Conditions, 2019). Reference: https://zenodo.org/records/12690050 and https://www.nlm.nih.gov/research/visible/getting_data.html

Steps:
1. Query IDC with `idc-index`:
   ```python
   from idc_index import IDCClient
   c = IDCClient()
   df = c.sql_query("""
     SELECT PatientID, Modality, SeriesInstanceUID, SeriesDescription, series_size_MB
     FROM index WHERE collection_id = 'nlm_visible_human_project'
   """)
   ```
   Print the full table. Pick the **male, CT** series. If there is both a "normal/fresh" CT and a "frozen" CT, prefer the normal/fresh one. If the body is split into several CT series (head, thorax, abdomen, pelvis, legs), download all of them for the male and stitch by slice position.
2. Download only the chosen CT series with `c.download_from_selection(seriesInstanceUID=[...], downloadDir="data/raw/vhp_male_ct")`. Do **not** download the color cryosection series yet (they are huge).
3. Convert to a single NIfTI in `data/work/body_ct.nii.gz`. Check slice spacing is about 1 mm, check for missing slices or duplicate positions, and fix ordering. Reorient to canonical RAS (`nibabel.as_closest_canonical`).
4. Sanity check HU: air near -1000, soft tissue 0 to 80, bone above 300. If values look offset (for example no negatives), find the rescale slope/intercept and correct. Note it in the log.

Fallback if IDC fails or the CT series is not there: use one case from the TotalSegmentator dataset v2.0.1 small subset (CC BY 4.0, https://zenodo.org/records/10047292). Pick the case with the largest z-extent that includes the head. Tell me you switched.

## 2. Brain volume: CQ500 case with a Seg-CQ500 bleed mask

Sources:
- Seg-CQ500 (voxel hemorrhage masks for 51 CQ500 scans), CC BY 4.0: https://zenodo.org/records/8063221 (single zip, about 2.5 GB)
- CQ500 head CTs (491 scans, DICOM), CC BY-NC-SA 4.0: http://headctstudy.qure.ai/dataset (per-scan downloads; also on Academic Torrents)

Steps:
1. Download Seg-CQ500 first. Inspect it: which CQ500 case IDs have masks, whether the zip includes the CT images or masks only, and the mask format.
2. From those cases, pick **one** that has (a) a thin-slice series, about 0.625 mm, not only 5 mm, and (b) a clearly visible bleed of decent size. If the Seg-CQ500 zip already contains the matching CT, use it and skip step 3.
3. Otherwise download only that one CQ500 scan from the qure.ai page. Do not download the full CQ500 set.
4. Convert the thin-slice series to `data/work/brain_ct.nii.gz`, RAS canonical. Make sure the bleed mask is on the same grid (resample the mask with nearest neighbor if needed). Save it as `data/work/brain_bleed.nii.gz`.

Fallback: if no masked case has thin slices, take the thinnest one available and tell me the spacing. If Seg-CQ500 is unusable, take any CQ500 scan whose `reads.csv` shows an intracranial hemorrhage from all three readers and skip the mask; the finding becomes a hand-placed point.

## 3. Segmentation (layers)

Run TotalSegmentator on both volumes with `--device mps`. Use `--fast` for the body if full resolution is too slow (over 15 minutes).

Body (`data/work/body_ct.nii.gz`):
- `-ta total` → keep: skull, brain, all vertebrae (merge to "spine"), ribs (merge), sternum, clavicles, scapulae, humeri, hips, femurs, sacrum, plus major organs: lungs (merge left/right), heart, liver, spleen, kidneys (merge), stomach, aorta.
- `-ta body` → skin.
- `-ta tissue_types` → subcutaneous_fat, skeletal_muscle. If this task asks for a license, skip it and use the HU fallback below.

Brain (`data/work/brain_ct.nii.gz`):
- `-ta total` → skull, brain.
- `-ta body` → skin (scalp).
- Add the bleed mask from Seg-CQ500.
- Do not use `brain_structures` (needs a license request).

HU fallback, use for any layer that failed (it is a 1990s cadaver scan, so expect some misses):
- body mask: HU > -500, keep the largest connected component, fill holes slice by slice
- skin: body mask minus a 1-voxel erosion (at the final 2 mm grid)
- bone: HU > 250 inside the body
- fat: HU between -190 and -30 inside the body, not skin
- muscle: HU between 30 and 150 inside the body, not bone, not an organ

Visually check a few masks per layer in the previews (section 5) before trusting them. Cadaver CT can confuse the model, especially at the gut and brain.

## 4. Build the app bundles

For each of `out/body/` and `out/brain/` produce exactly these files:

- `ct.raw`: signed int16 HU, little endian, **x fastest, then y, then z**, z increasing toward the head. No header.
- `labels.raw`: uint8 label IDs, same grid and ordering. 0 = background.
- `meta.json`:
  ```json
  { "dims": [x, y, z], "spacing_mm": [sx, sy, sz], "origin_mm": [ox, oy, oz],
    "orientation": "RAS", "ct_dtype": "int16_le_HU", "labels_dtype": "uint8",
    "window_presets": { "soft": [40, 400], "bone": [500, 2000], "brain": [40, 80], "lung": [-600, 1500] },
    "source": "...", "license": "..." }
  ```
- `layers.json`: array ordered outside to inside, each item
  `{ "id": 1, "name": "Skin", "group": "skin|fat|muscle|bone|organ|brain|finding", "color": "#RRGGBB", "peel_order": 0, "blurb": "one plain-language sentence" }`.
  Keep blurbs factual and simple (what the structure is, not diagnoses). Use a clear, distinct palette. Skin warm beige, fat yellow, muscle red, bone off-white, organs varied, bleed bright magenta.
- `findings.json`: array of `{ "id": ..., "label_id": ..., "title": ..., "center_mm": [x,y,z], "radius_mm": r, "explanation": "..." }`. For the brain, compute the bleed's centroid and equivalent radius from the mask, and set the title to the hemorrhage type from CQ500's reads if available. The body has no real findings: leave its findings array empty and say so in the log. Do not invent findings.

Resampling:
- **Body:** isotropic **2.0 mm**, cropped tightly to the body mask plus 4 voxels margin. Target under ~130 MB for `ct.raw`. If bigger, go to 2.5 mm.
- **Brain:** isotropic **0.8 mm**, cropped to the head plus margin, max 256 per axis. If bigger, go to 1.0 mm.
- CT with linear interpolation, labels with nearest neighbor.
- Label merge priority when masks overlap: finding > brain/organ > bone > muscle > fat > skin.

## 5. Verify

Write `data/verify.py` and run it. For each bundle:
- Reload `ct.raw` and `labels.raw` from bytes using only `meta.json`, to prove the layout is right.
- Print dims, spacing, file sizes, HU min/max/percentiles, and voxel count + volume (mL) per label.
- Check every label ID in `labels.raw` exists in `layers.json`, and every finding's `center_mm` lands inside its label.
- Save PNGs to `data/previews/`: mid axial, mid coronal, mid sagittal, each as plain CT and with a colored label overlay. Also one **oblique slice tilted 60 degrees** through the brain finding (or the body center), sampled with trilinear interpolation, to prove the tilted-plane idea works on this data.
- Look at the PNGs yourself. If a layer is clearly wrong (for example skin inside the body, bone missing, labels flipped vs CT), fix it before finishing.

## 6. Optional — SKIPPED for the 3-hour demo (Commander override)

## 7. Attribution and report

`data/ATTRIBUTION.md`: list each dataset with its license and citation.
- Visible Human Project: U.S. National Library of Medicine, NLM Terms and Conditions (2019).
- CQ500: Chilamkurthy et al., Lancet 2018, CC BY-NC-SA 4.0.
- Seg-CQ500: Zenodo 8063221, CC BY 4.0.
- TotalSegmentator: Wasserthal et al., Radiology: AI 2023, tool Apache-2.0.
- If the fallback was used, the TotalSegmentator dataset, CC BY 4.0.

Add one line that this is a non-clinical demo.

When done, reply with a short report:
- final file list with sizes for `out/body/` and `out/brain/`
- which sources and series you actually used, and any fallbacks taken
- per-layer status: model vs HU fallback, and any layer that looks bad
- the brain finding (type, size, location)
- total wall time
- anything I must know before loading these in Metal (axis order, orientation quirks)

Rules: do not download anything not listed here. Do not download full datasets when a single series or case is enough. Do not delete anything outside `data/`. If a site needs a login, a license click-through, or a CAPTCHA, stop and tell me instead of working around it.
