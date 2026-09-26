#!/usr/bin/env python3
"""Reference loader / verifier for Layer Lens A4 case bundles.

Usage: python data/verify.py data/out/body
       python data/verify.py data/out/brain
"""
import json
import sys
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.ndimage import map_coordinates


def load_bundle(bundle_dir: Path):
    meta = json.loads((bundle_dir / "meta.json").read_text())
    dims = meta["dims"]  # [x,y,z]
    x, y, z = dims
    ct = np.fromfile(bundle_dir / "ct.raw", dtype="<i2")
    assert ct.size == x * y * z, f"ct.raw size mismatch: {ct.size} vs {x*y*z}"
    ct = ct.reshape((z, y, x)).transpose(2, 1, 0)  # -> (x,y,z), x fastest in file
    labels = np.fromfile(bundle_dir / "labels.raw", dtype="<u1")
    assert labels.size == x * y * z, f"labels.raw size mismatch"
    labels = labels.reshape((z, y, x)).transpose(2, 1, 0)
    layers = json.loads((bundle_dir / "layers.json").read_text())
    findings = json.loads((bundle_dir / "findings.json").read_text())
    return meta, ct, labels, layers, findings


def voxel_volume_ml(meta):
    sx, sy, sz = meta["spacing_mm"]
    return (sx * sy * sz) / 1000.0


def ijk_to_mm(meta, ijk):
    o = np.array(meta["origin_mm"])
    sp = np.array(meta["spacing_mm"])
    return o + np.array(ijk) * sp


def oblique_slice(vol, center_ijk, tilt_deg, size=256, spacing=1.0):
    """Sample a plane through center_ijk, tilted tilt_deg about the x axis, trilinear."""
    cx, cy, cz = center_ijk
    t = np.radians(tilt_deg)
    u = np.arange(-size // 2, size // 2) * spacing
    v = np.arange(-size // 2, size // 2) * spacing
    uu, vv = np.meshgrid(u, v, indexing="ij")
    # plane basis: local x axis stays x; the plane normal tilts about x
    X = cx + uu
    Y = cy + vv * np.cos(t)
    Z = cz + vv * np.sin(t)
    coords = np.stack([X, Y, Z])
    return map_coordinates(vol, coords, order=1, mode="constant", cval=-1024)


def main():
    bundle_dir = Path(sys.argv[1])
    name = bundle_dir.name
    meta, ct, labels, layers, findings = load_bundle(bundle_dir)
    print(f"=== {name} ===")
    print("dims:", meta["dims"], "spacing_mm:", meta["spacing_mm"], "origin_mm:", meta["origin_mm"])
    ct_size = (bundle_dir / "ct.raw").stat().st_size
    lb_size = (bundle_dir / "labels.raw").stat().st_size
    print(f"ct.raw: {ct_size/1e6:.1f} MB, labels.raw: {lb_size/1e6:.1f} MB")
    print("HU min/max:", ct.min(), ct.max(), "percentiles 0.5/50/99.5:", np.percentile(ct, [0.5, 50, 99.5]))

    layer_ids = {l["id"] for l in layers}
    present_ids = set(np.unique(labels).tolist())
    print("label ids present:", sorted(present_ids))
    unknown = present_ids - layer_ids - {0}
    if unknown:
        print("!! WARNING: label ids present but not in layers.json:", unknown)
    else:
        print("OK: every non-background label id in labels.raw is in layers.json")

    vol_ml = voxel_volume_ml(meta)
    print("per-label voxel counts / volume(mL):")
    for lid in sorted(present_ids):
        if lid == 0:
            continue
        name_l = next((l["name"] for l in layers if l["id"] == lid), "?")
        n = int((labels == lid).sum())
        print(f"  id={lid:3d} {name_l:20s} voxels={n:9d} volume={n*vol_ml:9.1f} mL")

    for f in findings:
        lbl = f["label_id"]
        ijk = np.round((np.array(f["center_mm"]) - np.array(meta["origin_mm"])) / np.array(meta["spacing_mm"])).astype(int)
        x, y, z = meta["dims"]
        inside_bounds = (0 <= ijk[0] < x) and (0 <= ijk[1] < y) and (0 <= ijk[2] < z)
        lands_on_label = inside_bounds and labels[ijk[0], ijk[1], ijk[2]] == lbl
        print(f"finding '{f['title']}': center_mm={f['center_mm']} -> ijk={ijk.tolist()} "
              f"inside_bounds={inside_bounds} lands_on_label({lbl})={lands_on_label}")
        if not lands_on_label:
            print("  !! WARNING: finding center does not land on its label id (may be near a boundary voxel)")

    # Previews
    preview_dir = Path("data/previews")
    preview_dir.mkdir(parents=True, exist_ok=True)
    x, y, z = meta["dims"]
    cmap_colors = {0: (0, 0, 0)}
    for l in layers:
        h = l["color"].lstrip("#")
        cmap_colors[l["id"]] = tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))

    def label_rgb(lbl_slice):
        rgb = np.zeros(lbl_slice.shape + (3,))
        for lid, col in cmap_colors.items():
            rgb[lbl_slice == lid] = col
        return rgb

    def save_pair(ct_slice, lbl_slice, fname, wl=(40, 400)):
        level, width = wl
        lo, hi = level - width / 2, level + width / 2
        fig, axs = plt.subplots(1, 2, figsize=(8, 4))
        axs[0].imshow(ct_slice.T, cmap="gray", vmin=lo, vmax=hi, origin="lower")
        axs[0].set_title("CT")
        axs[1].imshow(ct_slice.T, cmap="gray", vmin=lo, vmax=hi, origin="lower")
        axs[1].imshow(label_rgb(lbl_slice).transpose(1, 0, 2), alpha=0.5, origin="lower")
        axs[1].set_title("labels")
        plt.tight_layout()
        plt.savefig(preview_dir / fname, dpi=110)
        plt.close(fig)

    wl = tuple(meta["window_presets"].get("soft", [40, 400]))
    save_pair(ct[x // 2, :, :], labels[x // 2, :, :], f"{name}_sagittal.png", wl)
    save_pair(ct[:, y // 2, :], labels[:, y // 2, :], f"{name}_coronal.png", wl)
    save_pair(ct[:, :, z // 2], labels[:, :, z // 2], f"{name}_axial.png", wl)

    if findings:
        center_ijk = np.round((np.array(findings[0]["center_mm"]) - np.array(meta["origin_mm"])) / np.array(meta["spacing_mm"]))
    else:
        center_ijk = np.array([x / 2, y / 2, z / 2])
    obl_ct = oblique_slice(ct, center_ijk, 60.0, size=min(256, x, y, z), spacing=meta["spacing_mm"][0])
    obl_lb = oblique_slice(labels.astype(np.float32), center_ijk, 60.0, size=min(256, x, y, z), spacing=meta["spacing_mm"][0])
    obl_lb = np.round(obl_lb).astype(np.uint8)
    save_pair(obl_ct, obl_lb, f"{name}_oblique60.png", wl)

    print(f"Saved previews to {preview_dir}/{name}_[sagittal|coronal|axial|oblique60].png")
    print(f"=== {name}: OK ===\n")


if __name__ == "__main__":
    main()
