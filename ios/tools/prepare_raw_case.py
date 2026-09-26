#!/usr/bin/env python3
"""Convert a team raw case bundle (App/Cases/<name>: meta.json, ct.raw int16, labels.raw uint8,
layers.json, findings.json) into a folder the native viewer bundles:
ios/Generalizable/Resources/Cases/<ID>/.

Unlike prepare_head.py, labels keep their own values: the case ships layers.json (id, name,
color, peel_order, blurb), which the viewer uses instead of the medical Organ table. That is
what lets non-medical volumes (the Sun, a circuit board) and layer peeling work.

NIfTI header layout is prepare_head.py's; the raw files are already x-fastest like NIfTI, so the
voxel bytes are copied through unchanged and this needs only the standard library.
Usage: python3 ios/tools/prepare_raw_case.py sun Synthetic_Sun "The Sun"
       python3 ios/tools/prepare_raw_case.py circuit Synthetic_Circuit "Circuit board"
"""
import gzip, json, shutil, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def nifti_header(dims, spacing, origin, datatype: int, bitpix: int) -> bytes:
    hdr = bytearray(348)
    struct.pack_into("<i", hdr, 0, 348)                                   # sizeof_hdr
    struct.pack_into("<8h", hdr, 40, 3, *dims, 1, 1, 1, 1)                 # dim
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
    return bytes(hdr) + b"\0" * 4


def main(src_name: str, case_id: str, region: str):
    src = ROOT / "App/Cases" / src_name
    dst = ROOT / "ios/Generalizable/Resources/Cases" / case_id
    meta = json.loads((src / "meta.json").read_text())
    dims, spacing, origin = meta["dims"], meta["spacing_mm"], meta["origin_mm"]
    n = dims[0] * dims[1] * dims[2]
    ct, lab = (src / "ct.raw").read_bytes(), (src / "labels.raw").read_bytes()
    assert len(ct) == 2 * n and len(lab) == n, "raw size does not match meta.json dims"

    dst.mkdir(parents=True, exist_ok=True)
    for name, raw, dt, bp in [("ct.nii.gz", ct, 4, 16), ("combined_labels.nii.gz", lab, 2, 8)]:
        with gzip.open(dst / name, "wb", compresslevel=6) as f:
            f.write(nifti_header(dims, spacing, origin, dt, bp) + raw)
    for extra in ["layers.json", "findings.json"]:
        if (src / extra).exists():
            shutil.copy(src / extra, dst / extra)
    meta["region"], meta["name"] = region, meta.get("name", "Synthetic")
    (dst / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")

    counts = {v: lab.count(bytes([v])) for v in sorted(set(lab))}
    print(f"wrote {dst.relative_to(ROOT)}  dims={dims}  labels={counts}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
