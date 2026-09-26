"""Build the data/out/brain A4 bundle from brain_ct.nii.gz + brain_bleed.nii.gz +
TotalSegmentator total/body task output. Filled in after Seg-CQ500 inspection
determines the exact case and finding metadata (title, center_mm, radius_mm).
Placeholder to be completed once the CQ500 case is selected.
"""
import glob
import sys
import json

import numpy as np

sys.path.insert(0, "data/work")
from bundle_common import (
    load_nii, load_mask, native_spacing_origin, union_masks,
    resample_axis_aligned, compute_crop_grid, write_bundle,
)

CT_PATH = "data/work/brain_ct.nii.gz"
BLEED_PATH = "data/work/brain_bleed.nii.gz"
TOTAL = "data/work/ts_brain_total"
BODYT = "data/work/ts_brain_body"
TARGET_SPACING = np.array([0.8, 0.8, 0.8])
MAX_DIM = 256

ct, affine, shape = load_nii(CT_PATH)
spacing_in, origin_in = native_spacing_origin(affine)
print("native shape", shape, "spacing", spacing_in, "origin", origin_in)


def g(pattern, base=TOTAL):
    return sorted(glob.glob(f"{base}/{pattern}"))


skull_mask = union_masks(g("skull.nii.gz"), shape)
brain_mask = union_masks(g("brain.nii.gz"), shape)
skin_paths = g("skin.nii.gz", base=BODYT)
body_paths = g("body.nii.gz", base=BODYT)
skin_mask = union_masks(skin_paths, shape)
body_mask = union_masks(body_paths, shape)
if not body_mask.any():
    from bundle_common import body_mask_hu_fallback
    body_mask = body_mask_hu_fallback(ct)
if not skin_mask.any():
    from scipy.ndimage import binary_erosion
    skin_mask = body_mask & ~binary_erosion(body_mask, iterations=1)

bleed_mask = load_mask(BLEED_PATH, shape) if __import__("pathlib").Path(BLEED_PATH).exists() else np.zeros(shape, dtype=bool)

LAYERS = [
    {"id": 1, "name": "Skin", "group": "skin", "color": "#E8B89C", "peel_order": 0,
     "blurb": "The scalp, the outer surface of the head.", "mask": skin_mask},
    {"id": 2, "name": "Skull", "group": "bone", "color": "#EDE6DA", "peel_order": 1,
     "blurb": "The skull, which protects the brain.", "mask": skull_mask},
    {"id": 3, "name": "Brain", "group": "brain", "color": "#C9A7E8", "peel_order": 2,
     "blurb": "Brain tissue.", "mask": brain_mask & ~bleed_mask},
    {"id": 4, "name": "Bleed", "group": "finding", "color": "#FF00AA", "peel_order": 3,
     "blurb": "An intracranial hemorrhage identified in this scan.", "mask": bleed_mask},
]

labels_full = np.zeros(shape, dtype=np.uint8)
# priority: finding > brain > bone > skin (skip fat/muscle -- not segmented for head; brief §3 doesn't ask for them)
for layer in sorted(LAYERS, key=lambda l: l["peel_order"]):
    labels_full[layer["mask"]] = layer["id"]

present_ids = set(np.unique(labels_full).tolist())
LAYERS = [l for l in LAYERS if l["id"] in present_ids]
print("layers present:", [(l["id"], l["name"]) for l in LAYERS])

crop_mask = body_mask | skull_mask | brain_mask
out_origin, out_dims = compute_crop_grid(crop_mask, spacing_in, origin_in, TARGET_SPACING, margin_voxels=4)
out_dims = np.minimum(out_dims, MAX_DIM)
out_dims = tuple(int(d) for d in out_dims)
print("out_dims", out_dims, "out_origin", out_origin)

ct_out = resample_axis_aligned(ct, spacing_in, origin_in, TARGET_SPACING, out_origin, out_dims, order=1)
ct_out = np.clip(ct_out, -1024, 3071).astype(np.int16)
labels_out = resample_axis_aligned(labels_full.astype(np.float32), spacing_in, origin_in,
                                    TARGET_SPACING, out_origin, out_dims, order=0)
labels_out = np.round(labels_out).astype(np.uint8)

size_mb = ct_out.nbytes / 1e6
print(f"ct.raw would be {size_mb:.1f} MB at spacing {TARGET_SPACING}")
if max(out_dims) > MAX_DIM:
    print("resizing to 1.0mm per brief's fallback rule")
    TARGET_SPACING = np.array([1.0, 1.0, 1.0])
    out_origin, out_dims = compute_crop_grid(crop_mask, spacing_in, origin_in, TARGET_SPACING, margin_voxels=4)
    out_dims = np.minimum(out_dims, MAX_DIM)
    out_dims = tuple(int(d) for d in out_dims)
    ct_out = resample_axis_aligned(ct, spacing_in, origin_in, TARGET_SPACING, out_origin, out_dims, order=1)
    ct_out = np.clip(ct_out, -1024, 3071).astype(np.int16)
    labels_out = resample_axis_aligned(labels_full.astype(np.float32), spacing_in, origin_in,
                                        TARGET_SPACING, out_origin, out_dims, order=0)
    labels_out = np.round(labels_out).astype(np.uint8)

# ---- finding: centroid + equivalent radius of the bleed mask, in the OUTPUT grid ----
findings_json = []
bleed_id = next((l["id"] for l in LAYERS if l["name"] == "Bleed"), None)
if bleed_id is not None:
    idx = np.argwhere(labels_out == bleed_id)
    if idx.size:
        centroid_ijk = idx.mean(axis=0)
        # A subdural bleed is crescent-shaped (concave), so its geometric centroid can
        # fall outside the mask itself (in the "hollow" of the crescent). Anchor the
        # finding at the mask voxel closest to that centroid instead, so center_mm is
        # always guaranteed to land inside label_id.
        dists = np.sum((idx - centroid_ijk) ** 2, axis=1)
        anchor_ijk = idx[np.argmin(dists)]
        center_mm = (np.array(out_origin) + anchor_ijk * TARGET_SPACING).tolist()
        n_vox = idx.shape[0]
        voxel_vol_mm3 = float(np.prod(TARGET_SPACING))
        vol_mm3 = n_vox * voxel_vol_mm3
        radius_mm = float((3 * vol_mm3 / (4 * np.pi)) ** (1 / 3))
        # CQ500-CT-243's 3-reader consensus (info.csv): SDH 0.93 dominant (ICH 0.98,
        # mass effect 0.99, midline shift 0.99; other subtypes low) -> subdural hemorrhage.
        findings_json.append({
            "id": 1, "label_id": bleed_id, "title": "Subdural hemorrhage",
            "center_mm": center_mm, "radius_mm": round(radius_mm, 1),
            "explanation": ("A subdural hemorrhage (bleeding between the brain and the skull), "
                             "voxel-masked by Seg-CQ500. CQ500's three-reader consensus for this "
                             "case (CQ500-CT-243) rates subdural hemorrhage at 0.93 and associated "
                             "mass effect / midline shift at 0.99."),
        })
        print("finding:", findings_json[0])
    else:
        print("WARNING: bleed_id present in LAYERS but no voxels in cropped/resampled output")

window_presets = {"soft": [40, 400], "bone": [500, 2000], "brain": [40, 80], "lung": [-600, 1500]}
source = ("CQ500-CT-243 (qure.ai CQ500 head CT dataset), thin-slice (0.628mm) series, "
          "with the Seg-CQ500 intracranial hemorrhage mask for this case")
license_ = "CQ500: CC BY-NC-SA 4.0 (Chilamkurthy et al., Lancet 2018); Seg-CQ500 mask: CC BY 4.0 (Zenodo 8063221)"

layers_json = [{k: v for k, v in l.items() if k != "mask"} for l in LAYERS]

write_bundle(
    "data/out/brain", ct_out, labels_out, out_dims, TARGET_SPACING, out_origin,
    window_presets, source, license_, layers_json, findings_json,
)
print("DONE build_brain_bundle")
