#!/usr/bin/env bash
# Visual review: renders the store-listing views of the demo farm into $1 (default scratch dir).
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/harvest_shots}"; mkdir -p "$OUT"
shot() { timeout 90 godot --path . -- --shot="$OUT/$1.png" --demo --clean "${@:2}" >/dev/null 2>&1; }
shot 1_farm_day   --hour=11 --at=0,2,0             &   # village square, looking at the inn
shot 2_farm_night --hour=22 --at=0,2,0             &
shot 3_fields     --hour=16 --at=-2,4,180          &   # standing at the fields, looking south
shot 4_market     --hour=11 --at=-12,0,-60         &   # market stall + merchant
wait
shot 5_pens       --hour=11 --at=13,28,-80,9       &   # hens, cows and the barns
shot 6_inn        --hour=19 --inside=inn           &
shot 7_workshop   --hour=11 --inside=mill          &
shot 8_storehouse --hour=11 --inside=storehouse    &
wait
shot 9_creator    --hour=11 --creator
echo "$OUT"
