#!/usr/bin/env python
"""
render_ref.py -- L4-viz-reference

A numpy reference for the two views the Metal render lane (built later in
Bitrig) needs to port: the oblique CT/label slice, and the 3D "peel"
orthographic overview. Every per-pixel formula here is written so it reads
straight across into a fragment shader -- see docs/viz/SPEC.md for the exact
parameters and pseudocode this file implements.

Run with:
  uv run --python 3.12 --with numpy --with scipy --with matplotlib --with nibabel \
      python scripts/viz/render_ref.py [bundle_dir] [work_dir]

Reads bundle_dir (default data/out/body), cleans it with clean_labels.clean()
(the un-cleaned bundle is too speckled to read), and writes PNGs to docs/viz/.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from scipy.ndimage import map_coordinates, gaussian_filter
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).parent))
from clean_labels import clean, _load_bundle

# ---------------------------------------------------------------------------
# CutPlane, mirroring App/Core/CutPlane.swift (A1/A4): tilt about +x, rotation
# about +z, tilt 0 = axial (normal = +z). Kept as one small class so this file
# and SPEC.md can point at the exact same formulas Bitrig's Swift already has.
# ---------------------------------------------------------------------------
class CutPlane:
    def __init__(self, pivot_mm, tilt_deg, rotation_deg=0.0, slice_offset_mm=0.0):
        self.pivot = np.array(pivot_mm, dtype=np.float64)
        self.tilt = np.radians(tilt_deg)
        self.rotation = np.radians(rotation_deg)
        self.slice_offset = slice_offset_mm

    @staticmethod
    def _rotate_x(v, r):
        c, s = np.cos(r), np.sin(r)
        return np.array([v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c])

    @staticmethod
    def _rotate_z(v, r):
        c, s = np.cos(r), np.sin(r)
        return np.array([v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]])

    @property
    def normal(self):
        return self._rotate_z(self._rotate_x(np.array([0.0, 0.0, 1.0]), self.tilt), self.rotation)

    @property
    def u_axis(self):
        return self._rotate_z(self._rotate_x(np.array([1.0, 0.0, 0.0]), self.tilt), self.rotation)

    @property
    def v_axis(self):
        return self._rotate_z(self._rotate_x(np.array([0.0, 1.0, 0.0]), self.tilt), self.rotation)

    @property
    def origin_mm(self):
        return self.pivot + self.normal * self.slice_offset

    def point(self, u, v):
        return self.origin_mm + self.u_axis * u + self.v_axis * v


# ---------------------------------------------------------------------------
# Layer colors / groups / opacities
# ---------------------------------------------------------------------------
def hex_to_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.float64) / 255.0


# Per-sample opacity at the bundle's native 2mm step (A4 spacing). "skin very
# low, fat low, muscle/bone/organs higher" per the task -- tuned by eye against
# the peel PNGs (see docs/viz/SPEC.md).
GROUP_ALPHA_PER_2MM_STEP = {
    "skin": 0.030,
    "fat": 0.060,
    "muscle": 0.150,
    "bone": 0.550,
    "organ": 0.350,
    "brain": 0.350,
}

LAYER_OVERLAY_ALPHA = 0.42  # 2a layers-mode blend: gray*(1-a) + colour*a
EARLY_TERMINATION_ALPHA = 0.98
LIGHT_DIR = np.array([0.35, -0.55, 0.75])
LIGHT_DIR = LIGHT_DIR / np.linalg.norm(LIGHT_DIR)
AMBIENT = 0.35
RAY_DIR = np.array([0.0, -1.0, 0.0])  # anterior camera, front-to-back


def build_lookup(layers):
    """id -> (rgb, group) for every layer, including ids the pipeline never painted."""
    color = np.zeros((256, 3), dtype=np.float64)
    group = ["" for _ in range(256)]
    for l in layers:
        color[l["id"]] = hex_to_rgb(l["color"])
        group[l["id"]] = l["group"]
    return color, group


# ---------------------------------------------------------------------------
# 2(a) Oblique slice
# ---------------------------------------------------------------------------
def window_soft(hu, level, width):
    """Soft-tissue window -> gray in [0,1]. Per-pixel formula:
    gray = clamp((hu - (level - width/2)) / width, 0, 1)."""
    lo = level - width / 2
    return np.clip((hu - lo) / width, 0.0, 1.0)


def sample_oblique(ct, labels, meta, cut, u_range, v_range, px_mm):
    """Samples the CT (trilinear) and labels (nearest) on the plane's (u, v)
    grid. u_range/v_range are (lo, hi) in mm; px_mm is mm per output pixel.
    Per-pixel formula (A1/A4):
        pointMM  = originMM + u*uAxis + v*vAxis
        voxelIdx = (pointMM - origin_mm) / spacing_mm      # A4 inverse map
    """
    origin = np.array(meta["origin_mm"])
    spacing = np.array(meta["spacing_mm"])
    dims = np.array(meta["dims"])

    us = np.arange(u_range[0], u_range[1], px_mm)
    vs = np.arange(v_range[0], v_range[1], px_mm)
    uu, vv = np.meshgrid(us, vs)  # (H, W)

    pts = (cut.origin_mm[None, None, :] + uu[..., None] * cut.u_axis[None, None, :]
           + vv[..., None] * cut.v_axis[None, None, :])
    voxel = (pts - origin) / spacing  # (H, W, 3), x/y/z voxel coords

    coords = [voxel[..., 0], voxel[..., 1], voxel[..., 2]]
    hu = map_coordinates(ct, coords, order=1, mode="constant", cval=-1024, prefilter=False)
    lab = map_coordinates(labels.astype(np.float32), coords, order=0, mode="constant", cval=0,
                           prefilter=False).astype(np.uint8)
    in_bounds = np.all([(voxel[..., i] >= 0) & (voxel[..., i] <= dims[i] - 1) for i in range(3)], axis=0)
    lab[~in_bounds] = 0
    return hu, lab, in_bounds


def label_boundary(lab):
    """A pixel whose label differs from a 4-neighbour -> outline pixel."""
    b = np.zeros(lab.shape, dtype=bool)
    b[:, 1:] |= lab[:, 1:] != lab[:, :-1]
    b[:, :-1] |= lab[:, 1:] != lab[:, :-1]
    b[1:, :] |= lab[1:, :] != lab[:-1, :]
    b[:-1, :] |= lab[1:, :] != lab[:-1, :]
    return b


def render_slice(ct, labels, meta, layers, cut, u_range, v_range, px_mm,
                  show_layers=True, hidden_ids=(), window="soft", findings=()):
    """2(a): the oblique CT/label slice. Returns an (H, W, 3) float image."""
    color_lut, group_lut = build_lookup(layers)
    level, width = meta["window_presets"][window]
    hu, lab, in_bounds = sample_oblique(ct, labels, meta, cut, u_range, v_range, px_mm)
    gray = window_soft(hu, level, width)
    gray3 = np.repeat(gray[..., None], 3, axis=-1)

    if not show_layers:
        img = gray3.copy()
    else:
        visible = np.array([1 if (i == 0 or i not in hidden_ids) else 0 for i in range(256)], dtype=bool)
        vis_pixel = visible[lab] & (lab != 0)
        colour = color_lut[lab]
        alpha = np.where(vis_pixel, LAYER_OVERLAY_ALPHA, 0.0)[..., None]
        img = gray3 * (1 - alpha) + colour * alpha
        # 1px label-boundary outline at full colour, only where both sides are visible labels
        boundary = label_boundary(lab) & vis_pixel
        img[boundary] = colour[boundary]

    img[~in_bounds] = 0.0

    for f in findings:
        img = draw_finding_ring(img, f, cut, u_range, v_range, px_mm)
    return np.clip(img, 0, 1)


def draw_finding_ring(img, finding, cut, u_range, v_range, px_mm):
    """Projects a finding's center_mm onto the plane and draws a ring at
    radius_mm if the center is within ~1 voxel of the plane (else skipped --
    the finding isn't on this slice)."""
    c = np.array(finding["center_mm"])
    rel = c - cut.origin_mm
    dist_to_plane = abs(np.dot(rel, cut.normal))
    if dist_to_plane > 2.0:  # more than one 2mm voxel off-plane
        return img
    u = np.dot(rel, cut.u_axis)
    v = np.dot(rel, cut.v_axis)
    r = finding["radius_mm"]
    H, W = img.shape[:2]
    us = u_range[0] + np.arange(W) * px_mm
    vs = v_range[0] + np.arange(H) * px_mm
    uu, vv = np.meshgrid(us, vs)
    d = np.sqrt((uu - u) ** 2 + (vv - v) ** 2)
    ring = (d > r - 1.5) & (d < r + 1.5)
    out = img.copy()
    out[ring] = np.array([1.0, 1.0, 0.0])
    return out


# ---------------------------------------------------------------------------
# 2(b) 3D peel overview: orthographic, front-to-back (anterior camera, ray
# direction -y), axis-aligned so the reference can march voxel slabs directly
# instead of general ray-marching with trilinear resampling. The per-sample
# formulas below (opacity, colour, shading, compositing, clipping) are exactly
# what a general ray-marcher would do at each step; see docs/viz/SPEC.md.
# ---------------------------------------------------------------------------
def occupancy_gradient(labels, visible_mask_by_id, spacing):
    """'shading from a gradient of the visible-label occupancy': build a 0/1
    volume of currently-visible, non-background labels, smooth it slightly,
    and take its spatial gradient as a cheap surface normal."""
    occ = (visible_mask_by_id[labels] & (labels != 0)).astype(np.float32)
    occ = gaussian_filter(occ, sigma=1.0)
    gx, gy, gz = np.gradient(occ, spacing[0], spacing[1], spacing[2])
    norm = np.sqrt(gx * gx + gy * gy + gz * gz) + 1e-6
    return gx / norm, gy / norm, gz / norm


def render_peel(ct, labels, meta, layers, hidden_ids=(), cut=None, window="soft"):
    """2(b): orthographic front-to-back peel over the y axis (anterior view).
    If `cut` is given, samples on the plane's positive-normal side (the
    'viewer side', A1's tilt convention: +z is superior at tilt 0, +y is
    anterior at tilt 90) are clipped, and the first unclipped sample along
    each ray is painted fully opaque with the slice colour so the cut face
    reads as a flat cross-section, exactly like a real cut.

    Per-pixel formulas (front-to-back "over" compositing, standard volume
    rendering -- see docs/viz/SPEC.md for the shader form):
        for each sample, front to back:
            contribution = alpha(sample) * (1 - accumulated_alpha)
            accumulated_color += contribution * colour(sample) * shade(sample)
            accumulated_alpha += contribution
            stop early once accumulated_alpha > EARLY_TERMINATION_ALPHA
    """
    dims = np.array(labels.shape)
    spacing = np.array(meta["spacing_mm"])
    origin = np.array(meta["origin_mm"])
    color_lut, group_lut = build_lookup(layers)
    level, width = meta["window_presets"][window]

    group_alpha = np.zeros(256, dtype=np.float64)
    for gid, name in enumerate(group_lut):
        if name:
            group_alpha[gid] = GROUP_ALPHA_PER_2MM_STEP.get(name, 0.0)
    # alpha scaled for this (possibly downsampled) step size relative to the
    # 2mm bundle spacing the constants above were tuned at.
    step_scale = spacing[1] / 2.0
    alpha_by_label = 1 - (1 - group_alpha) ** step_scale

    visible = np.ones(256, dtype=bool)
    for hid in hidden_ids:
        visible[hid] = False
    visible[0] = False

    gx, gy, gz = occupancy_gradient(labels, visible, spacing)

    nx, ny, nz = dims
    acc_color = np.zeros((nx, nz, 3), dtype=np.float64)
    acc_alpha = np.zeros((nx, nz), dtype=np.float64)
    prev_clipped = None  # per-ray clip state one step closer to the camera

    xs = origin[0] + np.arange(nx) * spacing[0]
    zs = origin[2] + np.arange(nz) * spacing[2]
    grid_x, grid_z = np.meshgrid(xs, zs, indexing="ij")  # (nx, nz)

    dn = float(np.dot(RAY_DIR, cut.normal)) if cut is not None else 0.0

    for j in range(ny - 1, -1, -1):  # front (large y / anterior) -> back
        y = origin[1] + j * spacing[1]
        lab_slab = labels[:, j, :]
        alpha = alpha_by_label[lab_slab] * visible[lab_slab]
        colour = color_lut[lab_slab]
        shade = np.clip(AMBIENT + (1 - AMBIENT) * np.abs(
            gx[:, j, :] * LIGHT_DIR[0] + gy[:, j, :] * LIGHT_DIR[1] + gz[:, j, :] * LIGHT_DIR[2]), 0, 1)

        if cut is not None:
            pts = np.stack([grid_x, np.full_like(grid_x, y), grid_z], axis=-1)
            signed = (pts - cut.origin_mm) @ cut.normal
            # "viewer side" of the plane, defined relative to the camera ray
            # direction d (here the fixed anterior-to-posterior (0,-1,0) ray):
            # a point is nearer the camera than the plane along its own ray iff
            # dot(p-planeOrigin, N) and dot(rayDir, N) have opposite signs. This
            # is the general clip-plane test -- it still works for an arbitrary
            # ray direction, not just this axis-aligned camera (see SPEC.md).
            if abs(dn) > 1e-3:
                clipped = (signed * dn) < 0
            else:
                # ray runs parallel to the plane (e.g. tilt 0 viewed from the
                # front): every sample on a given ray has the same clip state,
                # so there is no crossing to expose as a face -- the kept half
                # just peel-renders normally and the clipped half stays empty.
                clipped = signed > 0
            alpha = np.where(clipped, 0.0, alpha)

            # the sample where a ray transitions from clipped to unclipped
            # (i.e. crosses the plane, front to back) becomes the opaque cut
            # face, coloured exactly like the 2(a) oblique slice at that point.
            if prev_clipped is None:
                prev_clipped = clipped
            face_here = prev_clipped & (~clipped)
            prev_clipped = clipped
            if face_here.any():
                voxel = (pts[face_here] - origin) / spacing
                hu = map_coordinates(ct, [voxel[:, 0], voxel[:, 1], voxel[:, 2]],
                                      order=1, mode="constant", cval=-1024, prefilter=False)
                face_lab = map_coordinates(labels.astype(np.float32),
                                            [voxel[:, 0], voxel[:, 1], voxel[:, 2]],
                                            order=0, mode="constant", cval=0, prefilter=False).astype(np.uint8)
                gray = window_soft(hu, level, width)
                gray3 = np.repeat(gray[:, None], 3, axis=1)
                vis_pixel = visible[face_lab]
                face_colour = color_lut[face_lab]
                face_alpha = np.where(vis_pixel, LAYER_OVERLAY_ALPHA, 0.0)[:, None]
                face_rgb = gray3 * (1 - face_alpha) + face_colour * face_alpha
                acc_color[face_here] = face_rgb
                acc_alpha[face_here] = 1.0

        remaining = 1 - acc_alpha
        active = remaining > (1 - EARLY_TERMINATION_ALPHA)
        contribution = np.where(active, alpha * remaining, 0.0)
        acc_color += contribution[..., None] * colour * shade[..., None]
        acc_alpha += contribution

    return np.clip(acc_color, 0, 1), acc_alpha


# ---------------------------------------------------------------------------
# CLI: renders the fixed set of PNGs the task asks for.
# ---------------------------------------------------------------------------
def downsample(ct, labels, meta, factor):
    if factor == 1:
        return ct, labels, meta
    ct_ds = ct[::factor, ::factor, ::factor]
    labels_ds = labels[::factor, ::factor, ::factor]
    meta_ds = dict(meta)
    meta_ds["dims"] = list(ct_ds.shape)
    meta_ds["spacing_mm"] = [s * factor for s in meta["spacing_mm"]]
    return ct_ds, labels_ds, meta_ds


def torso_pivot(meta):
    origin = np.array(meta["origin_mm"])
    dims = np.array(meta["dims"])
    spacing = np.array(meta["spacing_mm"])
    extent = dims * spacing
    return origin + extent * 0.5


def save_png(img, path, max_kb=300):
    plt.imsave(path, np.clip(img, 0, 1), origin="lower")
    size_kb = Path(path).stat().st_size / 1024
    tag = "OK" if size_kb <= max_kb else "OVER BUDGET"
    print(f"  {path}  {size_kb:.0f} KB  [{tag}]")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bundle_dir", nargs="?", default="data/out/body")
    ap.add_argument("work_dir", nargs="?", default="data/work")
    ap.add_argument("--out-dir", default="docs/viz")
    ap.add_argument("--peel-downsample", type=int, default=2,
                     help="Voxel stride for the 3D peel renders (speed).")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    meta, layers, ct, labels_raw = _load_bundle(args.bundle_dir)
    findings = json.loads((Path(args.bundle_dir) / "findings.json").read_text())
    labels, extra_layers = clean(labels_raw, ct, meta, args.work_dir)
    layers = layers + extra_layers
    print(f"cleaned bundle: {len(extra_layers)} extra organ layer(s) added")

    pivot = torso_pivot(meta)
    dims = np.array(meta["dims"])
    spacing = np.array(meta["spacing_mm"])
    extent = dims * spacing
    u_range = (-extent[0] / 2, extent[0] / 2)

    print("rendering oblique slices ...")
    for tilt in (0, 60, 90):
        cut = CutPlane(pivot, tilt)
        # v_axis is a mix of +y/+z at this tilt; size the crop to the volume's
        # own y/z half-extents projected onto v_axis, so each tilt frames the
        # torso tightly instead of leaving mostly-empty margin.
        v_half = abs(cut.v_axis[1]) * extent[1] / 2 + abs(cut.v_axis[2]) * extent[2] / 2
        v_range = (-v_half, v_half)
        img = render_slice(ct, labels, meta, layers, cut, u_range, v_range, px_mm=2.0, findings=findings)
        save_png(img, out_dir / f"slice_tilt{tilt}.png")

    print("rendering 3D peel overviews ...")
    ct_ds, labels_ds, meta_ds = downsample(ct, labels, meta, args.peel_downsample)

    peel_sets = [
        ("peel_all_layers", set()),
        ("peel_hide_skin_fat", {1, 2}),
        ("peel_hide_skin_fat_muscle", {1, 2, 3}),
    ]
    for name, hidden in peel_sets:
        img, _ = render_peel(ct_ds, labels_ds, meta_ds, layers, hidden_ids=hidden)
        save_png(np.transpose(img, (1, 0, 2)), out_dir / f"{name}.png")

    for tilt in (0, 60, 90):
        cut = CutPlane(pivot, tilt)
        img, _ = render_peel(ct_ds, labels_ds, meta_ds, layers, hidden_ids=set(), cut=cut)
        save_png(np.transpose(img, (1, 0, 2)), out_dir / f"peel_cut_tilt{tilt}.png")

    print("done.")


if __name__ == "__main__":
    main()
