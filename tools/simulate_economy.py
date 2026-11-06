#!/usr/bin/env python3
"""Economy checks for HarvestInn (data validation; 7-day pacing sim added in M6).

  python3 tools/simulate_economy.py           # print report
  python3 tools/simulate_economy.py --check   # exit 1 on a balance violation (CI)
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
D = lambda n: {k: v for k, v in json.loads((ROOT / "data" / n).read_text()).items() if k != "_doc"}


def validate() -> list:
    items, crops, recipes = D("items.json"), D("crops.json"), D("recipes.json")
    errs = []
    for cid, c in crops.items():
        if cid not in items:
            errs.append(f"crop {cid} missing from items.json")
    for rid, r in recipes.items():
        for i in list(r["inputs"]) + list(r["outputs"]):
            if i not in items:
                errs.append(f"recipe {rid}: unknown item {i}")
    return errs


if __name__ == "__main__":
    errs = validate()
    for e in errs:
        print("ERROR", e)
    print(f"{len(errs)} problems")
    sys.exit(1 if errs and "--check" in sys.argv else 0)
