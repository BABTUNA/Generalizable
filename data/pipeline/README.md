# Data pipeline scripts (lane L1)

> **DEMO ONLY.** These are the actual scripts L1 ran, copied from the gitignored `data/work/` so the pipeline can be reproduced. `data/PIPELINE_LOG.md` has the commands in order and the reasoning behind them.

| Stage | Scripts |
|---|---|
| Find and download the Visible Human series | `idc_query.py`, `idc_query2.py`, `idc_download.py`, `vhp_*.csv` |
| Convert DICOM → NIfTI, fix irregular z-spacing / gantry tilt | `convert_body2.py` (the final version; `convert_body.py` was the first attempt), `convert_brain.py` |
| Inspect Seg-CQ500 | `inspect_segcq500.py`, `notes_brain_plan.md` |
| Build the bundles | `bundle_common.py`, `build_body_bundle.py`, `build_brain_bundle.py` |
| Logs | `*.log` (TotalSegmentator runs, build output) |

Inputs and intermediates are on the `data/assets` branch; restore them with `unpack.sh`. The label cleanup and app bundles come from `scripts/viz/clean_labels.py` and `scripts/make_demo_bundles.py`.
