# Brain pipeline plan (drafted while Seg-CQ500 downloads)

1. Unzip Seg-CQ500.zip to data/work/seg_cq500_extracted/. Inspect: per-case mask files, whether CT
   images are bundled, mask file format (nifti vs dicom-seg vs numpy), and any reads/metadata csv.
2. Pick a case: thin-slice (~0.625mm) if available, decent-sized bleed. If Seg-CQ500 already has the
   matching CT series bundled, use it directly (skip qure.ai entirely — good, since
   headctstudy.qure.ai does not resolve in DNS from this sandbox; other hosts resolve fine, so this
   looks like the source itself being unreachable, which is exactly the kind of source-level failure
   the brief says to stop on and fall back from, not work around).
3. If Seg-CQ500 has NO CT and only masks: this lane hits a real blocker (qure.ai unreachable, full
   CQ500 torrent set explicitly out of scope per the brief's "do not download the full CQ500 set").
   In that case: report the blocker plainly, and as the pragmatic fallback within data already on
   hand, note that no substitute head+bleed CT is available through any brief-approved source from
   this sandbox — do NOT fabricate a hemorrhage finding on unrelated data to paper over it.
4. Convert to NIfTI RAS canonical (same approach as body: pydicom read + sort by true
   ImagePositionPatient z, correct rescale slope/intercept, nibabel.as_closest_canonical).
   Resample the mask onto the same grid with nearest-neighbor if it isn't already.
5. Run TotalSegmentator `-ta total --fast --device mps` (skull, brain) and `-ta body --fast --device
   mps` (skin/scalp) on brain_ct.nii.gz, same pattern as body.
6. Run data/work/build_brain_bundle.py (already drafted) → data/out/brain/*.
7. python data/verify.py data/out/brain, eyeball previews, fix anything clearly wrong.
