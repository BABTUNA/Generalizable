"""DEMO ONLY: run a real head-CT hemorrhage detector from the Hugging Face Hub on our head case.

Model: ianpan/ct-head-hemorrhage-detection (MIT; RSNA intracranial hemorrhage data; research
software, not a medical device). Its weights and inference code are downloaded through the
Hugging Face Hub API. It runs blind: it is never told what the dataset annotates. We then compare
its subdural heatmap against the expert Seg-CQ500 mask, as an honest check.

Writes App/Cases/head/detection.json (read offline by the app) and build/ml/ich_*.png.

Run: uv run --python 3.12 --with-requirements <model requirements.txt> python scripts/ml/ich_detect.py
"""
import json, sys, time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
REPO = "ianpan/ct-head-hemorrhage-detection"
CLASSES = ["epidural", "intraparenchymal", "intraventricular", "subarachnoid", "subdural", "any"]


def main():
    from huggingface_hub import snapshot_download
    t0 = time.time()
    local = snapshot_download(REPO)
    sys.path.insert(0, local)
    import torch
    from inference import HemorrhageSliceModel, read_nifti_volume
    import nibabel as nib

    nii = ROOT / "data/work/brain_ct.nii.gz"
    mask_nii = ROOT / "data/work/brain_bleed.nii.gz"
    volume = read_nifti_volume(str(nii))            # (D=inf->sup, H=ant->post, W=right->left), HU
    model = HemorrhageSliceModel()
    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    try:
        model = model.to(dev)
    except Exception:
        dev = "cpu"
    t1 = time.time()
    out = model.predict_hu_volume(volume, batch_size=2, return_segmentation=True)
    t2 = time.time()

    series = np.asarray(out["series_classification"], float)            # (6,)
    slices = np.asarray(out["slice_classification"], float)             # (D, 6)
    seg = out["segmentation"]                                           # (D, 6, 512, 512)
    si = CLASSES.index("subdural")
    top_slice = int(np.argmax(slices[:, si]))

    # Compare the model's subdural heatmap with the expert mask, reoriented the same way as the volume.
    mask = (read_nifti_volume(str(mask_nii)) > 0.5)
    D, H, W = volume.shape
    heat = np.asarray(seg[:, si], np.float32)                           # (D, 512, 512), centre-cropped/padded
    def crop_to(a, h, w):  # undo center_crop_or_pad of 512x512 back to (h, w)
        out = np.zeros((a.shape[0], h, w), a.dtype)
        ph, pw = (512 - h) // 2, (512 - w) // 2
        ys, xs = max(0, ph), max(0, pw)
        yd, xd = max(0, -ph), max(0, -pw)
        hh, ww = min(512, h) , min(512, w)
        out[:, yd:yd + hh, xd:xd + ww] = a[:, ys:ys + hh, xs:xs + ww]
        return out
    heat = crop_to(heat, H, W)
    pred = heat > 0.5
    inter = (pred & mask).sum()
    dice = float(2 * inter / max(1, pred.sum() + mask.sum()))
    mask_slices = np.where(mask.any(axis=(1, 2)))[0]
    record = {
        "model": REPO, "via": "Hugging Face Hub (weights + inference.py)", "device": dev,
        "blind": True, "label": "Research model, not a medical device — not a diagnosis",
        "series_probability": {c: round(float(p), 3) for c, p in zip(CLASSES, series)},
        "subdural_peak_slice_index": top_slice,
        "expert_mask_slice_range": [int(mask_slices.min()), int(mask_slices.max())] if len(mask_slices) else None,
        "peak_slice_inside_expert_range": bool(len(mask_slices) and mask_slices.min() <= top_slice <= mask_slices.max()),
        "subdural_heatmap_dice_vs_expert_mask": round(dice, 3),
        "runtime_s": {"download_and_load": round(t1 - t0, 1), "inference": round(t2 - t1, 1)},
        "slices": int(D),
    }
    (ROOT / "App/Cases/head/detection.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2))

    # Evidence image: CT at the peak slice (subdural window) with heatmap and expert contour.
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    ct = np.clip((volume[top_slice] - (75 - 107.5)) / 215, 0, 1)
    fig, ax = plt.subplots(1, 2, figsize=(8, 4.2))
    for a in ax: a.imshow(ct, cmap="gray"); a.axis("off")
    ax[1].imshow(np.ma.masked_less(heat[top_slice], 0.2), cmap="magma", alpha=0.6, vmin=0, vmax=1)
    if mask[top_slice].any(): ax[1].contour(mask[top_slice], levels=[0.5], colors="cyan", linewidths=0.8)
    ax[0].set_title(f"slice {top_slice} (subdural window)")
    ax[1].set_title(f"model heatmap (magma) vs expert mask (cyan)\nP(subdural)={series[si]:.2f}  Dice={dice:.2f}")
    (ROOT / "build/ml").mkdir(parents=True, exist_ok=True)
    fig.savefig(ROOT / "build/ml/ich_detect.png", dpi=110, bbox_inches="tight")


if __name__ == "__main__":
    main()
