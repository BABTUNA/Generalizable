import nibabel as nib
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

img = nib.load("data/work/body_ct.nii.gz")
data = img.get_fdata()
print("shape", data.shape, "affine\n", img.affine)
x, y, z = data.shape
fig, axs = plt.subplots(1, 3, figsize=(12, 4))
axs[0].imshow(np.rot90(data[x // 2, :, :]), cmap="gray", vmin=-200, vmax=400)
axs[0].set_title("sagittal mid")
axs[1].imshow(np.rot90(data[:, y // 2, :]), cmap="gray", vmin=-200, vmax=400)
axs[1].set_title("coronal mid")
axs[2].imshow(data[:, :, z // 2], cmap="gray", vmin=-200, vmax=400)
axs[2].set_title("axial mid")
plt.tight_layout()
plt.savefig("data/work/body_quicklook.png", dpi=100)
print("saved quicklook")
