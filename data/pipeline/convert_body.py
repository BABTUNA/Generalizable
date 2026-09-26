import glob, sys
import SimpleITK as sitk
import numpy as np
import nibabel as nib

series_dir_glob = "data/raw/vhp_male_ct/**/CT_1.3.6.1.4.1.5962.1.3.1174.2.1672334394.26545"
series_dir = glob.glob(series_dir_glob, recursive=True)[0]
print("series dir:", series_dir)

reader = sitk.ImageSeriesReader()
files = reader.GetGDCMSeriesFileNames(series_dir)
print("n files:", len(files))
reader.SetFileNames(files)
img = reader.Execute()  # already applies RescaleSlope/Intercept -> HU
print("size:", img.GetSize(), "spacing:", img.GetSpacing(), "origin:", img.GetOrigin())

arr = sitk.GetArrayFromImage(img)  # z, y, x
print("HU range:", arr.min(), arr.max())
print("dtype:", arr.dtype)

# Build a nibabel image. SimpleITK is LPS; nibabel/NIfTI wants RAS-ish affine (world = LPS -> convert by flipping x,y sign)
spacing = img.GetSpacing()  # (sx, sy, sz)
origin = img.GetOrigin()    # LPS
direction = img.GetDirection()
dir_mat = np.array(direction).reshape(3, 3)

# Affine mapping voxel (i,j,k) -> LPS mm
affine_lps = np.eye(4)
affine_lps[:3, :3] = dir_mat @ np.diag(spacing)
affine_lps[:3, 3] = origin

# Convert LPS -> RAS: flip x and y
lps_to_ras = np.diag([-1, -1, 1, 1])
affine_ras = lps_to_ras @ affine_lps

# arr is (z,y,x) -> transpose to (x,y,z) for nibabel
vol_xyz = np.transpose(arr, (2, 1, 0)).astype(np.int16)

nii = nib.Nifti1Image(vol_xyz, affine_ras)
nii_canon = nib.as_closest_canonical(nii)
print("canonical shape:", nii_canon.shape, "affine:\n", nii_canon.affine)

nib.save(nii_canon, "data/work/body_ct.nii.gz")
print("saved data/work/body_ct.nii.gz")

data = nii_canon.get_fdata()
print("HU min/max/mean:", data.min(), data.max(), data.mean())
print("percentiles 0.5/50/99.5:", np.percentile(data, [0.5, 50, 99.5]))
