#!/usr/bin/env python
"""
clean_labels.py -- L4-viz-reference

Cleans the salt-and-pepper fat/muscle speckle in an A4 body bundle
(data/out/body/*.raw, see docs/PRD.md addendum A4) and adds real organ
labels from TotalSegmentator where the pipeline's HU-threshold fallback
left the bowel region unlabeled or speckled.

Run with:
  uv run --python 3.12 --with numpy --with scipy --with matplotlib --with nibabel \
      python scripts/viz/clean_labels.py <bundle_dir> <work_dir> <out_dir>

<out_dir> must NOT be under data/out (that tree belongs to lane L1).
"""
import argparse
import glob
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from scipy.ndimage import uniform_filter, affine_transform, label as cc_label

FAT_ID = 2
MUSCLE_ID = 3
SPECKLE_IDS = (FAT_ID, MUSCLE_ID)

# New organ ids, allocated at 13+ per the task (ids 1-12 are taken by layers.json).
EXTRA_ORGANS = [
    {"id": 13, "name": "Intestines", "group": "organ", "color": "#B98D63", "peel_order": 4,
     "blurb": "The intestines, where digestion continues after the stomach.",
     "sources": ["colon.nii.gz", "small_bowel.nii.gz", "duodenum.nii.gz", "esophagus.nii.gz"]},
    {"id": 14, "name": "Pancreas", "group": "organ", "color": "#D9A441", "peel_order": 4,
     "blurb": "The pancreas, which aids digestion and regulates blood sugar.",
     "sources": ["pancreas.nii.gz"]},
    {"id": 15, "name": "Gallbladder", "group": "organ", "color": "#5B8C5A", "peel_order": 4,
     "blurb": "The gallbladder, which stores bile made by the liver.",
     "sources": ["gallbladder.nii.gz"]},
    {"id": 16, "name": "Bladder", "group": "organ", "color": "#E0C34C", "peel_order": 4,
     "blurb": "The bladder, which stores urine.",
     "sources": ["urinary_bladder.nii.gz"]},
]


def count_small_components(labels, ids=SPECKLE_IDS, max_voxels=5):
    """Count connected components (26-connectivity) of `ids` voxels smaller than
    `max_voxels`. This is the speckle metric."""
    mask = np.isin(labels, ids)
    structure = np.ones((3, 3, 3), dtype=bool)
    lab, n = cc_label(mask, structure=structure)
    if n == 0:
        return 0
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0  # background
    return int(np.sum((sizes > 0) & (sizes < max_voxels)))


def majority_filter_3x3x3(labels):
    """For every voxel, find the most common label in its 3x3x3 (26-neighbour + self)
    neighbourhood. Implemented as one separable box-sum per distinct label id present
    (cheap: O(num_ids) uniform_filter passes) rather than a per-voxel Python callback,
    which would be far too slow at ~20M voxels."""
    ids = np.unique(labels)
    counts = np.empty((len(ids),) + labels.shape, dtype=np.float32)
    for i, lid in enumerate(ids):
        counts[i] = uniform_filter((labels == lid).astype(np.float32), size=3, mode="nearest")
    best = np.argmax(counts, axis=0)
    return ids[best].astype(labels.dtype)


def clean_speckle(labels, iterations=3):
    """3x3x3 majority filter restricted to fat/muscle voxels: only voxels currently
    labeled fat or muscle are candidates for relabeling, and they take on whichever
    label (including background, or a neighbouring organ/bone) is most common in
    their neighbourhood. Voxels of every other label are left untouched.

    One pass only dissolves speckle whose 3x3x3 neighbourhood already has a clear
    non-speckle majority; a fat/muscle checkerboard region needs the boundary to
    move inward repeatedly, so this iterates. Measured on the body bundle: fat/
    muscle connected components under 5 voxels go 1515 -> 1422 (1 pass) -> 429
    (2 passes) -> 217 (3 passes) -> 150 (4 passes), each pass ~1-2s; 3 passes is
    the point of diminishing returns used here."""
    out = labels
    for _ in range(iterations):
        majority = majority_filter_3x3x3(out)
        speckle_mask = np.isin(out, SPECKLE_IDS)
        out = out.copy()
        out[speckle_mask] = majority[speckle_mask]
    return out


def _mm_grid_to_native_voxel_offset(spacing_mm, origin_mm, native_spacing, native_origin):
    scale = np.array(spacing_mm) / np.array(native_spacing)
    offset = (np.array(origin_mm) - np.array(native_origin)) / np.array(native_spacing)
    return scale, offset


def resample_mask_nn(nii_path, dims, spacing_mm, origin_mm):
    """Resample a TotalSegmentator mask (its own NIfTI grid/affine) onto the bundle's
    axis-aligned RAS grid (meta.json's origin_mm + 2mm spacing) with nearest-neighbor.
    Mirrors data/work/bundle_common.py's resample_axis_aligned, but for a boolean mask
    read straight off disk (no float64 upcast)."""
    import nibabel as nib

    img = nib.load(nii_path)
    affine = img.affine
    native_spacing = np.abs(np.diag(affine)[:3])
    native_origin = affine[:3, 3]
    mask = (np.asarray(img.dataobj) > 0.5).astype(np.float32)

    scale, offset = _mm_grid_to_native_voxel_offset(spacing_mm, origin_mm, native_spacing, native_origin)
    matrix = np.diag(scale)
    out = affine_transform(
        mask, matrix, offset=offset, output_shape=dims, order=0,
        mode="constant", cval=0.0, prefilter=False,
    )
    return out > 0.5


def add_ts_organs(labels, meta, work_dir):
    """Adds Intestines/Pancreas/Gallbladder/Bladder from TotalSegmentator's
    ts_body_total output, if present, resampled onto the bundle grid. Returns
    (labels, extra_layers_actually_added)."""
    total_dir = Path(work_dir) / "ts_body_total"
    if not total_dir.is_dir():
        return labels, []

    dims = tuple(meta["dims"])
    spacing_mm = meta["spacing_mm"]
    origin_mm = meta["origin_mm"]

    out = labels.copy()
    added = []
    for organ in EXTRA_ORGANS:
        union = np.zeros(dims, dtype=bool)
        found_any = False
        for src in organ["sources"]:
            path = total_dir / src
            if path.exists():
                found_any = True
                union |= resample_mask_nn(str(path), dims, spacing_mm, origin_mm)
        if not found_any or not union.any():
            continue
        out[union] = organ["id"]
        added.append({k: v for k, v in organ.items() if k != "sources"})
    return out, added


def clean(labels, ct, meta, work_dir):
    """Public entry point.

    labels: uint8 ndarray, shape meta['dims'] (x,y,z), x fastest per A4.
    ct:     int16 ndarray, same shape (unused by cleaning itself; kept in the
            signature because a fancier speckle rule could use HU, and the CLI
            needs it to round-trip ct.raw unchanged).
    meta:   parsed meta.json dict.
    work_dir: path to data/work (TotalSegmentator outputs), or None/missing to skip
              the extra-organs step.

    Returns (labels_out, extra_layers) where extra_layers is a list of layers.json-
    shaped dicts for any newly added organ ids (empty if work_dir has no usable
    TotalSegmentator output).
    """
    cleaned = clean_speckle(labels)
    if work_dir is not None and Path(work_dir).is_dir():
        cleaned, extra_layers = add_ts_organs(cleaned, meta, work_dir)
    else:
        extra_layers = []
    return cleaned, extra_layers


def _load_bundle(bundle_dir):
    bundle_dir = Path(bundle_dir)
    meta = json.loads((bundle_dir / "meta.json").read_text())
    layers = json.loads((bundle_dir / "layers.json").read_text())
    dims = tuple(meta["dims"])  # x, y, z
    voxels = dims[0] * dims[1] * dims[2]
    # files are z-major / x-fastest on disk (A4); numpy array shaped (z,y,x) with
    # C order gives exactly that byte layout when read flat, so read into (z,y,x)
    # and transpose to (x,y,z) for everything above, which indexes labels[x,y,z].
    ct_zyx = np.fromfile(bundle_dir / "ct.raw", dtype="<i2").reshape((dims[2], dims[1], dims[0]))
    lb_zyx = np.fromfile(bundle_dir / "labels.raw", dtype="<u1").reshape((dims[2], dims[1], dims[0]))
    ct = np.transpose(ct_zyx, (2, 1, 0))
    labels = np.transpose(lb_zyx, (2, 1, 0))
    return meta, layers, ct, labels


def _write_bundle(out_dir, meta, layers, ct, labels, findings_src):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ct_zyx = np.transpose(ct, (2, 1, 0)).copy(order="C")
    lb_zyx = np.transpose(labels, (2, 1, 0)).copy(order="C")
    ct_zyx.astype("<i2").tofile(out_dir / "ct.raw")
    lb_zyx.astype("<u1").tofile(out_dir / "labels.raw")
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2))
    (out_dir / "layers.json").write_text(json.dumps(layers, indent=2))
    if findings_src.exists():
        shutil.copy(findings_src, out_dir / "findings.json")
    else:
        (out_dir / "findings.json").write_text("[]")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bundle_dir", nargs="?", default="data/out/body",
                     help="A4 bundle directory to read (default: data/out/body)")
    ap.add_argument("work_dir", nargs="?", default="data/work",
                     help="TotalSegmentator work directory (default: data/work)")
    ap.add_argument("out_dir", help="Directory to WRITE the cleaned bundle to. "
                                     "Must not be under data/out (that's lane L1's).")
    args = ap.parse_args()

    out_dir = Path(args.out_dir).resolve()
    forbidden = (Path("data/out").resolve(),)
    if any(out_dir == f or f in out_dir.parents for f in forbidden):
        sys.exit(f"refusing to write into {out_dir}: data/out belongs to lane L1")

    meta, layers, ct, labels = _load_bundle(args.bundle_dir)

    before = count_small_components(labels)
    cleaned, extra_layers = clean(labels, ct, meta, args.work_dir)
    after = count_small_components(cleaned)

    print(f"speckle (fat/muscle connected components < 5 voxels): before={before} after={after}")
    if extra_layers:
        print("added organ layers:", ", ".join(f"{l['id']}:{l['name']}" for l in extra_layers))
    else:
        print("no TotalSegmentator organ masks added (work_dir missing or none found)")

    out_layers = layers + extra_layers
    _write_bundle(out_dir, meta, out_layers, ct, cleaned, Path(args.bundle_dir) / "findings.json")
    print(f"wrote cleaned bundle to {out_dir}")


if __name__ == "__main__":
    main()
