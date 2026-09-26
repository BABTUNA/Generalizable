"""Resample L1 bundles (data/out/<src>) into committed app bundles (App/Cases/<dst>).

DEMO ONLY. PRD addendum A8: every file must stay under MAX_MB so GitHub/Bitrig accept it.
Keeps the physical bounds of the volume; CT is trilinear, labels nearest-neighbour.
Findings are in mm, so they carry over unchanged.

Run: uv run --python 3.12 --with numpy --with scipy python scripts/make_demo_bundles.py
"""
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from scipy.ndimage import map_coordinates

ROOT = Path(__file__).resolve().parent.parent
MAX_MB = 45
PAIRS = [("body", "body"), ("brain", "head")]


def load(src):
    meta = json.loads((src / "meta.json").read_text())
    nx, ny, nz = meta["dims"]
    # x fastest => C-order array indexed [z, y, x]
    ct = np.fromfile(src / "ct.raw", dtype="<i2").reshape(nz, ny, nx)
    lab = np.fromfile(src / "labels.raw", dtype=np.uint8).reshape(nz, ny, nx)
    return meta, ct, lab


def resample(meta, ct, lab):
    dims = np.array(meta["dims"], float)
    sp = np.array(meta["spacing_mm"], float)
    org = np.array(meta["origin_mm"], float)
    # int16 CT dominates size: 2 bytes per voxel
    scale = max(1.0, (dims.prod() * 2 / (MAX_MB * 1e6)) ** (1 / 3))
    if scale == 1.0:
        return meta, ct, lab
    new_sp = sp * scale
    new_dims = np.maximum(1, np.floor(dims * sp / new_sp)).astype(int)
    # keep the outer face of the volume fixed: first voxel centre moves inward
    new_org = org - sp / 2 + new_sp / 2
    axes = [(new_org[i] + np.arange(new_dims[i]) * new_sp[i] - org[i]) / sp[i] for i in range(3)]
    zz, yy, xx = np.meshgrid(axes[2], axes[1], axes[0], indexing="ij")
    coords = np.stack([zz, yy, xx])
    new_ct = np.rint(map_coordinates(ct.astype(np.float32), coords, order=1, mode="nearest")).astype("<i2")
    new_lab = map_coordinates(lab, coords, order=0, mode="nearest").astype(np.uint8)
    meta = dict(meta, dims=new_dims.tolist(), spacing_mm=new_sp.round(4).tolist(), origin_mm=new_org.round(4).tolist())
    return meta, new_ct, new_lab


def main():
    for src_name, dst_name in PAIRS:
        src, dst = ROOT / "data/out" / src_name, ROOT / "App/Cases" / dst_name
        if not (src / "meta.json").exists():
            print(f"skip {src_name}: {src} missing", file=sys.stderr)
            continue
        meta, ct, lab = resample(*load(src))
        dst.mkdir(parents=True, exist_ok=True)
        ct.tofile(dst / "ct.raw")
        lab.tofile(dst / "labels.raw")
        (dst / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
        for name in ("layers.json", "findings.json"):
            shutil.copy(src / name, dst / name)
        sizes = {p.name: round(p.stat().st_size / 1e6, 1) for p in dst.iterdir()}
        print(dst_name, meta["dims"], meta["spacing_mm"], sizes)
        assert all(v < MAX_MB for v in sizes.values()), f"{dst_name} over {MAX_MB} MB"


if __name__ == "__main__":
    main()
