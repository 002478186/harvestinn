#!/usr/bin/env bash
# Visual review: renders the demo farm from several viewpoints into $1 (default scratch dir).
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/harvest_shots}"; mkdir -p "$OUT"
shot() { timeout 90 godot --path . -- --shot="$OUT/$1.png" --demo --clean --at="$2" >/dev/null 2>&1; }
shot spawn   "0,2,0"          # village square, looking at the inn
shot fields  "-2,4,180"       # standing at the fields, looking south
shot market  "-12,0,-60"      # market stall + merchant
shot animals "23,15,180,12"   # animal paddock from the lane
shot crops   "-5,9,200,7"     # close-up on growing crops
echo "$OUT"
