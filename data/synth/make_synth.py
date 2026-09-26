#!/usr/bin/env python3
"""Generate synthetic A4-format case bundles: The Sun and a Circuit board.

Format (PRD addendum A4):
  ct.raw       int16 LE, no header, x fastest then y then z
  labels.raw   uint8, same grid/order, 0 = background
  meta.json    dims, spacing_mm, origin_mm, orientation, dtypes,
               window_presets, source, license
  layers.json  list of {id, name, group, color, peel_order, blurb},
               ordered outside to inside
  findings.json list of {id, label_id, title, center_mm, radius_mm,
               explanation}

numpy only. Run with:
  cd /Users/dqi26/Generalizable && uv run --python 3.12 --with numpy \
      python data/synth/make_synth.py
"""
from __future__ import annotations

import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CASES_DIR = os.path.join(REPO_ROOT, "App", "Cases")


def write_bundle(out_dir, dims, spacing_mm, ct, labels, layers, findings,
                  window_presets, source, license_str):
    """dims = (nx, ny, nz). ct/labels arrays have shape (nz, ny, nx) so that
    a C-order .tofile() write yields x fastest, then y, then z."""
    os.makedirs(out_dir, exist_ok=True)
    nx, ny, nz = dims
    assert ct.shape == (nz, ny, nx), ct.shape
    assert labels.shape == (nz, ny, nx), labels.shape

    ct.astype("<i2").tofile(os.path.join(out_dir, "ct.raw"))
    labels.astype(np.uint8).tofile(os.path.join(out_dir, "labels.raw"))

    origin_mm = [-(dims[i] // 2) * spacing_mm[i] for i in range(3)]

    meta = {
        "dims": [nx, ny, nz],
        "spacing_mm": spacing_mm,
        "origin_mm": origin_mm,
        "orientation": "RAS",
        "dtypes": {"ct": "int16", "labels": "uint8"},
        "window_presets": window_presets,
        "source": source,
        "license": license_str,
    }
    with open(os.path.join(out_dir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    with open(os.path.join(out_dir, "layers.json"), "w") as f:
        json.dump(layers, f, indent=2)
    with open(os.path.join(out_dir, "findings.json"), "w") as f:
        json.dump(findings, f, indent=2)

    total = sum(
        os.path.getsize(os.path.join(out_dir, n))
        for n in ("ct.raw", "labels.raw", "meta.json", "layers.json", "findings.json")
    )
    print(f"  wrote {out_dir}: {total} bytes ({total / 1024 / 1024:.3f} MiB)")
    return meta


def ijk_to_mm(idx_xyz, origin_mm, spacing_mm):
    return [origin_mm[i] + idx_xyz[i] * spacing_mm[i] for i in range(3)]


# ---------------------------------------------------------------------------
# The Sun
# ---------------------------------------------------------------------------

def make_sun():
    print("Building Sun bundle...")
    dims = (80, 80, 80)  # nx, ny, nz
    nx, ny, nz = dims
    spacing = [10.0, 10.0, 10.0]  # mm/voxel -> ~800mm scale-model sphere
    origin = [-(dims[i] // 2) * spacing[i] for i in range(3)]

    idx_z, idx_y, idx_x = np.indices((nz, ny, nx))
    mm_x = origin[0] + idx_x * spacing[0]
    mm_y = origin[1] + idx_y * spacing[1]
    mm_z = origin[2] + idx_z * spacing[2]
    r = np.sqrt(mm_x ** 2 + mm_y ** 2 + mm_z ** 2)

    ID_CORE, ID_RADIATIVE, ID_CONVECTIVE, ID_PHOTOSPHERE, ID_SUNSPOT, ID_CORONA = 1, 2, 3, 4, 5, 6

    R_PHOTOSPHERE = 320.0
    label = np.zeros((nz, ny, nx), dtype=np.uint8)
    label[r <= 0.20 * R_PHOTOSPHERE] = ID_CORE
    label[(r > 0.20 * R_PHOTOSPHERE) & (r <= 0.65 * R_PHOTOSPHERE)] = ID_RADIATIVE
    label[(r > 0.65 * R_PHOTOSPHERE) & (r <= 0.90 * R_PHOTOSPHERE)] = ID_CONVECTIVE
    label[(r > 0.90 * R_PHOTOSPHERE) & (r <= R_PHOTOSPHERE)] = ID_PHOTOSPHERE

    # Coronal loop: an arch tied to two footpoints on the photosphere,
    # bulging outward above the surface.
    def sph_to_cart(colat_deg, az_deg):
        colat, az = np.radians(colat_deg), np.radians(az_deg)
        return np.array([
            np.sin(colat) * np.cos(az),
            np.sin(colat) * np.sin(az),
            np.cos(colat),
        ])

    a_hat = sph_to_cart(80.0, -20.0)
    b_hat = sph_to_cart(80.0, 20.0)
    omega = np.arccos(np.clip(np.dot(a_hat, b_hat), -1.0, 1.0))
    t = np.linspace(0.0, 1.0, 80)
    sin_o = np.sin(omega)
    w_a = np.sin((1 - t) * omega) / sin_o
    w_b = np.sin(t * omega) / sin_o
    dirs = np.outer(w_a, a_hat) + np.outer(w_b, b_hat)  # (80,3) unit-ish vectors
    dirs = dirs / np.linalg.norm(dirs, axis=1, keepdims=True)
    loop_h = 55.0
    radii = R_PHOTOSPHERE + loop_h * np.sin(np.pi * t)
    arc_pts = dirs * radii[:, None]  # (80,3) mm coordinates

    tube_radius = 16.0
    corona_mask = np.zeros((nz, ny, nx), dtype=bool)
    for px, py, pz in arc_pts:
        d2 = (mm_x - px) ** 2 + (mm_y - py) ** 2 + (mm_z - pz) ** 2
        corona_mask |= d2 <= tube_radius ** 2
    label[corona_mask] = ID_CORONA

    # Sunspot: a small cool patch embedded near the photosphere surface.
    spot_center = sph_to_cart(60.0, 30.0) * (0.5 * (0.90 * R_PHOTOSPHERE + R_PHOTOSPHERE))
    spot_radius = 40.0
    spot_mask = (
        (mm_x - spot_center[0]) ** 2
        + (mm_y - spot_center[1]) ** 2
        + (mm_z - spot_center[2]) ** 2
    ) <= spot_radius ** 2
    label[spot_mask] = ID_SUNSPOT

    density = np.zeros(ID_CORONA + 1, dtype=np.int16)
    density[0] = -200       # deep space / background
    density[ID_CORE] = 2200
    density[ID_RADIATIVE] = 1600
    density[ID_CONVECTIVE] = 1100
    density[ID_PHOTOSPHERE] = 650
    density[ID_SUNSPOT] = 420
    density[ID_CORONA] = 850
    ct = density[label]

    layers = [
        {"id": ID_CORONA, "name": "Coronal loop", "group": "feature",
         "color": "#7FDBFF", "peel_order": 1,
         "blurb": "A loop of hot, tenuous plasma arcing above the surface, traced by the magnetic field."},
        {"id": ID_PHOTOSPHERE, "name": "Photosphere", "group": "region",
         "color": "#FFD54A", "peel_order": 2,
         "blurb": "The visible surface of the Sun, where light escapes into space."},
        {"id": ID_SUNSPOT, "name": "Sunspot", "group": "feature",
         "color": "#5B3A29", "peel_order": 3,
         "blurb": "A cooler, darker patch on the photosphere caused by concentrated magnetic field lines."},
        {"id": ID_CONVECTIVE, "name": "Convective zone", "group": "region",
         "color": "#FF8C42", "peel_order": 4,
         "blurb": "Hot plasma churns here in convection cells, carrying energy outward toward the surface."},
        {"id": ID_RADIATIVE, "name": "Radiative zone", "group": "region",
         "color": "#E8542A", "peel_order": 5,
         "blurb": "Energy moves outward here as radiation, taking a long time to random-walk through dense plasma."},
        {"id": ID_CORE, "name": "Core", "group": "region",
         "color": "#FFFDE0", "peel_order": 6,
         "blurb": "The innermost region, dense and hot enough to sustain nuclear fusion."},
    ]

    core_center_mm = [0.0, 0.0, 0.0]
    findings = [
        {
            "id": "core",
            "label_id": ID_CORE,
            "title": "The Core",
            "center_mm": core_center_mm,
            "radius_mm": 0.20 * R_PHOTOSPHERE,
            "explanation": "The core is where immense pressure and temperature sustain the proton-proton fusion chain that converts hydrogen into helium.",
        },
        {
            "id": "sunspot",
            "label_id": ID_SUNSPOT,
            "title": "A Sunspot",
            "center_mm": [float(spot_center[0]), float(spot_center[1]), float(spot_center[2])],
            "radius_mm": spot_radius,
            "explanation": "Sunspots are cooler patches where strong, concentrated magnetic field lines suppress convective heat transport to the surface.",
        },
    ]

    window_presets = {"soft": [800, 2000], "density": [1200, 3000]}

    write_bundle(
        os.path.join(CASES_DIR, "sun"),
        dims, spacing, ct, label, layers, findings, window_presets,
        source="Synthetic (generated for Generalizable demo)",
        license_str="CC0",
    )


# ---------------------------------------------------------------------------
# Circuit board
# ---------------------------------------------------------------------------

def make_circuit():
    print("Building Circuit board bundle...")
    dims = (96, 96, 32)  # nx, ny, nz -- thin slab
    nx, ny, nz = dims
    spacing = [1.0, 1.0, 0.25]  # mm/voxel -> 96x96mm board, 8mm tall
    origin = [-(dims[i] // 2) * spacing[i] for i in range(3)]

    idx_z, idx_y, idx_x = np.indices((nz, ny, nx))

    ID_SUBSTRATE, ID_COPPER, ID_CHIP, ID_SOLDER, ID_VIA = 1, 2, 3, 4, 5
    label = np.zeros((nz, ny, nx), dtype=np.uint8)

    # 1. substrate slab (FR4 board body), z voxels 0..5
    label[(idx_z <= 5)] = ID_SUBSTRATE

    # chip footprint (index space, 1mm/voxel in x,y): 36mm square, centered
    fp_lo, fp_hi = 30, 66

    # 2. copper traces at z==6, outside the chip footprint
    def segment_dist(x1, y1, x2, y2):
        X = idx_x[0].astype(np.float64)
        Y = idx_y[0].astype(np.float64)
        dx, dy = x2 - x1, y2 - y1
        seg_len_sq = dx * dx + dy * dy
        t = np.clip(((X - x1) * dx + (Y - y1) * dy) / seg_len_sq, 0.0, 1.0)
        px, py = x1 + t * dx, y1 + t * dy
        return np.sqrt((X - px) ** 2 + (Y - py) ** 2)

    segments = [
        (fp_lo, 48, 5, 48),
        (fp_hi, 48, 91, 48),
        (48, fp_lo, 48, 5),
        (48, fp_hi, 48, 91),
        (fp_lo, fp_lo, 10, 10),
        (fp_hi, fp_hi, 86, 86),
    ]
    trace_half_width = 1.0
    trace_mask_2d = np.zeros((ny, nx), dtype=bool)
    for seg in segments:
        trace_mask_2d |= segment_dist(*seg) <= trace_half_width

    footprint_mask_2d = np.zeros((ny, nx), dtype=bool)
    footprint_mask_2d[fp_lo:fp_hi, fp_lo:fp_hi] = True
    trace_mask_2d &= ~footprint_mask_2d

    copper_mask = (idx_z == 6) & trace_mask_2d[None, :, :]
    label[copper_mask] = ID_COPPER

    # 3. solder balls under the chip, z voxels 7..8
    ball_radius = 2.0
    ball_centers = [(bx, by) for bx in np.linspace(fp_lo + 4, fp_hi - 4, 4)
                    for by in np.linspace(fp_lo + 4, fp_hi - 4, 4)]
    solder_mask_2d = np.zeros((ny, nx), dtype=bool)
    X2, Y2 = idx_x[0].astype(np.float64), idx_y[0].astype(np.float64)
    for bx, by in ball_centers:
        solder_mask_2d |= (X2 - bx) ** 2 + (Y2 - by) ** 2 <= ball_radius ** 2
    solder_mask = ((idx_z >= 7) & (idx_z <= 8)) & solder_mask_2d[None, :, :]
    label[solder_mask] = ID_SOLDER

    # 4. chip package block, z voxels 9..20
    chip_mask = (
        (idx_x >= fp_lo) & (idx_x < fp_hi)
        & (idx_y >= fp_lo) & (idx_y < fp_hi)
        & (idx_z >= 9) & (idx_z <= 20)
    )
    label[chip_mask] = ID_CHIP

    # 5. via: plated through-hole away from the chip, on a trace line
    via_xy = (20, 48)
    via_radius = 1.5
    via_mask = (
        ((idx_x - via_xy[0]) ** 2 + (idx_y - via_xy[1]) ** 2 <= via_radius ** 2)
        & (idx_z <= 6)
    )
    label[via_mask] = ID_VIA

    density = np.zeros(ID_VIA + 1, dtype=np.int16)
    density[0] = -500        # air
    density[ID_SUBSTRATE] = 300
    density[ID_COPPER] = 2900
    density[ID_CHIP] = 500
    density[ID_SOLDER] = 2100
    density[ID_VIA] = 2800
    ct = density[label]

    layers = [
        {"id": ID_CHIP, "name": "Chip package", "group": "package",
         "color": "#2B2B2B", "peel_order": 1,
         "blurb": "The molded housing over the semiconductor die, on top of the board."},
        {"id": ID_SOLDER, "name": "Solder balls", "group": "solder",
         "color": "#C0C0C0", "peel_order": 2,
         "blurb": "A ball-grid array of solder bumps carrying signal and power between the chip and the board."},
        {"id": ID_VIA, "name": "Via", "group": "via",
         "color": "#D4AF37", "peel_order": 3,
         "blurb": "A plated hole connecting copper on different layers of the board."},
        {"id": ID_COPPER, "name": "Copper traces", "group": "trace",
         "color": "#B87333", "peel_order": 4,
         "blurb": "Etched copper lines that carry electrical signals across the board surface."},
        {"id": ID_SUBSTRATE, "name": "Substrate", "group": "substrate",
         "color": "#2E7D32", "peel_order": 5,
         "blurb": "The fiberglass (FR4) board body that everything else is mounted on."},
    ]

    chip_center_idx = ((fp_lo + fp_hi) / 2.0, (fp_lo + fp_hi) / 2.0, 14.0)
    chip_center_mm = ijk_to_mm(chip_center_idx, origin, spacing)
    via_center_idx = (via_xy[0], via_xy[1], 3.0)
    via_center_mm = ijk_to_mm(via_center_idx, origin, spacing)

    findings = [
        {
            "id": "chip",
            "label_id": ID_CHIP,
            "title": "The Chip Package",
            "center_mm": chip_center_mm,
            "radius_mm": 15.0,
            "explanation": "The chip package is the molded housing that protects the semiconductor die and routes its connections out to the board.",
        },
        {
            "id": "via",
            "label_id": ID_VIA,
            "title": "A Via",
            "center_mm": via_center_mm,
            "radius_mm": 3.0,
            "explanation": "A via is a plated hole that carries an electrical connection vertically between copper layers of the board.",
        },
    ]

    window_presets = {"soft": [400, 1200], "density": [1400, 3800]}

    write_bundle(
        os.path.join(CASES_DIR, "circuit"),
        dims, spacing, ct, label, layers, findings, window_presets,
        source="Synthetic (generated for Generalizable demo)",
        license_str="CC0",
    )


if __name__ == "__main__":
    make_sun()
    make_circuit()
    print("Done.")
