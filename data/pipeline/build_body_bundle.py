import glob
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy.ndimage import binary_erosion

sys.path.insert(0, "data/work")
from bundle_common import (
    load_nii, native_spacing_origin, union_masks, largest_cc,
    resample_axis_aligned, compute_crop_grid, write_bundle,
)

CT_PATH = "data/work/body_ct.nii.gz"
TOTAL = "data/work/ts_body_total"
BODYT = "data/work/ts_body_body"
TARGET_SPACING = np.array([2.0, 2.0, 2.0])
MAX_CT_MB = 130.0

ct, affine, shape = load_nii(CT_PATH)
spacing_in, origin_in = native_spacing_origin(affine)
print("native shape", shape, "spacing", spacing_in, "origin", origin_in)

def g(pattern, base=TOTAL):
    return sorted(glob.glob(f"{base}/{pattern}"))

bone_paths = (g("skull.nii.gz") + g("sacrum.nii.gz") + g("sternum.nii.gz") +
              g("vertebrae_*.nii.gz") + g("rib_*.nii.gz") + g("clavicula_*.nii.gz") +
              g("scapula_*.nii.gz") + g("humerus_*.nii.gz") + g("hip_*.nii.gz") + g("femur_*.nii.gz"))
lung_paths = g("lung_*.nii.gz")
heart_paths = g("heart.nii.gz")
liver_paths = g("liver.nii.gz")
spleen_paths = g("spleen.nii.gz")
kidney_paths = g("kidney_left.nii.gz") + g("kidney_right.nii.gz")
stomach_paths = g("stomach.nii.gz")
aorta_paths = g("aorta.nii.gz")
brain_paths = g("brain.nii.gz")
ts_muscle_paths = (g("autochthon_left.nii.gz") + g("autochthon_right.nii.gz") +
                    g("iliopsoas_left.nii.gz") + g("iliopsoas_right.nii.gz") +
                    g("gluteus_maximus_left.nii.gz") + g("gluteus_maximus_right.nii.gz") +
                    g("gluteus_medius_left.nii.gz") + g("gluteus_medius_right.nii.gz") +
                    g("gluteus_minimus_left.nii.gz") + g("gluteus_minimus_right.nii.gz"))
skin_paths = g("skin.nii.gz", base=BODYT)
body_paths = g("body.nii.gz", base=BODYT)

print("bone parts:", len(bone_paths), "lung parts:", len(lung_paths), "ts_muscle parts:", len(ts_muscle_paths))
print("skin found:", bool(skin_paths), "body mask found:", bool(body_paths))

bone_mask = union_masks(bone_paths, shape)
lung_mask = union_masks(lung_paths, shape)
heart_mask = union_masks(heart_paths, shape)
liver_mask = union_masks(liver_paths, shape)
spleen_mask = union_masks(spleen_paths, shape)
kidney_mask = union_masks(kidney_paths, shape)
stomach_mask = union_masks(stomach_paths, shape)
aorta_mask = union_masks(aorta_paths, shape)
brain_mask = union_masks(brain_paths, shape)
ts_muscle_mask = union_masks(ts_muscle_paths, shape)

body_mask = union_masks(body_paths, shape)
if not body_mask.any():
    print("WARNING: body task mask missing, using HU fallback body mask")
    from bundle_common import body_mask_hu_fallback
    body_mask = body_mask_hu_fallback(ct)

skin_mask = union_masks(skin_paths, shape)
if not skin_mask.any():
    print("WARNING: skin.nii.gz missing, using HU fallback (body mask minus 1-voxel erosion)")
    skin_mask = body_mask & ~binary_erosion(body_mask, iterations=1)
skin_source = "TotalSegmentator body task" if union_masks(skin_paths, shape).any() else "HU fallback (body minus erosion)"

organ_bone_union = bone_mask | lung_mask | heart_mask | liver_mask | spleen_mask | kidney_mask | stomach_mask | aorta_mask | brain_mask

# HU fallback for fat (tissue_types needs a license -> skipped per brief)
fat_hu = (ct >= -190) & (ct <= -30) & body_mask & ~skin_mask & ~organ_bone_union
fat_mask = fat_hu
fat_source = "HU fallback (-190..-30 HU inside body, not skin/bone/organ) — tissue_types task needs a license, skipped per brief"

# Muscle: union of TotalSegmentator individual muscle structures + HU fallback for the rest of the body
muscle_hu = (ct >= 30) & (ct <= 150) & body_mask & ~skin_mask & ~bone_mask & ~organ_bone_union
muscle_mask = ts_muscle_mask | muscle_hu
muscle_source = "TotalSegmentator total task (autochthon/iliopsoas/gluteus) UNION HU fallback (30..150 HU, not bone/organ) for the rest"

print("mask voxel counts: skin", skin_mask.sum(), "fat", fat_mask.sum(), "muscle", muscle_mask.sum(),
      "bone", bone_mask.sum(), "brain", brain_mask.sum())

# ---- Assign label ids, paint priority: skin(1) < fat(2) < muscle(3) < bone(4) < organs(5-11) ----
LAYERS = [
    {"id": 1, "name": "Skin", "group": "skin", "color": "#E8B89C", "peel_order": 0,
     "blurb": "The outer surface of the body.", "mask": skin_mask},
    {"id": 2, "name": "Fat", "group": "fat", "color": "#F4D35E", "peel_order": 1,
     "blurb": "Subcutaneous fat beneath the skin.", "mask": fat_mask},
    {"id": 3, "name": "Muscle", "group": "muscle", "color": "#C1443C", "peel_order": 2,
     "blurb": "Skeletal muscle that moves the skeleton.", "mask": muscle_mask},
    {"id": 4, "name": "Bone", "group": "bone", "color": "#EDE6DA", "peel_order": 3,
     "blurb": "The skeleton: skull, spine, ribs, and limb bones.", "mask": bone_mask},
    {"id": 5, "name": "Lungs", "group": "organ", "color": "#A7C7E7", "peel_order": 4,
     "blurb": "The lungs, which exchange oxygen and carbon dioxide.", "mask": lung_mask},
    {"id": 6, "name": "Heart", "group": "organ", "color": "#D1495B", "peel_order": 4,
     "blurb": "The heart, which pumps blood through the body.", "mask": heart_mask},
    {"id": 7, "name": "Liver", "group": "organ", "color": "#8B5E3C", "peel_order": 4,
     "blurb": "The liver, which filters blood and aids digestion.", "mask": liver_mask},
    {"id": 8, "name": "Spleen", "group": "organ", "color": "#6B4C9A", "peel_order": 4,
     "blurb": "The spleen, part of the immune and blood-filtering system.", "mask": spleen_mask},
    {"id": 9, "name": "Kidneys", "group": "organ", "color": "#4C7A54", "peel_order": 4,
     "blurb": "The kidneys, which filter blood and produce urine.", "mask": kidney_mask},
    {"id": 10, "name": "Stomach", "group": "organ", "color": "#E8873A", "peel_order": 4,
     "blurb": "The stomach, where digestion begins.", "mask": stomach_mask},
    {"id": 11, "name": "Aorta", "group": "organ", "color": "#B22222", "peel_order": 4,
     "blurb": "The aorta, the body's main artery, standing in for blood.", "mask": aorta_mask},
    {"id": 12, "name": "Brain", "group": "brain", "color": "#F2A0C9", "peel_order": 5,
     "blurb": "The brain, visible where this scan's field of view reaches the head.", "mask": brain_mask},
]

labels_full = np.zeros(shape, dtype=np.uint8)
for layer in LAYERS:
    labels_full[layer["mask"]] = layer["id"]

present_ids = set(np.unique(labels_full).tolist())
LAYERS = [l for l in LAYERS if l["id"] in present_ids]
print("layers present after painting:", [(l["id"], l["name"]) for l in LAYERS])

# ---- crop grid from body_mask, resample to target spacing ----
def build_at_spacing(target_spacing):
    out_origin, out_dims = compute_crop_grid(body_mask, spacing_in, origin_in, target_spacing, margin_voxels=4)
    out_dims = tuple(int(d) for d in out_dims)
    print("target_spacing", target_spacing, "-> out_dims", out_dims, "out_origin", out_origin)
    ct_out = resample_axis_aligned(ct, spacing_in, origin_in, target_spacing, out_origin, out_dims, order=1)
    ct_out = np.clip(ct_out, -1024, 3071).astype(np.int16)
    labels_out = resample_axis_aligned(labels_full.astype(np.float32), spacing_in, origin_in,
                                        target_spacing, out_origin, out_dims, order=0)
    labels_out = np.round(labels_out).astype(np.uint8)
    return ct_out, labels_out, out_dims, out_origin

target_spacing = TARGET_SPACING.copy()
ct_out, labels_out, out_dims, out_origin = build_at_spacing(target_spacing)
size_mb = ct_out.nbytes / 1e6
print(f"at spacing {target_spacing}: ct.raw would be {size_mb:.1f} MB")
if size_mb > MAX_CT_MB:
    target_spacing = np.array([2.5, 2.5, 2.5])
    print("over budget, retrying at 2.5mm")
    ct_out, labels_out, out_dims, out_origin = build_at_spacing(target_spacing)
    size_mb = ct_out.nbytes / 1e6
    print(f"at spacing {target_spacing}: ct.raw is {size_mb:.1f} MB")

window_presets = {"soft": [40, 400], "bone": [500, 2000], "brain": [40, 80], "lung": [-600, 1500]}
source = ("NLM Visible Human Project, VHP-M (male), Normal (fresh) whole-body CT series "
          "1.3.6.1.4.1.5962.1.3.1174.2.1672334394.26545, via NCI Imaging Data Commons "
          "collection nlm_visible_human_project")
license_ = "NLM Terms and Conditions (2019), no license agreement required"

layers_json = [{k: v for k, v in l.items() if k != "mask"} for l in LAYERS]
findings_json = []  # Body CT has no findings per A5 -- do not invent any

write_bundle(
    "data/out/body", ct_out, labels_out, out_dims, target_spacing, out_origin,
    window_presets, source, license_, layers_json, findings_json,
)

print("SKIN_SOURCE:", skin_source)
print("FAT_SOURCE:", fat_source)
print("MUSCLE_SOURCE:", muscle_source)
print("DONE build_body_bundle")
