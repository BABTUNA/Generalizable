"""Run ianpan/ct-head-hemorrhage-detection on a bundled head case and export it for the iOS app.

DEMO ONLY. Research model (MIT, trained on RSNA ICH data), not a medical device, not a diagnosis.

Prior art followed:
  - scripts/ml/ich_detect.py (this repo): same model, same calls
    (HemorrhageSliceModel().predict_hu_volume(volume, batch_size=2, return_segmentation=True),
    read_nifti_volume), same subdural-window evidence image.
  - Model repo inference.py (huggingface.co/ianpan/ct-head-hemorrhage-detection, revision
    e6d89c253fdcc2a597dd0fd0f5771821f4947b37, file inference.py):
      * read_nifti_volume(): reorients the NIfTI to LPS by nearest-axis permute/flip
        (nib.orientations.ornt_transform(src, LPS) + apply_orientation), then transpose(2,1,0)
        -> model volume is (D=S, H=P, W=L).
      * window_hu_slice(): for H,W <= 640 it centre-crops to 512 and zero-pads centred
        (pad//2 before, remainder after); for H or W > 640 it resizes to 512x512 (not supported here).
      * SegmentationHead upsamples to (512, 512) (skp/models/segmentation/base.py), so
        out["segmentation"] is (D, 6, 512, 512) sigmoid probabilities, mean of 5 folds.
      * HemorrhageSliceModel(device=...) takes the device in the constructor (it has no .to()).
  This script inverts exactly those steps so the heatmap lands voxel-for-voxel on ct.nii.gz.

Writes into the case folder: ai.json, ai_heatmap.nii.gz (uint8, round(255*p_headline)), ai_preview.png.

Run (Python 3.12):
  uv venv --python 3.12 .venv && uv pip install -r <model>/requirements.txt nibabel matplotlib
  HF_HOME=<scratch>/hf .venv/bin/python ios/tools/ml/run_ich_model.py [case_dir]
"""
import json
import os
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
REPO = "ianpan/ct-head-hemorrhage-detection"
CLASSES = ["epidural", "intraparenchymal", "intraventricular", "subarachnoid", "subdural", "any"]
BLEED_LABEL = 39  # Seg-CQ500 expert bleed mask in combined_labels.nii.gz


def model_to_source(vol_dhw, src_ornt):
    """Invert read_nifti_volume: (D,H,W) LPS-ordered array -> original NIfTI voxel grid."""
    import nibabel as nib
    lps = vol_dhw.transpose(2, 1, 0)
    back = nib.orientations.ornt_transform(nib.orientations.axcodes2ornt(("L", "P", "S")), src_ornt)
    return nib.orientations.apply_orientation(lps, back)


def uncrop_pad(a, h, w, size=512):
    """Invert window_hu_slice's centre crop + centred zero pad for (.., 512, 512) -> (.., h, w)."""
    if max(h, w) > 640:
        raise NotImplementedError("model resizes >640px slices; not needed for our cases")
    out = np.zeros(a.shape[:-2] + (h, w), a.dtype)
    # forward: crop offset (top/left) when larger than 512, then pad (pad//2 before) when smaller
    top, left = max((h - size) // 2, 0), max((w - size) // 2, 0)
    ch, cw = min(h, size), min(w, size)
    ph, pw = (size - ch) // 2, (size - cw) // 2
    out[..., top:top + ch, left:left + cw] = a[..., ph:ph + ch, pw:pw + cw]
    return out


def main():
    case = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "ios/Generalizable/Resources/Cases/CQ500_CT_243"
    import nibabel as nib
    import torch
    from huggingface_hub import snapshot_download

    t0 = time.time()
    local = snapshot_download(REPO)
    sys.path.insert(0, local)
    from inference import HemorrhageSliceModel, read_nifti_volume

    ct_path, lab_path = case / "ct.nii.gz", case / "combined_labels.nii.gz"
    ct_img = nib.load(str(ct_path))
    src_ornt = nib.orientations.io_orientation(ct_img.affine)
    volume = read_nifti_volume(str(ct_path))  # (D, H, W) in LPS order
    D, H, W = volume.shape
    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    model = HemorrhageSliceModel(device=dev, local_dir=local)

    cache = os.environ.get("ICH_CACHE")  # optional npz to skip re-inference while iterating
    t1 = time.time()
    if cache and Path(cache).exists():
        z = np.load(cache)
        series, slices, seg_all = z["series"], z["slices"], z["seg"]
    else:
        out = model.predict_hu_volume(volume, batch_size=2, return_segmentation=True)
        series = np.asarray(out["series_classification"], np.float32)       # (6,)
        slices = np.asarray(out["slice_classification"], np.float32)        # (D, 6)
        seg_all = np.asarray(out["segmentation"], np.float16)               # (D, 6, 512, 512)
        if cache:
            np.savez(cache, series=series, slices=slices, seg=seg_all)
    t2 = time.time()

    # Headline = highest series probability among the 5 subtypes (not "any").
    hi = int(np.argmax(series[:5]))
    headline = CLASSES[hi]

    heat = uncrop_pad(seg_all[:, hi].astype(np.float32), H, W)             # (D, H, W)
    heat_src = model_to_source(heat, src_ornt)                               # NIfTI grid
    assert heat_src.shape == ct_img.shape, (heat_src.shape, ct_img.shape)
    heat_u8 = np.clip(np.rint(heat_src * 255), 0, 255).astype(np.uint8)

    # Slice probabilities: map model depth index -> source voxel index along the S axis.
    didx = np.broadcast_to(np.arange(D, dtype=np.int16)[:, None, None], (D, H, W))
    didx_src = model_to_source(np.ascontiguousarray(didx), src_ornt)
    s_axis = int(np.where(src_ornt[:, 0] == 2)[0][0])                      # voxel axis closest to S
    order = np.moveaxis(didx_src, s_axis, -1)[0, 0, :]                     # model d for each source k
    slice_prob = slices[order, hi].astype(float)
    nz = ct_img.shape[s_axis]
    assert len(slice_prob) == nz

    hdr = ct_img.header.copy()
    hdr.set_data_dtype(np.uint8)
    hdr["scl_slope"], hdr["scl_inter"] = 1.0, 0.0
    heat_img = nib.Nifti1Image(heat_u8, ct_img.affine, hdr)
    heat_img.set_qform(ct_img.get_qform(), int(ct_img.header["qform_code"]))
    heat_img.set_sform(ct_img.get_sform(), int(ct_img.header["sform_code"]))
    nib.save(heat_img, str(case / "ai_heatmap.nii.gz"))

    # Alignment check vs expert mask.
    labels = np.asarray(nib.load(str(lab_path)).dataobj)
    mask = labels == BLEED_LABEL
    pred = heat_u8 > 127
    dice = float(2 * (pred & mask).sum() / max(1, pred.sum() + mask.sum())) if mask.any() else None
    cen = lambda m: np.round(np.argwhere(m).mean(0), 1).tolist() if m.any() else None
    wcen = np.round((np.argwhere(heat_u8 > 0) * heat_u8[heat_u8 > 0][:, None]).sum(0) / heat_u8.sum(), 1).tolist()
    print(f"headline={headline} dice={dice} pred_vox={int(pred.sum())} mask_vox={int(mask.sum())}")
    print(f"centroid (i,j,k) heatmap>127={cen(pred)} heat-weighted={wcen} expert={cen(mask)}")

    peak = int(np.argmax(slice_prob))
    record = {
        "model": REPO,
        "license": "MIT",
        "disclaimer": "Research model, not a medical device. Not a diagnosis.",
        "headlineClass": headline,
        "series": [{"name": c, "probability": round(float(p), 4)} for c, p in zip(CLASSES, series)],
        "sliceProbability": [round(float(p), 4) for p in slice_prob],
        "diceVsExpert": None if dice is None else round(dice, 3),
        "runtimeSeconds": round(t2 - t1, 1),
        "device": dev,
    }
    (case / "ai.json").write_text(json.dumps(record) + "\n")
    print(json.dumps({k: v for k, v in record.items() if k != "sliceProbability"}, indent=1))
    print(f"peak slice k={peak} p={slice_prob[peak]:.3f}; expert k-range="
          f"{[int(x) for x in np.where(mask.any((0, 1)))[0][[0, -1]]] if mask.any() else None}")

    # Evidence image (radiological display: patient right on screen left, anterior up). RAS assumed.
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    ct = np.asarray(ct_img.dataobj, np.float32)
    disp = lambda a: a[::-1, ::-1, peak].T
    ctw = np.clip((disp(ct) - (80 - 100)) / 200, 0, 1)
    fig, ax = plt.subplots(1, 2, figsize=(9, 5))
    for a in ax:
        a.imshow(ctw, cmap="gray")
        a.axis("off")
    ax[1].imshow(np.ma.masked_less(disp(heat_u8) / 255.0, 0.15), cmap="hot", alpha=0.6, vmin=0, vmax=1)
    if disp(mask).any():
        ax[1].contour(disp(mask), levels=[0.5], colors="cyan", linewidths=0.8)
    ax[0].set_title(f"CQ500 slice k={peak} (W200 L80)")
    ax[1].set_title(f"{headline} heatmap (hot) vs expert (cyan)\n"
                    f"P={series[hi]:.3f}  slice p={slice_prob[peak]:.2f}  Dice={dice if dice is None else round(dice, 3)}")
    fig.savefig(case / "ai_preview.png", dpi=110, bbox_inches="tight")
    print("wrote", case / "ai.json", case / "ai_heatmap.nii.gz", case / "ai_preview.png")


if __name__ == "__main__":
    main()
