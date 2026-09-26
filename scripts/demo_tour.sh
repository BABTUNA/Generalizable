#!/bin/zsh
# DEMO ONLY. Captures the demo screenshot set via scripts/build_sim.sh on the iPhone 17 Pro Max
# simulator (the iPhone 17 Pro is reserved for another worker).
# Usage: scripts/demo_tour.sh <out-dir>
# Layer ids come from App/Cases/<case>/layers.json (head: 1 Skin, 2 Skull; body: 1 Skin, 2 Fat).
set -euo pipefail
[[ -n "${1:-}" ]] || { echo "usage: $0 <out-dir>"; exit 2; }
mkdir -p "$1"
OUT="${1:A}"
BUILD="${0:A:h}/build_sim.sh"
export SIM_DEVICE="iPhone 17 Pro Max"

shot() { local name=$1; shift; "$BUILD" "$OUT/$name.png" "$@" | grep -E "SCREENSHOT|FAILED|error:" || true; }

shot head_layers_t0        -case head -mode layers -tilt 0  -select 1
shot head_layers_t60       -case head -mode layers -tilt 60 -select 1
shot head_ct_t0            -case head -mode ct     -tilt 0  -select 1
shot head_ct_t60           -case head -mode ct     -tilt 60 -select 1
shot head_skin_bone_hidden -case head -mode layers -hide 1,2 -select 1
shot body_all              -case body -mode layers
shot body_skin_fat_hidden  -case body -mode layers -hide 1,2
shot sun                   -case sun  -select core
shot circuit               -case circuit -select chip

ls "$OUT"/*.png | wc -l | xargs echo "screenshots in $OUT:"
