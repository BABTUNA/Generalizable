#!/usr/bin/env python3
"""Reload each synthetic bundle using only meta.json and assert:
  - ct.raw / labels.raw sizes match dims/dtypes in meta.json
  - every label id present in labels.raw is 0 or a known layers.json id
  - each finding's center_mm lands on a voxel carrying that finding's label_id

Run with:
  cd /Users/dqi26/Generalizable && uv run --python 3.12 --with numpy \
      python data/synth/verify_synth.py
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DTYPE_MAP = {"int16": "<i2", "uint8": "u1"}


def verify_bundle(case_dir, name):
    print(f"--- {name} ({case_dir}) ---")
    with open(os.path.join(case_dir, "meta.json")) as f:
        meta = json.load(f)
    with open(os.path.join(case_dir, "layers.json")) as f:
        layers = json.load(f)
    with open(os.path.join(case_dir, "findings.json")) as f:
        findings = json.load(f)

    nx, ny, nz = meta["dims"]
    spacing = meta["spacing_mm"]
    origin = meta["origin_mm"]
    n_voxels = nx * ny * nz

    ct_path = os.path.join(case_dir, "ct.raw")
    labels_path = os.path.join(case_dir, "labels.raw")

    ct_dtype = np.dtype(DTYPE_MAP[meta["dtypes"]["ct"]])
    labels_dtype = np.dtype(DTYPE_MAP[meta["dtypes"]["labels"]])

    ct_bytes = os.path.getsize(ct_path)
    labels_bytes = os.path.getsize(labels_path)
    assert ct_bytes == n_voxels * ct_dtype.itemsize, (
        f"ct.raw size {ct_bytes} != {n_voxels} * {ct_dtype.itemsize}"
    )
    assert labels_bytes == n_voxels * labels_dtype.itemsize, (
        f"labels.raw size {labels_bytes} != {n_voxels} * {labels_dtype.itemsize}"
    )
    print(f"  size check ok: dims={meta['dims']} ct={ct_bytes}B labels={labels_bytes}B")

    total = ct_bytes + labels_bytes + sum(
        os.path.getsize(os.path.join(case_dir, n))
        for n in ("meta.json", "layers.json", "findings.json")
    )
    assert total < 2 * 1024 * 1024, f"bundle is {total} bytes, over the 2 MiB budget"
    print(f"  bundle size ok: {total} bytes ({total / 1024 / 1024:.3f} MiB) < 2 MiB")

    ct = np.fromfile(ct_path, dtype=ct_dtype).reshape((nz, ny, nx))
    labels = np.fromfile(labels_path, dtype=labels_dtype).reshape((nz, ny, nx))
    assert ct.shape == labels.shape == (nz, ny, nx)

    layer_ids = {layer["id"] for layer in layers}
    used_ids = set(np.unique(labels).tolist()) - {0}
    assert used_ids <= layer_ids, f"label ids {used_ids - layer_ids} not in layers.json"
    print(f"  label ids ok: used={sorted(used_ids)} subset of layers.json ids={sorted(layer_ids)}")

    for finding in findings:
        center_mm = finding["center_mm"]
        ijk = [round((center_mm[i] - origin[i]) / spacing[i]) for i in range(3)]
        ix, iy, iz = ijk
        assert 0 <= ix < nx and 0 <= iy < ny and 0 <= iz < nz, (
            f"finding {finding['id']} center maps outside the grid: {ijk}"
        )
        voxel_label = int(labels[iz, iy, ix])
        assert voxel_label == finding["label_id"], (
            f"finding {finding['id']} center lands on label {voxel_label}, "
            f"expected {finding['label_id']}"
        )
        print(f"  finding '{finding['id']}' ok: ijk={ijk} label={voxel_label}")

    print(f"  {name}: ALL CHECKS PASSED")


def main():
    cases = [
        (os.path.join(REPO_ROOT, "App", "Cases", "sun"), "Sun"),
        (os.path.join(REPO_ROOT, "App", "Cases", "circuit"), "Circuit board"),
    ]
    ok = True
    for case_dir, name in cases:
        try:
            verify_bundle(case_dir, name)
        except AssertionError as e:
            print(f"  FAIL: {e}")
            ok = False
    if not ok:
        sys.exit(1)
    print("\nAll bundles verified OK.")


if __name__ == "__main__":
    main()
