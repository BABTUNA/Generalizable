"""De-tilt (gantry tilt correction) + RAS-canonicalize the chosen CQ500 case.
Seg-CQ500's CT.nii has a real gantry-tilt affine (a small shear between the y and z
axes) -- ITK/SimpleITK refuses to even read it ("only supports orthonormal
direction cosines"). A4's axis-aligned bundle format can't represent a shear
either, so resample onto a proper axis-aligned RAS grid using the full affine
(nibabel reads it fine; scipy.ndimage.affine_transform handles the general
linear map, not just a diagonal one).
"""
import nibabel as nib
import numpy as np
from scipy.ndimage import affine_transform

CASE = "CQ500-CT-243"
CT_IN = f"data/work/seg_cq500_check/{CASE}_CT.nii"
MASK_IN = f"data/work/seg_cq500_check/{CASE}_ICH_mask.nii.gz"

ct_img = nib.load(CT_IN)
mask_img = nib.load(MASK_IN)
ct = ct_img.get_fdata().astype(np.float32)
mask = np.asarray(mask_img.dataobj)
affine_in = ct_img.affine
print("CT shape", ct.shape, "affine\n", affine_in)
assert mask.shape == ct.shape, f"mask shape {mask.shape} != ct shape {ct.shape}"

A_lin = affine_in[:3, :3]
t_in = affine_in[:3, 3]
A_inv = np.linalg.inv(A_lin)

# physical (RAS mm) bounding box of all 8 voxel-grid corners
shape = ct.shape
corners_ijk = np.array([[i, j, k] for i in (0, shape[0] - 1) for j in (0, shape[1] - 1) for k in (0, shape[2] - 1)])
corners_world = corners_ijk @ A_lin.T + t_in
lo = corners_world.min(axis=0)
hi = corners_world.max(axis=0)
print("RAS bbox lo/hi:", lo, hi)

in_spacing = np.abs(np.diag(A_lin)) if np.allclose(A_lin, np.diag(np.diag(A_lin))) else np.linalg.norm(A_lin, axis=0)
out_spacing = np.array([min(in_spacing[0], in_spacing[1])] * 2 + [in_spacing[2]])
out_origin = lo
out_shape = tuple((np.ceil((hi - lo) / out_spacing).astype(int) + 1).tolist())
print("out_spacing", out_spacing, "out_shape", out_shape, "out_origin", out_origin)

S_out = np.diag(out_spacing)
matrix = A_inv @ S_out
offset = A_inv @ (out_origin - t_in)

ct_out = affine_transform(ct, matrix, offset=offset, output_shape=out_shape, order=1,
                           mode="constant", cval=-1024.0).astype(np.int16)
mask_out = affine_transform(mask.astype(np.float32), matrix, offset=offset, output_shape=out_shape, order=0,
                             mode="constant", cval=0.0)
mask_out = np.round(mask_out).astype(np.uint8)

print("ct HU range after resample:", ct_out.min(), ct_out.max())
print("mask voxel count after resample:", int((mask_out > 0).sum()), "(before:", int((mask > 0).sum()), ")")

affine_out = np.eye(4)
affine_out[:3, :3] = S_out
affine_out[:3, 3] = out_origin

nii_ct = nib.Nifti1Image(ct_out, affine_out)
nii_ct_canon = nib.as_closest_canonical(nii_ct)
nii_mask = nib.Nifti1Image(mask_out, affine_out)
nii_mask_canon = nib.as_closest_canonical(nii_mask)

nib.save(nii_ct_canon, "data/work/brain_ct.nii.gz")
nib.save(nii_mask_canon, "data/work/brain_bleed.nii.gz")
print("canonical shape:", nii_ct_canon.shape, "affine:\n", nii_ct_canon.affine)
data = nii_ct_canon.get_fdata()
print("final HU min/max/percentiles:", data.min(), data.max(), np.percentile(data, [0.5, 50, 99.5]))
mdata = nii_mask_canon.get_fdata()
print("final mask voxel count:", int((mdata > 0).sum()))
print("saved data/work/brain_ct.nii.gz and data/work/brain_bleed.nii.gz")
