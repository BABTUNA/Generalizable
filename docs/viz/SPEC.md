# Viz reference spec (L4-viz-reference)

Numpy reference: `scripts/viz/render_ref.py` (+ `scripts/viz/clean_labels.py` for the
label cleanup it renders on top of). This is the exact math the Metal render lane
should port; see `App/Core/CutPlane.swift` and `App/Core/CaseBundle.swift` for the
Swift-side names referenced throughout.

## 0. Label cleanup (feeds both shaders)

The raw A4 bundle's Fat/Muscle labels are an HU-threshold fallback (see
`data/work/build_body_bundle.py`), so they're salt-and-pepper speckle, worst over the
bowel where there's no TotalSegmentator organ label at all. `clean_labels.clean()`:

1. **3x3x3 majority filter, restricted to fat/muscle voxels, 3 iterations.** For every
   voxel currently labeled Fat(2) or Muscle(3), replace it with the most common label
   (any id, including background) in its 3x3x3 neighbourhood (26-neighbour + self).
   One pass only removes speckle whose neighbourhood already has a clear non-speckle
   majority; a fat/muscle checkerboard needs the boundary to erode inward repeatedly,
   so it iterates 3x (point of diminishing returns; see numbers below). All other
   labels are untouched.
2. **Add real organs from TotalSegmentator**, resampled from `data/work/ts_body_total/*.nii.gz`
   onto the bundle's grid with nearest-neighbor (`scipy.ndimage.affine_transform`,
   `order=0`), using each mask's own NIfTI affine for native spacing/origin against the
   bundle's `meta.json` `origin_mm` + 2mm `spacing_mm` — this is the transform step;
   there's no rotation in either grid so it's a diagonal scale + offset, not a general
   affine. New ids start at 13 (1-12 are taken): 13 Intestines (colon + small_bowel +
   duodenum + esophagus, unioned), 14 Pancreas, 15 Gallbladder, 16 Bladder
   (urinary_bladder). These overwrite whatever the majority filter left there — a real
   segmentation beats a threshold fallback. On this cadaver, Gallbladder resolves to
   zero voxels (TotalSegmentator found none) and is correctly omitted.

**Speckle metric** (count of fat/muscle connected components, 26-connectivity, smaller
than 5 voxels): **1515 before -> 222 after** on `data/out/body` (85% reduction; 1422 /
429 / 217 after 1/2/3 filter passes alone, before the organ overlay drops it further to
222). Run: `uv run --python 3.12 --with numpy --with scipy --with matplotlib --with nibabel python scripts/viz/clean_labels.py data/out/body data/work <out_dir>`.

## 1. Oblique slice shader

**Geometry** (`App/Core/CutPlane.swift`, A1/A4 — reference implements the identical
formulas in `render_ref.py`'s `CutPlane` class):

```
pointMM   = cutPlane.originMM + u * cutPlane.uAxis + v * cutPlane.vAxis
texCoord  = CaseBundle.textureCoord(forMM: pointMM)   // (voxel + 0.5) / dims
```

`u, v` are mm offsets in the fragment's local slice-space; `cutPlane.originMM` is
`pivotMM + normal * sliceOffsetMM`. Tilt 0 = axial (normal = +z); tilt rotates about
+x; rotation (unused here, held at 0) rotates about +z afterward.

**CT sampling**: linear filter (Metal: a sampler with `.linear`, or here
`scipy.ndimage.map_coordinates(order=1)`), then window:

```
gray = clamp((hu - (level - width/2)) / width, 0, 1)     // soft window: level=40, width=400
```

`hu = ctTexture.sample(linearSampler, texCoord).r * 32767.0` (r16Snorm round-trip, per
`CaseBundle.swift`'s header comment).

**Label sampling**: **nearest only** — `labelsTexture.read(uint3(voxelCoord), 0).r`
(never a filtering sampler; interpolating label ids is meaningless). Voxel coord is
`floor(pointMM - origin_mm) / spacing_mm)`, no `+0.5` (texel read, not a normalized
sampler fetch).

**Compositing** (per pixel, layers mode; `LAYER_OVERLAY_ALPHA = 0.42`):

```
color = layerColor[label]                  // layers.json #RRGGBB, alpha implicit 1
visible = label != 0 && !hidden[label]
alpha = visible ? 0.42 : 0.0
out = gray*(1-alpha) + color*alpha
if isBoundary(pixel) && visible: out = color              // full-colour outline
if !showLayers: out = vec3(gray)                          // hidden layers -> plain CT
```

`isBoundary(pixel)`: label at this pixel differs from any 4-neighbour (up/down/left/
right in slice-space, i.e. compare `label(u,v)` against `label(u±1px,v)`,
`label(u,v±1px)`) — draws a crisp 1px outline at full layer colour even where the fill
alpha is only 0.42, which is what makes organ borders read against a wash of similar
tissue colours.

**Finding ring**: if a finding's `center_mm` projects within one voxel (2mm) of the
plane along `normal`, draw a ring at `radius_mm` around its `(u,v)` projection
(`dot(center-origin, uAxis)`, `dot(center-origin, vAxis)`), full saturation yellow,
±1.5mm ring width. (Body case's `findings.json` is empty per A5, so no ring appears in
the shipped PNGs — the code path is exercised but has nothing to draw.)

**Window presets** used: `soft` (40/400) for every render here; `bone`/`brain`/`lung`
exist in `meta.json` and use the same formula with different level/width.

## 2. 3D peel overview shader

Orthographic, front-to-back, standard "over" compositing with early ray termination.
The numpy reference exploits an axis-aligned anterior camera (ray direction
`(0,-1,0)`, i.e. it marches whole `y`-index slabs of the volume instead of general
ray-marching with trilinear resampling) purely for speed — **the per-sample formulas
below are exactly what a general ray-marcher does at every step** and port directly;
only the "which points lie on which ray" bookkeeping would need to generalize for an
arbitrary camera.

**Per-sample opacity**, by `layers.json` `group`, calibrated at the bundle's native
2mm step (scale for a different step size `s` via `alpha_s = 1-(1-alpha_2mm)^(s/2)`):

| group | alpha @ 2mm |
|---|---|
| skin | 0.030 |
| fat | 0.060 |
| muscle | 0.150 |
| bone | 0.550 |
| organ | 0.350 |
| brain | 0.350 |

Hidden-layer ids get alpha forced to 0 (fully transparent, not just low) so peeling
skin/fat/muscle actually removes them rather than fading them.

**Shading** — "gradient of the visible-label occupancy": build `occ = (label != 0 &&
visible[label]) ? 1 : 0` over the whole volume, Gaussian-blur it lightly (`sigma=1`
voxel, so the gradient isn't just axis-aligned voxel-boundary noise), take
`gradient(occ)` as a normal-ish vector, normalize, and Lambert-shade:

```
shade = clamp(0.35 + 0.65 * abs(dot(normalize(grad(occ)), lightDir)), 0, 1)
lightDir = normalize(0.35, -0.55, 0.75)   // fixed, mostly-frontal-above key light
color_sample = layerColor[label] * shade
```

**Compositing per step** (front to back; `T` = accumulated alpha):

```
contribution = alpha(sample) * (1 - T)
accColor += contribution * color_sample
T += contribution
if T > 0.98: break               // early ray termination
```

**Cut-plane clip** (the tilt 0/60/90 renders): standard clip-plane test, generalizes to
any camera ray direction `d` (here fixed `(0,-1,0)`):

```
signed = dot(sampleMM - cutPlane.originMM, cutPlane.normal)
dn     = dot(d, cutPlane.normal)
clipped = abs(dn) > 1e-3 ? (signed * dn < 0)     // point is nearer camera than the plane along its own ray
                          : (signed > 0)         // ray parallel to plane (e.g. tilt 0, straight-on):
                                                  // no crossing exists; fall back to the plane's own +normal half
if clipped: alpha(sample) = 0
```

The sample where a ray transitions from clipped to unclipped (front to back) is the
plane crossing: paint it **fully opaque** with the oblique-slice color at that exact
point (§1's `gray*(1-a)+color*a`, boundary rule included) instead of the peel opacity,
so the cut face reads as a flat, crisp cross-section rather than a translucent smear.
Note the tilt-0 degenerate case in the table below — it's expected, not a bug: when
the plane is edge-on to the ray direction there is no per-ray crossing, so that render
just shows the kept half peeling normally with the other half fully removed, instead of
a flat face.

**Pivot for all three cut renders**: bundle geometric centre (`origin_mm + extent_mm/2`,
i.e. `App/Core/CaseBundle.swift`'s `centerMM`) — "the torso centre," since the body
case has no `findings.json` entries to anchor to.

## 3. Renders (docs/viz/, all under 300KB)

| File | What |
|---|---|
| `peel_all_layers.png` | Anterior peel, every layer visible |
| `peel_hide_skin_fat.png` | Skin+fat hidden -> muscle/bone/organs |
| `peel_hide_skin_fat_muscle.png` | +muscle hidden -> bone/organs only |
| `peel_cut_tilt0.png` | Peel + axial cut through torso centre (degenerate ray/plane case, see above) |
| `peel_cut_tilt60.png` | Peel + 60 deg oblique cut |
| `peel_cut_tilt90.png` | Peel + coronal cut (full flat cross-section) |
| `slice_tilt0.png` / `slice_tilt60.png` / `slice_tilt90.png` | Matching §1 oblique slices at the same tilts/pivot |

Peel renders use a 2x voxel stride (`--peel-downsample`, default 2) for speed; slices
render at full bundle resolution.

## 4. Metal-specific notes for the render lane

- **Texel-centre convention**: `CaseBundle.textureCoord(forMM:)` adds `+0.5` before
  dividing by `dims` because Metal's normalized-coordinate sampler expects texel
  *centers* at `(i+0.5)/dim`. That's only correct for the **CT** texture, sampled with
  a `.linear` sampler at normalized coordinates. For **labels**, don't use a sampler or
  normalized coordinates at all — use `texture.read(uint3(voxel), 0)` at the plain
  integer voxel index (`floor((pointMM - origin_mm) / spacing_mm)`, no `+0.5`,
  clamped to `[0, dim-1]`). Mixing these up (e.g. normalized-coord `+0.5` math feeding
  a `read()`, or linear-filtering the label texture) is the most likely source of a
  half-voxel drift between the CT and label layers or of blended/impossible label ids
  at boundaries.
- **r16Snorm CT**: HU is recovered as `value * 32767.0`, matching the int16 HU range
  bundle-side; do the window math in HU space after that multiply, not on the raw
  snorm value.
- **r8Uint labels**: always an integer read, never filtered — this is what makes the
  boundary-outline rule (§1) meaningful; a filtered label texture would smear ids at
  edges and the outline test would misfire.
