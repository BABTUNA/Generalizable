# Generalizable

**Data:** see [`DATA.md`](DATA.md) for every dataset and link.

> **DEMO ONLY: public open-source research data, not a diagnosis.** This is a 3-hour hackathon demo. Nothing in it is medical advice.

Generalizable is one 3D viewer for any sliced volume. You pick a case, peel away its colored layers, and move a cut plane through it. The live cross-section follows the cut. On a CT scan you can switch between **Layers**, which shows what patients see, and **CT scan**, which shows what doctors see, while the cut stays where it is. On an iPhone Duo, the cut angle is meant to change by folding the device. The same viewer and controls work on a CQ500 head CT with a real bleed, on a whole-body CT, on the Sun and on a circuit board.

## Run it

**In Bitrig (the real demo host).** Bitrig builds from Git. Inside the Bitrig project, fetch the demo branch by URL and merge it, as described in [`docs/ORCHESTRATION.md`](docs/ORCHESTRATION.md):

```sh
git fetch https://github.com/machmoon/Generalizable.git demo/addenda-and-pipeline
git merge FETCH_HEAD
```

Then build and run it on Bitrig's simulator. All four cases are committed under `App/Cases/`, so the app runs offline.

**Locally (a build check).** You need Xcode and `xcodegen`.

```sh
scripts/build_sim.sh                         # build, install, launch on "iPhone 17 Pro"
SIM_DEVICE="iPhone 17 Pro Max" scripts/build_sim.sh shot.png -case head -mode ct
scripts/demo_tour.sh out/tour                # scripted screenshot set (iPhone 17 Pro Max)
```

The launch arguments are `-case head|body|sun|circuit`, `-tilt <deg>`, `-hide <layer ids>`, `-mode layers|ct` and `-select <finding id>`. See `App/UI/LaunchArguments.swift`.

The presenter script is [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md).

## Repo map

| Path | What |
|---|---|
| `App/Core/` | Non-visual Swift: the `CaseBundle` loader and the cut-plane and hinge math |
| `App/UI/` | SwiftUI: case picker, viewer, layer, finding and cut controls, demo banner, credits (built in Bitrig) |
| `App/Render/` | Metal slice shader, `SliceView` and `OverviewView` (built in Bitrig; the current stubs are in `App/UI/Stubs/`) |
| `App/Duo/` | Hinge driver and Duo pose layout (built in Bitrig) |
| `App/Cases/` | The four bundled cases: `head`, `body`, `sun` and `circuit`. Each has `meta.json`, `layers.json`, `findings.json`, `ct.raw` and `labels.raw` |
| `data/` | The pipeline log, attribution, previews, `verify.py` and the synthetic case generators |
| `scripts/` | `build_sim.sh`, `demo_tour.sh`, `make_demo_bundles.py` and the viz references |
| `docs/` | `PRD.md` (with its Addenda), `ORCHESTRATION.md`, the contracts and the Bitrig prompts |
| `coordination/` | Agent registrations, the task board and the handoffs |

**Source data** is on the orphan branch **`data/assets`**, which shares no history with the app branches, so a normal clone never downloads it. Each asset is a tar split into parts under 95 MB. To restore one:

```sh
git fetch origin data/assets && git worktree add ../gz-assets origin/data/assets
cd ../gz-assets && ./unpack.sh <name> <dest>     # verifies the SHA-256
```

## Data credits

See [`data/ATTRIBUTION.md`](data/ATTRIBUTION.md) for the full citations.

- **Body CT:** the Visible Human Project (NLM), accessed through NCI Imaging Data Commons. Covered by the NLM Terms and Conditions (2019).
- **Head CT:** CQ500 case CQ500-CT-243 (Chilamkurthy et al., *The Lancet*, 2018), CC BY-NC-SA 4.0.
- **Bleed mask:** Seg-CQ500 (Spahr et al., *Frontiers in Neuroimaging*, 2023), Zenodo 8063221.
- **Segmentation:** TotalSegmentator (Wasserthal et al., 2023), Apache-2.0.
- **The Sun and Circuit board:** synthetic, generated for this demo, CC0.

## For agents

Read [`AGENTS.md`](AGENTS.md) first. You must register before you edit anything.
