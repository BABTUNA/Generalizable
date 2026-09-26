"""Shared helpers for building A4 case bundles."""
import glob
import json
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy.ndimage import affine_transform, binary_erosion, binary_fill_holes, label as cc_label


def load_nii(path):
    img = nib.load(path)
    return img.get_fdata().astype(np.float32), img.affine, img.shape


def load_mask_raw(path):
    """Load a segmentation mask preserving its on-disk dtype (fast, low memory:
    avoids nibabel's default float64 upcast for what is usually a uint8 volume)."""
    img = nib.load(path)
    return np.asarray(img.dataobj)


def native_spacing_origin(affine):
    spacing = np.abs(np.diag(affine)[:3])
    origin = affine[:3, 3]
    return spacing, origin


def load_mask(path, shape):
    if path is None or not Path(path).exists():
        return np.zeros(shape, dtype=bool)
    return load_mask_raw(path) > 0.5


def union_masks(paths, shape):
    m = np.zeros(shape, dtype=bool)
    for p in paths:
        if Path(p).exists():
            m |= load_mask_raw(p) > 0.5
    return m


def largest_cc(mask):
    lab, n = cc_label(mask)
    if n == 0:
        return mask
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    biggest = sizes.argmax()
    return lab == biggest


def body_mask_hu_fallback(ct):
    m = ct > -500
    m = largest_cc(m)
    # fill holes slice by slice (z axis assumed last)
    out = np.zeros_like(m)
    for z in range(m.shape[2]):
        out[:, :, z] = binary_fill_holes(m[:, :, z])
    return out


def resample_axis_aligned(vol, spacing_in, origin_in, spacing_out, origin_out, out_shape, order):
    """Resample an axis-aligned RAS volume onto a new axis-aligned grid, no rotation."""
    scale = np.array(spacing_out) / np.array(spacing_in)
    offset = (np.array(origin_out) - np.array(origin_in)) / np.array(spacing_in)
    matrix = np.diag(scale)
    cval = -1024.0 if order == 1 else 0.0
    return affine_transform(
        vol, matrix, offset=offset, output_shape=out_shape, order=order,
        mode="constant", cval=cval, prefilter=(order > 1),
    ).astype(vol.dtype)


def compute_crop_grid(mask, spacing_in, origin_in, target_spacing, margin_voxels=4):
    idx = np.argwhere(mask)
    if idx.size == 0:
        # fallback: whole volume
        lo = np.array([0, 0, 0])
        hi = np.array(mask.shape) - 1
    else:
        lo = idx.min(axis=0)
        hi = idx.max(axis=0)
    mm_lo = origin_in + lo * spacing_in
    mm_hi = origin_in + hi * spacing_in
    margin_mm = margin_voxels * target_spacing
    out_origin = mm_lo - margin_mm
    out_extent = (mm_hi + margin_mm) - out_origin
    out_dims = np.ceil(out_extent / target_spacing).astype(int) + 1
    return out_origin, out_dims


def write_bundle(out_dir, ct_i16, labels_u8, dims, spacing_mm, origin_mm, window_presets,
                  source, license_, layers, findings):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    x, y, z = dims
    assert ct_i16.shape == (x, y, z)
    assert labels_u8.shape == (x, y, z)
    # file order: x fastest, then y, then z -> array index [x,y,z] with x varying fastest
    # numpy default C order on array shaped (z,y,x) gives x fastest when written flat.
    ct_zyx = np.transpose(ct_i16, (2, 1, 0)).copy(order="C")
    lb_zyx = np.transpose(labels_u8, (2, 1, 0)).copy(order="C")
    ct_zyx.astype("<i2").tofile(out_dir / "ct.raw")
    lb_zyx.astype("<u1").tofile(out_dir / "labels.raw")

    meta = {
        "dims": [int(x), int(y), int(z)],
        "spacing_mm": [float(v) for v in spacing_mm],
        "origin_mm": [float(v) for v in origin_mm],
        "orientation": "RAS",
        "ct_dtype": "int16_le_HU",
        "labels_dtype": "uint8",
        "window_presets": window_presets,
        "source": source,
        "license": license_,
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2))
    (out_dir / "layers.json").write_text(json.dumps(layers, indent=2))
    (out_dir / "findings.json").write_text(json.dumps(findings, indent=2))
    ct_mb = (out_dir / "ct.raw").stat().st_size / 1e6
    lb_mb = (out_dir / "labels.raw").stat().st_size / 1e6
    print(f"wrote {out_dir}: dims={dims} ct.raw={ct_mb:.1f}MB labels.raw={lb_mb:.1f}MB")
    return ct_mb
