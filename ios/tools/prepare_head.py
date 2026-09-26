#!/usr/bin/env python3
"""Convert the team's head CT bundle (App/Cases/head: CQ500-CT-243 + Seg-CQ500 bleed mask)
into NIfTI files the native viewer bundles: ios/Generalizable/Resources/Cases/CQ500_CT_243/.

App/Cases/head is already RAS-canonical (meta.json "orientation": "RAS"), int16 HU and uint8
labels (1 skin, 2 skull, 3 brain, 4 bleed). Labels are shifted by +35 so they land on
Organ.skin/.skull/.brain/.hemorrhage (36-39) in Core/Contracts.swift.

The NIfTI-1 header layout follows nibabel's Nifti1Header (nibabel/nifti1.py, header_dtd);
it's written by hand so this runs with numpy alone.
Usage: python3 ios/tools/prepare_head.py
"""
import gzip, json, shutil, struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "App/Cases/head"
DST = ROOT / "ios/Generalizable/Resources/Cases/CQ500_CT_243"
LABEL_OFFSET = 35


def nifti_bytes(data: np.ndarray, spacing, origin, datatype: int, bitpix: int) -> bytes:
    hdr = bytearray(348)
    struct.pack_into("<i", hdr, 0, 348)                                   # sizeof_hdr
    struct.pack_into("<8h", hdr, 40, 3, *data.shape, 1, 1, 1, 1)           # dim
    struct.pack_into("<hh", hdr, 70, datatype, bitpix)
    struct.pack_into("<8f", hdr, 76, 1.0, *spacing, 0, 0, 0, 0)            # pixdim (qfac=1)
    struct.pack_into("<f", hdr, 108, 352.0)                                # vox_offset
    struct.pack_into("<ff", hdr, 112, 1.0, 0.0)                            # scl_slope/inter
    hdr[123] = 2                                                           # xyzt_units: mm
    struct.pack_into("<hh", hdr, 252, 1, 1)                                # qform/sform = scanner
    struct.pack_into("<6f", hdr, 256, 0, 0, 0, *origin)                    # identity quaternion
    sx, sy, sz = spacing
    struct.pack_into("<4f", hdr, 280, sx, 0, 0, origin[0])                 # srow_x
    struct.pack_into("<4f", hdr, 296, 0, sy, 0, origin[1])                 # srow_y
    struct.pack_into("<4f", hdr, 312, 0, 0, sz, origin[2])                 # srow_z
    hdr[344:348] = b"n+1\0"
    # NIfTI is Fortran order: x fastest.
    return bytes(hdr) + b"\0" * 4 + np.asfortranarray(data).tobytes(order="F")


def main():
    meta = json.loads((SRC / "meta.json").read_text())
    nx, ny, nz = meta["dims"]
    spacing, origin = meta["spacing_mm"], meta["origin_mm"]
    # The raw files are written x-fastest (same as NIfTI), so read them in Fortran order.
    ct = np.fromfile(SRC / "ct.raw", "<i2").reshape((nx, ny, nz), order="F")
    lab = np.fromfile(SRC / "labels.raw", "u1").reshape((nx, ny, nz), order="F")
    lab = np.where(lab > 0, lab + LABEL_OFFSET, 0).astype(np.uint8)

    DST.mkdir(parents=True, exist_ok=True)
    for name, arr, dt, bp in [("ct.nii.gz", ct, 4, 16), ("combined_labels.nii.gz", lab, 2, 8)]:
        with gzip.open(DST / name, "wb", compresslevel=6) as f:
            f.write(nifti_bytes(arr, spacing, origin, dt, bp))
    for extra in ["findings.json", "detection.json", "meta.json"]:
        if (SRC / extra).exists():
            shutil.copy(SRC / extra, DST / extra)

    counts = {int(k): int(v) for k, v in zip(*np.unique(lab, return_counts=True))}
    print(f"wrote {DST.relative_to(ROOT)}  dims={ct.shape}  HU=[{ct.min()}, {ct.max()}]  labels={counts}")


if __name__ == "__main__":
    main()
