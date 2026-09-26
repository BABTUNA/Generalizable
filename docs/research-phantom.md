# Synthetic CT phantom generation and tissue label colors / Hounsfield ranges (for the Generalizable patient-CT case)

## Summary
The open-source pattern for a procedural CT phantom is a list of analytic primitives (ellipsoids, elliptic cylinders, spheres), each row = (value, half-axes a b c, center x y z, three Euler angles), rasterized by testing (R·(p−c))²·(1/a², 1/b², 1/c²) ≤ 1 inside a bounding box: ODL's `_ellipsoid_phantom_3d` (src/odl/core/phantom/geometric.py) and TomoPhantom's `Phantom3DLibrary.dat` (`Object : ellipsoid C0 x0 y0 z0 a b c phi1 phi2 phi3`) both do exactly this, and GE's XCIST (`gecatsim/phantom/*.ppm`) stores the same primitives in millimetres with a material index and z clip limits. scikit-image's `shepp_logan_phantom` is NOT procedural (it loads `data/phantom.png`), so do not cite it as a generator. The 4D XCAT is NURBS surfaces segmented from the Visible Human and is not open source; FORBILD's thorax phantom site could not be opened (404), so no open-source torso-layout precedent exists at the level of "where the liver goes" — the layout below is bespoke, built from the primitive format of ODL/TomoPhantom/XCIST and sized from anatomy. For turning a label volume into a gray CT, SynthSeg (`ext/lab2im/layers.py` `SampleConditionalGMM`: `image = stds_map * N(0,1) + means_map`, then `GaussianBlur` in `SynthSeg/labels_to_image_model.py`) is the well-maintained precedent: per-label mean and std, sample, blur for partial volume; we plug in Hounsfield means from Radiopaedia/Wikipedia. Tissue colors come straight from 3D Slicer's `Base/Logic/Resources/ColorFiles/GenericAnatomyColors.txt` (skin 177,122,101; fat 230,220,70; muscle 192,104,88; bone 241,214,145; lungs 197,165,145; liver 221,130,101; kidneys 185,102,83; heart 206,110,84; aorta 224,97,76; cyst 205,205,100; mass 144,238,144). Window/level presets come from Slicer's `Modules/Loadable/Volumes/Resources/VolumeDisplayPresets.json` (CT-Lung W1400/L-500, CT-Abdomen W350/L40, CT-Bone W1000/L400) and the mapping formula from cornerstone3D `toLowHighRange` (DICOM C.11.2.1.2.1). Axis convention: DICOM/ITK are LPS, NIfTI/Slicer-internal are RAS (nifti1.h: "+x = Right +y = Anterior +z = Superior"); we recommend LPS voxel order (i→patient Left, j→Posterior, k→Superior) because the standard radiological axial image then draws with zero flips. Because the phantom is analytic, the hinge-driven oblique cross-section should be evaluated per pixel against the primitive list (ODL's own docstring notes a 3D phantom can be evaluated as a slice), giving crisp cuts at any angle; the 128×128×192 label volume is only needed for the 3D overview.

## Precedents
- 3D Slicer (Slicer/Slicer) — https://github.com/Slicer/Slicer/blob/main/Base/Logic/Resources/ColorFiles/GenericAnatomyColors.txt — The GenericAnatomyColors lookup table: one line per label `id name R G B A` (e.g. `2 bone 241 214 145 255`, `3 skin 177 122 101 255`, `12 fat 230 220 70 255`, `8 muscle 192 104 88 255`, `172 right_lung 197 165 145 255`, `216 liver 221 130 101 255`, `222 right_kidney 185 102 83 255`, `180 heart 206 110 84 255`, `191 aorta 224 97 76 255`, `5 blood 216 101 79 255`, `309 cyst 205 205 100 255`, `7 mass 144 238 144 255`). No entry exists for nodule, calculus/stone, or aneurysm.
- 3D Slicer (Slicer/Slicer) — https://github.com/Slicer/Slicer/blob/main/Modules/Loadable/Volumes/Resources/VolumeDisplayPresets.json — Slicer's window/level presets as JSON: CT-Bone window 1000 level 400; CT-Air 1000/-426; CT-Brain 100/50; CT-Abdomen 350/40; CT-Lung 1400/-500; PET 10000/6000 (rainbow); DTI 1/0.5. Each has id, name, description, icon, window, level, color table.
- 3D Slicer (Slicer/Slicer) — https://github.com/Slicer/Slicer/blob/main/Modules/Loadable/VolumeRendering/Resources/presets.xml — Volume-rendering presets with HU->color/opacity ramps. CT-Lung colorTransfer: -1000 (0.3,0.3,1), -600 (0,0,1), -530 (0.13,0.78,0.07), -460 (0.93,1,0.11), -400 (0.89,0.25,0.02); opacity nonzero only -599..-400. CT-Fat opacity nonzero -99..-60. CT-Bone: opacity ramps from -16.4 to 641; colors -16.4 (0.73,0.25,0.30), 641 (0.91,0.82,0.55), 3071 white. CT-Muscle: -155 (0.55,0.25,0.15), 217.6 (0.88,0.60,0.29), 419.7 (1,0.94,0.95). CT-Soft-Tissue: gray ramp -160..240 HU.
- 3D Slicer documentation — https://slicer.readthedocs.io/en/latest/user_guide/coordinate_systems.html — LPS (Left, Posterior, Superior) is used in DICOM and ITK; RAS is the same with the first two axes flipped; Slicer stores RAS internally but assumes files are LPS. Defines axial (separates superior/inferior), coronal (anterior/posterior), sagittal (left/right).
- NIfTI C library (NIFTI-Imaging/nifti_clib) — https://github.com/NIFTI-Imaging/nifti_clib/blob/master/niftilib/nifti1.h (comment block around line 1003) — NIfTI-1 spec text: `+x = Right  +y = Anterior  +z = Superior. This is a right-handed coordinate system.` plus voxel storage order (i fastest, then j, then k).
- ODL (odlgroup/odl) — https://github.com/odlgroup/odl/blob/master/src/odl/core/phantom/geometric.py (`_ellipsoid_phantom_3d`, lines 462-583; `ellipsoid_phantom`, line 586) — Reference ellipsoid rasterizer: each row is `value, axis_1, axis_2, axis_3, center_x, center_y, center_z, rotation_phi, rotation_theta, rotation_psi` in the cube [-1,1]^3; grid is normalized to [-1,1]; a bounding box (`_getshapes_3d(center, max_radius, shape)`) limits the loop; points are rotated by a ZXZ Euler matrix, `radius = dot(rotated**2, [1/a², 1/b², 1/c²])`, `inside = radius <= 1`, `p[idx][inside] += intensity`. Docstring: if a space axis has shape 1, a slice of the 3D phantom is produced.
- ODL (odlgroup/odl) — https://github.com/odlgroup/odl/blob/master/src/odl/core/phantom/transmission.py (`_shepp_logan_ellipsoids_3d`, lines 39-56) — The canonical 3D Shepp-Logan table: 10 ellipsoids, e.g. `[2.00, .6900, .9200, .810, 0, 0, 0, 0, 0, 0]`, `[-.98, .6624, .8740, .780, 0, -.0184, 0, 0, 0, 0]`, `[-.02, .11, .31, .22, .22, 0, 0, -18deg, 0, 0]`; the 'modified' variant sets intensities [1, -0.8, -0.2, -0.2, 0.1 x6].
- TomoPhantom (dkazanc/TomoPhantom) — https://github.com/dkazanc/TomoPhantom/blob/master/tomophantom/phantomlib/Phantom3DLibrary.dat and https://github.com/dkazanc/TomoPhantom/blob/master/tomophantom/TomoP3D.py (Objects3D enum, lines 40-48) — Text phantom library format: `Object : <type> C0 x0 y0 z0 a b c angle1 angle2 angle3;` with types gaussian, paraboloid, ellipsoid, cone, cuboid, elliptical_cylinder; models declare `Model : N; Components : K; TimeSteps : 1;`. Model 13 is the 3D Shepp-Logan (10 ellipsoids, angles in degrees, coordinates in [-1,1]).
- XCIST / CatSim (xcist/main) — https://github.com/xcist/main/blob/master/gecatsim/phantom/CTDI_16cm_WaterAirPEBoneChambers.ppm and https://github.com/xcist/main/blob/master/gecatsim/pyfiles/Phantom_Analytic.py; materials in gecatsim/material/ncat_* — Analytic phantom format in millimetres with a material index: `materialList = {'PMMA' 'water' 'air' ...}`, then per object `center(i,:)=[x y z]`, `half_axes(i,:)=[a b c]`, `euler_angs`, `density`, `type`, `material`, `axial_lims` (z clip), `clip`. NCAT material densities (g/cm³): lung 0.26, adipose 0.92, water 1.00, muscle 1.05, kidney 1.05, liver 1.06, blood 1.06, skin 1.09, dry spine 1.42.
- scikit-image (scikit-image/scikit-image) — https://github.com/scikit-image/scikit-image/blob/main/src/_skimage2/data/_fetchers.py (`shepp_logan_phantom`, lines 1008-1022) — `shepp_logan_phantom()` returns `_load('data/phantom.png', as_gray=True)` (400x400 float64). It is a file loader, not a procedural generator; cite ODL/TomoPhantom for procedural ellipsoids instead.
- SynthSeg (BBillot/SynthSeg) — https://github.com/BBillot/SynthSeg/blob/master/ext/lab2im/layers.py (`SampleConditionalGMM`, lines 430-498) and https://github.com/BBillot/SynthSeg/blob/master/SynthSeg/labels_to_image_model.py (lines 183-220) — Label map -> intensity image: per-label means and stds are gathered per voxel and `return stds_map * tf.random.normal(tf.shape(labels)) + means_map`. The generator then applies `BiasFieldCorruption` (MRI-only), `IntensityAugmentation(clip=300)`, and `GaussianBlur(sigma, 1.03)` / `DynamicGaussianBlur(0.75 * max_res / atlas_res, 1.03)` to mimic acquisition resolution (partial volume).
- cornerstone3D (cornerstonejs/cornerstone3D) — https://github.com/cornerstonejs/cornerstone3D/blob/main/packages/core/src/utilities/windowLevel.ts (`toLowHighRange`, lines 53-78) — DICOM C.11.2.1.2.1 linear VOI LUT: `lower = windowCenter - 0.5 - (windowWidth - 1) / 2; upper = windowCenter - 0.5 + (windowWidth - 1) / 2` (LINEAR) or `lower = c - w/2; upper = c + w/2` (LINEAR_EXACT).
- Radiopaedia — https://radiopaedia.org/articles/hounsfield-unit — HU per tissue: air -1000; water 0; subcutaneous fat -100 to -115; lungs -950 to -650; renal cortex 25-30; spleen 40-45; liver 45-50; muscle 45-50; grey matter 40; white matter 30; trabecular bone 300-800; cortical bone >1000; metal >3000.
- Radiopaedia — https://radiopaedia.org/articles/windowing-ct — Window presets: brain W80/L40; subdural W130-300/L50-100; soft tissue (head/neck) W350-400/L20-60; lungs W1500/L-600; mediastinum W350/L50; vascular/heart W600/L200 (or W1000/L400); abdomen soft tissue W400/L50; liver W150/L30; spine soft tissue W250/L50; bone W1800/L400. Upper grey = WL + WW/2, lower grey = WL - WW/2.
- Wikipedia — https://en.wikipedia.org/wiki/Hounsfield_scale — HU = 1000 x (mu - mu_water)/(mu_water - mu_air). Table: fat -120 to -90; lung -700 to -600; urine/bile -5 to +15; CSF +15; blood unclotted +13 to +50; blood clotted +50 to +75; kidney +20 to +45; muscle +35 to +55; liver 60 +/- 6; soft tissue on contrast CT +100 to +300; cancellous bone +300 to +400; cortical bone +500 to +1900.
- Radiopaedia (finding-specific pages) — https://radiopaedia.org/articles/urolithiasis ; https://radiopaedia.org/articles/hepatic-cyst ; https://radiopaedia.org/articles/abdominal-aortic-aneurysm ; https://radiopaedia.org/articles/pulmonary-nodule — Calcium oxalate/phosphate stones 400-600 HU, uric acid 100-200 HU, stones >5 mm considered for intervention. Simple hepatic cyst: homogeneous water attenuation ~0-10 HU, imperceptible wall, no enhancement. AAA: abdominal aorta >3 cm or >50% over the proximal normal segment; 4.0-4.4 cm gets 1-year surveillance; repair generally >=5.4 cm. Pulmonary nodule: 6-30 mm rounded opacity (<6 mm = micronodule; >30 mm = mass); solid / part-solid / ground-glass.
- 4D XCAT phantom (Segars et al., Med Phys 2008 and 2010) - abstracts — https://www.osti.gov/biblio/22098534 (2010) and Europe PMC REST record for PMID 18777939 (2008) — XCAT is a whole-body model built from NURBS and subdivision surfaces segmented from the Visible Male/Female, scaled to 50th-percentile adults with ICRP 89 organ volumes; CT projections are computed by ray tracing the surfaces. It is described in papers, not shipped as open-source code, so it is a design reference only (organ-per-surface, material per organ), not a copyable implementation.
- FakeCT (aghcv/FakeCT) — https://github.com/aghcv/FakeCT (README) and src/fakect.py — README advertises mesh -> voxelize -> assign HU -> blur/noise, but the opened source contains no HU table or noise sigma (it is a VTI/mesh viewer with a separate learned 'fakenoise' model). Not a usable precedent for HU assignment; listed so nobody re-cites it.
- FORBILD analytic thorax/abdomen phantoms (Univ. Erlangen) — https://www.mib.med.fau.de/forbild/english/results/index.htm — Would be the closest thing to an open ellipse-based torso phantom with HU per object, but the page (and its old imp.uni-erlangen.de URL) returned 404/redirect; definitions could not be read. Treat the torso layout below as bespoke.

## Recommendations
- Represent the patient case as an ordered list of analytic primitives, one struct per row mirroring ODL `_ellipsoid_phantom_3d` / TomoPhantom `Object : ellipsoid C0 x0 y0 z0 a b c phi1 phi2 phi3`, but in millimetres with a label index and optional z-clip like XCIST's `.ppm` (`center`, `half_axes`, `euler_angs`, `material`, `axial_lims`). Kinds needed: ellipsoid, sphere (ellipsoid with a=b=c), ellipticCylinder (with zRange), and an optional periodic z-band mask for ribs.
- Rasterize the 128x128x192 label volume exactly like ODL: loop primitives in paint order, compute an integer bounding box from the half-axes, rotate (p - c) by the ZXZ Euler matrix, test `(rx/a)^2 + (ry/b)^2 + (rz/c)^2 <= 1`, and write the label. Deviation from ODL/TomoPhantom (which `+=` intensities): we REPLACE labels (painter's algorithm) because we are building a segmentation, not an attenuation image; the CT gray is derived afterwards via a lookup, following SynthSeg's label->image design.
- Generate the 'CT scan - what doctors see' image the SynthSeg way (`SampleConditionalGMM` then `GaussianBlur`): `hu = mean[label] + std[label] * gaussianNoise(hash(i,j,k))`, then a separable Gaussian blur with sigma ~0.6 voxel for partial volume. Use a deterministic hash-based noise (not a RNG stream) so the texture is stable frame to frame and identical on both Duo displays.
- For the live cross-section, evaluate the primitive list analytically per pixel of the cut plane (ODL's docstring explicitly supports evaluating a 3D phantom as a single slice). This gives a crisp oblique cut at every hinge angle with no trilinear smearing and makes the 9 mm stone / 14 mm nodule render at true size; use the voxel volume only for the 3D overview (surface extraction or ray-march) where 3 mm resolution is fine.
- Use Slicer GenericAnatomyColors RGB values verbatim for the seven patient layers (skin 177,122,101; fat 230,220,70; muscle 192,104,88; bone 241,214,145; lungs 197,165,145; organs: liver 221,130,101, spleen 157,108,162, kidneys 185,102,83; blood: heart 206,110,84, aorta 224,97,76). Store them in the case JSON as `label name R G B A` rows, the same shape as Slicer's file, so a designer can edit them without touching Swift.
- For findings, Slicer has no nodule/stone/aneurysm colors; use Slicer's `cyst` 205,205,100 for the hepatic cyst and `mass` 144,238,144 for the nodule if you want table-derived colors, but render finding PINS in the app accent color (one accent, all four findings) rather than tissue colors - findings are markers, not tissues. State this deviation in code comments.
- Ship Slicer's CT window/level presets by name and value from VolumeDisplayPresets.json (CT-Lung W1400/L-500, CT-Abdomen W350/L40, CT-Bone W1000/L400, CT-Air W1000/L-426, CT-Brain W100/L50) and auto-select per finding: nodule -> CT-Lung; aneurysm, cyst, stone -> CT-Abdomen. Implement the gray mapping with cornerstone3D's `toLowHighRange` LINEAR formula (`lower = L - 0.5 - (W-1)/2`, `upper = L - 0.5 + (W-1)/2`, gray = clamp((hu - lower)/(upper - lower), 0, 1)).
- Adopt DICOM/ITK LPS voxel ordering for the volume: i (0..127) increases toward patient Left, j (0..127) toward Posterior, k (0..191) toward Superior, 3.0 mm isotropic. This is the convention Slicer's docs say DICOM and ITK use, and it means the axial slice image is drawn with no flips (row 0 = anterior at top, column 0 = patient right at screen left, the standard radiological view). Map to the SceneKit/RealityKit scene as x = +i, y = +k (up), z = -j (toward camera = anterior); this triple is right-handed.
- Model the aneurysm as CT actually shows it, per Radiopaedia's AAA page and Wikipedia's clotted-blood HU: an outer 44 mm ellipsoid of mural thrombus (~60 HU) with an eccentric contrast-filled lumen (~250 HU). The normal aorta segments above and below (25 mm thoracic, 20 mm abdominal) make the widening obvious in both the colored and gray views.
- Label the CT view 'synthetic contrast-enhanced CT' in the UI: organ HU come from non-contrast published ranges (Radiopaedia/Wikipedia), while blood is set to +250 HU (inside Wikipedia's +100..+300 'soft tissue, contrast CT' range) so the aorta and heart are visible in gray. Keep all HU means/stds in the same case JSON as the colors so they are reviewable without a rebuild.

## Concrete values
## 1. Anatomical direction convention (recommended: DICOM/ITK LPS voxel order)

| Voxel axis | Count | Spacing | + direction | Index 0 is at | Source |
|---|---|---|---|---|---|
| i (x) | 128 | 3.0 mm | patient **Left** | patient right side | LPS per Slicer coordinate_systems.html ("used in DICOM", "ITK uses LPS") |
| j (y) | 128 | 3.0 mm | **Posterior** | anterior (front) | same |
| k (z) | 192 | 3.0 mm | **Superior** | inferior (feet end) | same; NIfTI/RAS also has +z = Superior (nifti1.h) |

Physical FOV: 384 × 384 × 576 mm. mm ↔ voxel: `x_mm = (i − 64)·3`, `y_mm = (j − 64)·3`, `z_mm = k·3`; `i = round(x/3)+64`, `j = round(y/3)+64`, `k = round(z/3)`. Origin (x=0,y=0) is the torso center; z=0 is the bottom (inferior) edge of the scan box.

Alternative (NIfTI / Slicer-internal RAS, nifti1.h line ~1003: `+x = Right +y = Anterior +z = Superior`): identical except x and y signs flipped. If you ever export to NIfTI, negate x and y.

Display rules (radiological convention):
- Axial image: column = i (screen-left = patient right), row = j (top = anterior). No flips.
- Coronal image: column = i, row = (191 − k) (top = superior).
- Sagittal image: column = j (left of screen = anterior), row = (191 − k).
- 3D scene (SceneKit/RealityKit, y-up, z toward camera): `scene = ((i−64)·s, (k−96)·s, −(j−64)·s)`. Right-handed: L × S = A.
- Hinge cut plane rotates about the patient left–right axis (i): normal = (0, −sinθ, cosθ) in (i,j,k) with θ = 0 axial (device 180°), θ = 90° coronal (device 90°).

## 2. Slicer GenericAnatomyColors RGB (verbatim from Base/Logic/Resources/ColorFiles/GenericAnatomyColors.txt)

| Slicer id | Slicer name | R G B | Hex | Our use |
|---|---|---|---|---|
| 3 | skin | 177 122 101 | #B17A65 | Layer **Skin** |
| 12 | fat | 230 220 70 | #E6DC46 | Layer **Fat** |
| 8 | muscle | 192 104 88 | #C06858 | Layer **Muscle** (also soft-tissue fill) |
| 2 | bone | 241 214 145 | #F1D691 | Layer **Bone** (default) |
| 201 | ribs | 253 232 158 | #FDE89E | Bone (optional per-part) |
| 200 | thoracic_vertebral_column | 226 202 134 | #E2CA86 | Bone (optional) |
| 246 | lumbar_vertebral_column | 212 188 102 | #D4BC66 | Bone (optional) |
| 202 | sternum | 244 217 154 | #F4D99A | Bone (optional) |
| 172 / 173 | right_lung / left_lung | 197 165 145 | #C5A591 | Layer **Lungs** |
| 170 | trachea | 182 228 255 | #B6E4FF | Lungs group (air tube) |
| 216 | liver | 221 130 101 | #DD8265 | Layer **Organs** |
| 220 | spleen | 157 108 162 | #9D6CA2 | Organs |
| 222 / 223 | right_kidney / left_kidney | 185 102 83 | #B96653 | Organs |
| 180 | heart | 206 110 84 | #CE6E54 | Layer **Blood** |
| 191 | aorta | 224 97 76 | #E0614C | Blood |
| 5 | blood | 216 101 79 | #D8654F | Blood (generic) |
| 17 / 16 | artery / vein | 216 101 79 / 0 151 206 | #D8654F / #0097CE | optional |
| 115 | spinal_cord | 244 214 49 | #F4D631 | spinal canal |
| 309 | cyst | 205 205 100 | #CDCD64 | Finding: hepatic cyst |
| 7 | mass | 144 238 144 | #90EE90 | Finding: nodule (only table option) |
| 1 | tissue | 128 174 128 | #80AE80 | generic |
| 29 | gas | 218 255 255 | #DAFFFF | air/gas |
| 0 | background | 0 0 0 0 | — | outside body |

Slicer has **no** entry for nodule, calculus/stone, or aneurysm. Recommend finding pins use one app accent color; tissue colors above are for layers only.

File format to copy (Slicer): `# comment lines` then `id name R G B A` per line, names snake_case.

## 3. Hounsfield units per tissue (cited) and demo values

| Label | Tissue | Cited range (source) | Demo mean HU | Demo σ HU |
|---|---|---|---|---|
| 0 | air (outside body, trachea) | −1000 (Radiopaedia HU; Wikipedia) | −1000 | 8 |
| 1 | skin | not listed; soft tissue ≈ muscle 35–55 (Wikipedia) | 45 | 15 |
| 2 | fat (subcutaneous) | −100 to −115 (Radiopaedia); −120 to −90 (Wikipedia) | −100 | 12 |
| 3 | muscle / soft-tissue fill | 45–50 (Radiopaedia); 35–55 (Wikipedia) | 45 | 12 |
| 4 | bone, cortical (ribs, sternum, vertebral shell) | >1000 (Radiopaedia); 500–1900 (Wikipedia) | 1000 | 80 |
| 5 | bone, trabecular (vertebral body interior) | 300–800 (Radiopaedia); cancellous 300–400 (Wikipedia) | 350 | 60 |
| 6/7 | lung parenchyma | −950 to −650 (Radiopaedia); −700 to −600 (Wikipedia) | −780 | 45 |
| 8 | heart (blood pool, contrast) | contrast soft tissue +100..+300 (Wikipedia) | 200 | 18 |
| 9 | liver | 45–50 (Radiopaedia); 60 ± 6 (Wikipedia) | 55 | 12 |
| 10 | spleen | 40–45 (Radiopaedia) | 42 | 12 |
| 11/12 | kidney | cortex 25–30 (Radiopaedia); 20–45 (Wikipedia) | 32 | 12 |
| 13 | aorta lumen (contrast) | +100..+300 (Wikipedia contrast CT); unclotted blood 13–50 (Wikipedia) | 250 | 18 |
| 15 | spinal canal (CSF) | +15 (Wikipedia) | 15 | 8 |
| 20 | lung nodule (solid) | soft-tissue attenuation; no HU on Radiopaedia nodule page → use muscle range 35–55 | 40 | 12 |
| 21 | AAA lumen (contrast) | as aorta | 250 | 18 |
| 22 | AAA mural thrombus | clotted blood +50..+75 (Wikipedia) | 60 | 12 |
| 23 | hepatic cyst | 0–10 HU water attenuation (Radiopaedia hepatic cyst) | 5 | 8 |
| 24 | renal calculus | calcium stones 400–600 HU (Radiopaedia urolithiasis) | 500 | 60 |

Density cross-check (XCIST `gecatsim/material/ncat_*`, g/cm³): lung 0.26, adipose 0.92, water 1.00, muscle 1.05, kidney 1.05, liver 1.06, blood 1.06, skin 1.09, dry spine 1.42.

HU definition (Wikipedia): `HU = 1000 × (μ − μ_water) / (μ_water − μ_air)`.

## 4. Window/level presets

| Name | Window | Level | Source | Use for |
|---|---|---|---|---|
| CT-Lung | 1400 | −500 | Slicer VolumeDisplayPresets.json | Lung nodule |
| CT-Abdomen | 350 | 40 | Slicer | AAA, cyst, stone |
| CT-Bone | 1000 | 400 | Slicer | optional (stone) |
| CT-Air | 1000 | −426 | Slicer | — |
| CT-Brain | 100 | 50 | Slicer | — |
| Lungs | 1500 | −600 | Radiopaedia windowing-ct | alt |
| Mediastinum | 350 | 50 | Radiopaedia | alt |
| Abdomen soft tissue | 400 | 50 | Radiopaedia | alt |
| Liver | 150 | 30 | Radiopaedia | alt (cyst) |
| Vascular | 600 | 200 | Radiopaedia | alt (AAA) |
| Bone | 1800 | 400 | Radiopaedia | alt |

Gray mapping (cornerstone3D `toLowHighRange`, DICOM C.11.2.1.2.1 LINEAR):
```
lower = L - 0.5 - (W - 1) / 2
upper = L - 0.5 + (W - 1) / 2
gray  = clamp((hu - lower) / (upper - lower), 0, 1)
```
(Radiopaedia's simpler form: upper = L + W/2, lower = L − W/2.)

## 5. Label → CT gray pipeline (SynthSeg pattern)

```
// 1. per-voxel intensity sample  (lab2im/layers.py SampleConditionalGMM)
hu[v] = mean[label[v]] + std[label[v]] * N01(hash(i, j, k, seed))
// 2. partial-volume blur         (labels_to_image_model.py GaussianBlur)
hu = gaussianBlur3D(hu, sigma = 0.6 voxel)   // separable, 5-tap
// 3. store Int16 (128*128*192*2 B = 6.3 MB), clamp to [-1024, 3071]
// 4. display
gray = windowLevel(hu, preset)
```
Noise: Box–Muller on two 32-bit hashes of (i,j,k,seed) (e.g. PCG/xxhash-style integer hash) — deterministic, tileable, identical on both Duo screens. For the analytic per-pixel slice, quantize the cut-plane sample position to a 1 mm grid before hashing so the noise is fixed in 3D as the plane tilts.

Deviation from SynthSeg: skip `BiasFieldCorruption` (MRI artifact) and skip the random-resolution `MimicAcquisition`; fixed sigma is enough for CT.

## 6. Primitive format (Swift), mirroring ODL/TomoPhantom rows + XCIST mm units

```swift
enum PrimitiveKind: String, Codable { case ellipsoid, ellipticCylinder }
struct Primitive: Codable {
  var kind: PrimitiveKind
  var label: UInt8                 // XCIST object.material
  var center: SIMD3<Float>         // mm, LPS (x=L, y=P, z=S)
  var halfAxes: SIMD3<Float>       // mm a,b,c  (ODL axis_1..3, XCIST half_axes)
  var eulerDeg: SIMD3<Float> = .zero   // phi, theta, psi (ODL ZXZ order; TomoPhantom uses degrees)
  var zRange: ClosedRange<Float>? = nil // ellipticCylinder only (XCIST axial_lims)
  var zBand: (period: Float, width: Float)? = nil  // optional periodic mask for ribs
}
```
Rasterization (ODL `_ellipsoid_phantom_3d`, replace instead of add):
```
for prim in primitives (paint order):
  bbox = voxel box of center ± R·halfAxes (ODL: max_radius = sqrt(|mat|·[a²,b²,c²]))
  for voxel v in bbox:
    d = R(phi,theta,psi) * (p_mm(v) - center)
    inside = (d.x/a)² + (d.y/b)² + (d.z/c)² <= 1     // ellipsoid
    inside = (d.x/a)² + (d.y/b)² <= 1 && z in zRange  // ellipticCylinder
    if inside && (zBand == nil || (z - zRange.lower) mod period < width): label[v] = prim.label
```
ODL rotation matrix (ZXZ Euler, quoted from geometric.py):
```
[[ cψcφ − cθsφsψ,  cψsφ + cθcφsψ,  sψsθ],
 [−sψcφ − cθsφcψ, −sψsφ + cθcφcψ,  cψsθ],
 [ sθsφ,          −sθcφ,           cθ ]]
```

## 7. Recommended body layout (mm, LPS; paint in this order)

Labels: 0 air · 1 skin · 2 fat · 3 muscle · 4 bone_cortical · 5 bone_trabecular · 6 lung_R · 7 lung_L · 8 heart · 9 liver · 10 spleen · 11 kidney_R · 12 kidney_L · 13 aorta · 14 trachea(air) · 15 spinal_canal · 20 nodule · 21 AAA_lumen · 22 AAA_thrombus · 23 cyst · 24 calculus.
Layer groups: Skin{1} Fat{2} Muscle{3} Bone{4,5} Lungs{6,7,14} Organs{9,10,11,12} Blood{8,13,21,22}. Findings {20–24} are always drawn as pins.

| # | Structure | Kind | Label | Center (x, y, z) mm | Half-axes (a, b, c) mm | z range / notes |
|---|---|---|---|---|---|---|
| 1 | Body (skin) | ellipticCylinder | 1 | (0, 0, —) | (165, 110, —) | z 0–576 (body cropped by scan box top & bottom, as real CT is) |
| 2 | Subcutaneous fat | ellipticCylinder | 2 | (0, 0, —) | (162, 107, —) | z 0–576 (skin = 3 mm shell) |
| 3 | Muscle / soft-tissue fill | ellipticCylinder | 3 | (0, 0, —) | (147, 92, —) | z 0–576 (fat = 15 mm ring) |
| 4 | Right lung | ellipsoid | 6 | (−62, 8, 420) | (55, 60, 120) | apex z 540, base z 300 |
| 5 | Left lung | ellipsoid | 7 | (62, 8, 420) | (52, 60, 118) | slightly smaller (heart) |
| 6 | Trachea | ellipticCylinder | 14 | (0, −10, —) | (9, 9, —) | z 470–576 |
| 7 | Heart | ellipsoid | 8 | (22, −22, 390) | (55, 45, 55) | optional eulerDeg (−30, 0, 0); painted after lungs = cardiac notch |
| 8 | Liver | ellipsoid | 9 | (−55, 5, 270) | (85, 72, 80) | dome (z 350) intrudes into right lung base = diaphragm look |
| 9 | Spleen | ellipsoid | 10 | (100, 38, 290) | (26, 40, 52) | |
| 10 | Right kidney | ellipsoid | 11 | (−62, 50, 195) | (28, 18, 55) | sits lower than left |
| 11 | Left kidney | ellipsoid | 12 | (62, 50, 205) | (28, 18, 55) | |
| 12 | Thoracic aorta | ellipticCylinder | 13 | (12, 20, —) | (12.5, 12.5, —) | z 250–470 (25 mm Ø), left-anterior of spine |
| 13 | Abdominal aorta | ellipticCylinder | 13 | (12, 20, —) | (10, 10, —) | z 130–250 (20 mm Ø; bifurcation at z 130) |
| 14 | Iliac arteries (optional) | ellipticCylinder ×2 | 13 | (±22, 28, —) | (6, 6, —) | z 60–130 |
| 15 | Ribs | ellipticCylinder shell | 4 | (0, 0, —) | outer (140, 86), inner (134, 80) | z 300–540; zBand period 24 mm, width 9 mm (paint outer as 4, inner as 3 within bands) |
| 16 | Sternum | ellipticCylinder | 4 | (0, −84, —) | (15, 5, —) | z 340–500 |
| 17 | Vertebral column shell | ellipticCylinder | 4 | (0, 64, —) | (16, 22, —) | z 0–576 |
| 18 | Vertebral body interior | ellipticCylinder | 5 | (0, 64, —) | (13, 19, —) | z 0–576; optional discs: zBand period 30, width 6 painted label 3 |
| 19 | Spinal canal | ellipticCylinder | 15 | (0, 72, —) | (6, 6, —) | z 0–576 |
| 20 | Pelvic wings (optional) | ellipsoid ×2 | 4 then 5 | (±78, 25, 60) | (45, 25, 50) then (39, 19, 44) | |
| 21 | **AAA mural thrombus** | ellipsoid | 22 | (12, 20, 175) | (22, 22, 30) | 44 mm max diameter, infrarenal (below kidneys z≈150–260 lower pole, above bifurcation 130) |
| 22 | **AAA lumen** | ellipsoid | 21 | (10, 18, 175) | (13, 13, 28) | eccentric contrast lumen; if no thrombus, paint #21 as label 21 |
| 23 | **Lung nodule 14 mm, RUL** | ellipsoid (sphere) | 20 | (−75, −15, 500) | (7, 7, 7) | inside right lung: normalized r² = 0.65 |
| 24 | **Hepatic cyst 2.4 cm** | sphere | 23 | (−80, −10, 280) | (12, 12, 12) | right lobe; normalized r² = 0.15 |
| 25 | **Left renal calculus 9 mm** | sphere | 24 | (46, 50, 205) | (4.5, 4.5, 4.5) | medial left kidney; normalized r² = 0.33 |

Paint order rationale: soft shells → lungs/trachea → heart → liver/spleen/kidneys → aorta → bone (bone must win over big soft blobs) → findings (win over everything).

Finding anchors in voxel coordinates (i, j, k) at 3 mm:

| Finding | mm (x,y,z) | voxel (i,j,k) | radius vox | Default W/L |
|---|---|---|---|---|
| Lung nodule | (−75, −15, 500) | (39, 59, 167) | 2.3 | CT-Lung 1400/−500 |
| AAA | (12, 20, 175) | (68, 71, 58) | (7.3, 7.3, 10) | CT-Abdomen 350/40 |
| Hepatic cyst | (−80, −10, 280) | (37, 61, 93) | 4.0 | CT-Abdomen 350/40 |
| Renal calculus | (46, 50, 205) | (79, 81, 68) | 1.5 | CT-Abdomen 350/40 (saturates white) |

Sanity checks done on this layout: lungs stay inside the inner rib ring (lung y ≤ 68 vs ring y 71 at x = 62; lung x ≤ 117 vs ring x 133); AAA y range −2..42 just touches the vertebral shell (y 42..86); left kidney x 34..90 touches AAA at x 34; liver lateral edge reaches x −140 inside the muscle ring (147). Small overlaps are resolved by paint order.

## 8. Slicer volume-rendering HU→color ramps (optional colored-CT mode, from presets.xml)

- CT-Lung: −1000 (0.3,0.3,1.0) · −600 (0,0,1) · −530 (0.13,0.78,0.07) · −460 (0.93,1,0.11) · −400 (0.89,0.25,0.02); opacity nonzero −599..−400.
- CT-Bone: −16.4 (0.73,0.25,0.30) · 641 (0.91,0.82,0.55) · 3071 (1,1,1); opacity ramps −16..641.
- CT-Muscle: −155 (0.55,0.25,0.15) · 218 (0.88,0.60,0.29) · 420 (1,0.94,0.95).
- CT-Fat opacity band: −99..−60 HU. CT-Soft-Tissue: gray ramp −160..240 HU.

## 9. Clinical numbers for the finding copy (cited)

- Nodule: 6–30 mm = nodule, <6 mm micronodule, >30 mm mass (Radiopaedia pulmonary-nodule).
- AAA: >3 cm or >50% over adjacent normal segment; 4.0–4.4 cm → 1-year surveillance; repair usually ≥5.4 cm; ≥5 mm growth in 6 months is a concern (Radiopaedia AAA).
- Hepatic cyst: 0–10 HU, imperceptible wall, no enhancement, benign, no malignant potential (Radiopaedia hepatic-cyst).
- Renal calculus: calcium stones 400–600 HU; stones >5 mm considered for intervention (Radiopaedia urolithiasis).

## Risks
- No open-source torso-layout precedent was readable: FORBILD's thorax/abdomen phantom pages returned 404, XCAT is NURBS-from-Visible-Human and not open source, and TomoPhantom/ODL ship only Shepp-Logan-style test phantoms. The organ positions/sizes in section 7 are bespoke (anatomy-sized, primitive format copied from ODL/TomoPhantom/XCIST); a clinician should eyeball one axial and one coronal slice before the pitch.
- Slicer's lung color (197,165,145, tan) has low contrast against skin (177,122,101) and muscle (192,104,88); if the peel-away demo reads poorly, the sanctioned deviation is Slicer's trachea blue (182,228,255) or pulmonary_arterial_system blue (0,122,171) for the Lungs layer, stated in code as a deliberate departure from GenericAnatomyColors.
- At 3.0 mm isotropic voxels the 9 mm renal calculus is only 3 voxels across and the 14 mm nodule ~5; the voxel volume alone will look blobby. Evaluate the cut plane analytically per pixel (ODL slice pattern) or the small findings will not be convincing.
- HU values mix non-contrast organ ranges with contrast-enhanced blood (+250 HU); this is a plausible 'arterial-phase CTA' look but not a single real protocol. Label the view as synthetic contrast-enhanced CT; do not present the numbers as measured.
- scikit-image's shepp_logan_phantom is a PNG loader and FakeCT's README claims (voxelize/HU/noise) are not backed by its source; neither should be cited as the generator precedent in the codebase.
- Painter's-order overlaps (AAA vs vertebra, left kidney vs spleen, liver dome vs right lung base) are intentional but fragile; if someone edits radii, re-run the containment checks in section 7 (normalized r² < 1 for each finding inside its host organ).
- Left/right flips are the classic bug: LPS (recommended) and RAS (NIfTI/Slicer-internal) differ by sign on x and y. Verify with the liver: it must appear on screen-LEFT in the axial view (patient right) and on the patient's right in the 3D overview.
- GitHub's search API rate-limited during research; implementers re-checking sources should curl raw.githubusercontent.com URLs directly (all paths above were verified that way).
