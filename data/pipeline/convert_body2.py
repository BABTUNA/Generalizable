import glob
import numpy as np
import pydicom
import nibabel as nib
from scipy.interpolate import interp1d

series_dir_glob = "data/raw/vhp_male_ct/**/CT_1.3.6.1.4.1.5962.1.3.1174.2.1672334394.26545"
series_dir = glob.glob(series_dir_glob, recursive=True)[0]
files = glob.glob(series_dir + "/*.dcm")
print("n files:", len(files))

slices = []
for f in files:
    ds = pydicom.dcmread(f)
    z = float(ds.ImagePositionPatient[2])
    slices.append((z, ds))
slices.sort(key=lambda t: t[0])

zs = np.array([s[0] for s in slices])
diffs = np.diff(zs)
print("z range:", zs.min(), zs.max(), "median spacing:", np.median(diffs), "min:", diffs.min(), "max:", diffs.max())
dupz = np.sum(diffs < 1e-3)
print("duplicate z positions:", dupz)
if dupz:
    # drop exact duplicate z slices, keep first occurrence
    keep = [0]
    for i in range(1, len(slices)):
        if zs[i] - zs[keep[-1]] > 1e-3:
            keep.append(i)
    slices = [slices[i] for i in keep]
    zs = np.array([s[0] for s in slices])
    print("after dedup n:", len(slices))

ds0 = slices[0][1]
rows, cols = int(ds0.Rows), int(ds0.Columns)
px_sp = [float(x) for x in ds0.PixelSpacing]  # [row spacing(y), col spacing(x)]
origin_xy = [float(x) for x in ds0.ImagePositionPatient[:2]]
slope = float(getattr(ds0, "RescaleSlope", 1))
intercept = float(getattr(ds0, "RescaleIntercept", 0))
print("pixel spacing (row,col):", px_sp, "rescale", slope, intercept)

n = len(slices)
arr = np.zeros((n, rows, cols), dtype=np.float32)
for i, (z, ds) in enumerate(slices):
    p = ds.pixel_array.astype(np.float32)
    sl = float(getattr(ds, "RescaleSlope", slope))
    ic = float(getattr(ds, "RescaleIntercept", intercept))
    arr[i] = p * sl + ic

# arr is (z_irregular, row=y, col=x). Resample along z to uniform spacing = min observed spacing (clamped floor 1mm)
target_dz = max(1.0, float(np.min(np.diff(zs))))
z_uniform = np.arange(zs.min(), zs.max() + 1e-6, target_dz)
print("resampling z to uniform spacing:", target_dz, "-> n_z:", len(z_uniform))

f_interp = interp1d(zs, arr, axis=0, kind="linear", assume_sorted=True)
arr_uniform = f_interp(z_uniform).astype(np.int16)  # (z, y, x)

# Build affine: x,y from pixel spacing/origin (LPS), z from uniform spacing starting at zs.min()
sx, sy = px_sp[1], px_sp[0]  # col spacing = x, row spacing = y
ox, oy = origin_xy
sz = target_dz
oz = float(z_uniform[0])

affine_lps = np.array([
    [sx, 0, 0, ox],
    [0, sy, 0, oy],
    [0, 0, sz, oz],
    [0, 0, 0, 1],
], dtype=np.float64)
lps_to_ras = np.diag([-1, -1, 1, 1]).astype(np.float64)
affine_ras = lps_to_ras @ affine_lps

vol_xyz = np.transpose(arr_uniform, (2, 1, 0))  # x,y,z
nii = nib.Nifti1Image(vol_xyz, affine_ras)
nii_canon = nib.as_closest_canonical(nii)
print("canonical shape:", nii_canon.shape)
print("canonical affine:\n", nii_canon.affine)

nib.save(nii_canon, "data/work/body_ct.nii.gz")
data = nii_canon.get_fdata()
print("HU min/max/mean:", data.min(), data.max(), data.mean())
print("percentiles 0.5/50/99.5:", np.percentile(data, [0.5, 50, 99.5]))
print("saved data/work/body_ct.nii.gz")
