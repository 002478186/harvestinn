#!/usr/bin/env python3
"""HarvestInn economy checks + 7-day pacing simulation, driven by data/*.json.

  python3 tools/simulate_economy.py           # report
  python3 tools/simulate_economy.py --check   # exit 1 if data is broken or pacing drifts (CI)
  python3 tools/simulate_economy.py --tables  # print the markdown tables used in docs/ECONOMY.md

The simulated player opens the app 4 times a day (08:00, 12:30, 18:00, 21:30) for
10 minutes and plays greedily: harvest, collect, serve guests, cook what guests
want, run workshops, fill deliveries, sell surplus, plant crops that will be ready
by the next session, and buy buildings/land/storage when comfortably affordable.
It re-implements the rules in scripts/core/game_model.gd in simplified form.
shortcut: no animals, rooms or trading in the sim; add them if mid-game pacing needs tuning.
"""
import json
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def D(n):
    return {k: v for k, v in json.loads((ROOT / "data" / n).read_text()).items() if k != "_doc"}


ITEMS, CROPS, RECIPES, BUILDINGS, ECO = D("items.json"), D("crops.json"), D("recipes.json"), D("buildings.json"), D("economy.json")
PRICE = {k: v["price"] for k, v in ITEMS.items()}
SESSIONS = [8 * 3600, 12.5 * 3600, 18 * 3600, 21.5 * 3600]
SESSION_LEN, STEP = 600, 30
# Pacing targets (level reached by end of day) — tuned so the first unlocks land on day 1,
# the online market on day 1-2, and livestock (L10) around day 4-6.
TARGETS = {1: (5, 9), 3: (8, 13), 7: (11, 18)}


def xp_to_next(level):
    c = ECO["xp_curve"]
    return round(c["base"] * level ** c["exponent"])


def validate():
    errs = []
    for cid in CROPS:
        if cid not in ITEMS:
            errs.append(f"crop {cid} missing from items.json")
    for rid, r in RECIPES.items():
        for i in list(r["inputs"]) + list(r["outputs"]):
            if i not in ITEMS:
                errs.append(f"recipe {rid}: unknown item {i}")
        if r["building"] not in BUILDINGS:
            errs.append(f"recipe {rid}: unknown building {r['building']}")
        cost = sum(PRICE[i] * q for i, q in r["inputs"].items())
        value = sum(PRICE[o] * q for o, q in r["outputs"].items())
        if rid != "animal_feed" and value < cost * 1.15:
            errs.append(f"recipe {rid}: output {value} is not worth 1.15x inputs {cost}")
    for cid, c in CROPS.items():
        if PRICE[cid] * c["yield"] <= c["seed_cost"]:
            errs.append(f"crop {cid} loses money")
    return errs


class Sim:
    def __init__(self, seed=1):
        st = ECO["start"]
        self.rng = random.Random(seed)
        self.coins, self.gems, self.xp, self.level, self.rep = st["coins"], st["gems"], 0, 1, 0
        self.inv = dict(st["items"])
        self.parcels = 0
        self.plots = []                                          # (crop, ready_at); fields are bought
        self.per = ECO["parcels"]["cols"] * ECO["parcels"]["rows"]
        self.storage = {"silo": 0, "barn": 0}
        self.buildings = {"kitchen": {"level": 0, "q": []}}
        self.guests, self.next_guest = [], 0.0
        self.deliveries = []
        self.log = []
        self.served = 0

    # --- helpers
    def unlocked(self, lvl):
        return self.level >= lvl

    def kind(self, item):
        return "silo" if ITEMS[item]["category"] == "crop" else "barn"

    def cap(self, k):
        return ECO["storage"][k][self.storage[k]]["capacity"]

    def used(self, k):
        return sum(q for i, q in self.inv.items() if self.kind(i) == k)

    def room(self, items):
        need = {"silo": 0, "barn": 0}
        for i, q in items.items():
            need[self.kind(i)] += q
        return all(self.used(k) + need[k] <= self.cap(k) for k in need if need[k] > 0)

    def has(self, items):
        return all(self.inv.get(i, 0) >= q for i, q in items.items())

    def take(self, items):
        for i, q in items.items():
            self.inv[i] -= q

    def give(self, items):
        for i, q in items.items():
            self.inv[i] = self.inv.get(i, 0) + q

    def add_xp(self, n, t):
        self.xp += n
        while self.level < ECO["max_level"] and self.xp >= xp_to_next(self.level):
            self.xp -= xp_to_next(self.level)
            self.level += 1
            self.gems += 1 + (4 if self.level % 5 == 0 else 0)
            self.log.append((t, f"level {self.level}"))

    def tier(self):
        best = ECO["inn"]["reputation_tiers"][0]
        for i, tr in enumerate(ECO["inn"]["reputation_tiers"]):
            if self.rep >= tr["reputation"]:
                best = dict(tr, index=i)
        best.setdefault("index", 0)
        return best

    def producible(self):
        out = {c for c, v in CROPS.items() if self.unlocked(v["unlock_level"])}
        for r, v in RECIPES.items():
            if self.unlocked(v["unlock_level"]) and v["building"] in self.buildings:
                out |= set(v["outputs"])
        return out

    def meals(self):
        can = self.producible()
        return [r for r, v in RECIPES.items() if v["building"] == "kitchen" and self.unlocked(v["unlock_level"]) and set(v["inputs"]) <= can]

    def order_value(self, order):
        inn = ECO["inn"]
        base = sum(PRICE[m] * q for m, q in order.items())
        return round(base * inn["meal_markup"] * (1 + inn["tip_per_reputation_tier"] * self.tier()["index"]))

    # --- systems
    def tick_inn(self, t):
        iv = ECO["inn"]["guest_interval_seconds"]
        while self.next_guest <= t:
            if len(self.guests) >= self.tier()["tables"]:
                self.next_guest = t + iv
                break
            if self.served == 0 and not self.guests:
                order = {"carrot_stew": 1}
            else:
                order = {}
                for _ in range(self.rng.randint(1, self.tier()["max_order_items"])):
                    m = self.rng.choice(self.meals())
                    order[m] = order.get(m, 0) + (self.rng.randint(1, 2) if self.tier()["index"] >= 2 else 1)
            self.guests.append(dict(order, _at=self.next_guest))
            self.next_guest += iv

    def slots(self, b):
        return BUILDINGS[b]["levels"][self.buildings[b]["level"]]["slots"]

    def queue(self, b, rid, t):
        r = RECIPES[rid]
        q = self.buildings[b]["q"]
        if len(q) >= self.slots(b) or not self.has(r["inputs"]) or not self.unlocked(r["unlock_level"]):
            return False
        self.take(r["inputs"])
        start = max(t, q[-1][1]) if q else t
        q.append((rid, start + r["seconds"]))
        return True

    def collect(self, t):
        for b, st in self.buildings.items():
            while st["q"] and st["q"][0][1] <= t and self.room(RECIPES[st["q"][0][0]]["outputs"]):
                rid, _ = st["q"].pop(0)
                self.give(RECIPES[rid]["outputs"])
                self.add_xp(RECIPES[rid]["xp"], t)

    def deliveries_refresh(self, t):
        if not self.unlocked(ECO["features"]["delivery_board"]):
            return
        cfg = ECO["delivery"]
        pool = [c for c, v in CROPS.items() if self.unlocked(v["unlock_level"])]
        for rid, r in RECIPES.items():
            if self.unlocked(r["unlock_level"]) and r["building"] in self.buildings:
                pool += list(r["outputs"])
        while len(self.deliveries) < cfg["slots"]:
            self.deliveries.append({"items": {}, "ready": t})
        for i, d in enumerate(self.deliveries):
            if not d["items"] and d["ready"] <= t:
                items = {}
                for _ in range(min(self.rng.randint(1, cfg["max_kinds"]), len(pool))):
                    it = self.rng.choice(pool)
                    items[it] = items.get(it, 0) + self.rng.randint(cfg["min_qty"], cfg["max_qty"])
                v = sum(PRICE[i2] * q for i2, q in items.items())
                self.deliveries[i] = {"items": items, "coins": round(v * cfg["reward_mult"]), "xp": max(1, round(v * cfg["xp_mult"])), "ready": t}

    # --- the player's turn
    def act(self, t, until_next):
        for i, p in enumerate(self.plots):                      # harvest
            if p and p[1] <= t and self.room({p[0]: CROPS[p[0]]["yield"]}):
                self.give({p[0]: CROPS[p[0]]["yield"]})
                self.add_xp(CROPS[p[0]]["xp"], t)
                self.plots[i] = None
        self.collect(t)
        self.tick_inn(t)
        self.guests = [g for g in self.guests if t - g["_at"] < 4 * 3600]   # let go of stale orders
        orders = [{k: v for k, v in g.items() if k != "_at"} for g in self.guests]
        for g, full in list(zip(orders, list(self.guests))):        # serve
            if self.has(g):
                self.take(g)
                self.coins += self.order_value(g)
                self.add_xp(sum(RECIPES[m]["xp"] * q for m, q in g.items()), t)
                self.rep += sum(g.values())
                self.served += 1
                self.guests.remove(full)
        for g in [{k: v for k, v in g.items() if k != "_at"} for g in self.guests]:   # cook for waiting guests
            for m, q in g.items():
                have = self.inv.get(m, 0) + sum(1 for j in self.buildings["kitchen"]["q"] if j[0] == m)
                for _ in range(q - have):
                    self.queue("kitchen", m, t)
        for m in self.meals():                                   # cook ahead: keep 2 of each meal
            while self.inv.get(m, 0) + sum(1 for j in self.buildings["kitchen"]["q"] if j[0] == m) < 2 and self.queue("kitchen", m, t):
                pass
        for b in [b for b in self.buildings if b != "kitchen"]:  # workshops: best value first
            for rid in sorted((r for r, v in RECIPES.items() if v["building"] == b), key=lambda r: -PRICE[list(RECIPES[r]["outputs"])[0]]):
                while self.queue(b, rid, t):
                    pass
        self.deliveries_refresh(t)
        for d in self.deliveries:                                # deliveries
            if d["items"] and self.has(d["items"]):
                self.take(d["items"])
                self.coins += d["coins"]
                self.add_xp(d["xp"], t)
                d["items"], d["ready"] = {}, t + ECO["delivery"]["refresh_seconds"]
        for b, v in BUILDINGS.items():                           # build when affordable with margin
            if v["kind"] == "workshop" and b not in self.buildings and not v.get("internal") and self.unlocked(v["unlock_level"]) and self.coins >= v["levels"][0]["cost"] * 1.3:
                self.coins -= v["levels"][0]["cost"]
                self.buildings[b] = {"level": 0, "q": []}
                self.log.append((t, f"built {b}"))
        ex = ECO["parcels"]["list"]
        if self.parcels < len(ex) and self.unlocked(ex[self.parcels]["unlock_level"]) and (self.parcels == 0 or self.coins >= ex[self.parcels]["cost"] * 1.5) and self.coins >= ex[self.parcels]["cost"]:
            self.coins -= ex[self.parcels]["cost"]
            self.plots += [None] * self.per
            self.parcels += 1
            self.log.append((t, f"field {self.parcels}"))
        for k in ("silo", "barn"):
            lv = ECO["storage"][k]
            if self.storage[k] + 1 < len(lv) and self.used(k) > self.cap(k) * 0.8 and self.coins >= lv[self.storage[k] + 1]["cost"] * 1.5:
                self.coins -= lv[self.storage[k] + 1]["cost"]
                self.storage[k] += 1
        for i in list(self.inv):                                 # sell surplus raw crops, keep 8
            if ITEMS[i]["category"] == "crop" and self.inv[i] > 8:
                n = self.inv[i] - 8
                self.inv[i] = 8
                self.coins += PRICE[i] * n
        options = [c for c, v in CROPS.items() if self.unlocked(v["unlock_level"])]
        for i, p in enumerate(self.plots):                       # plant
            if p is None:
                fit = [c for c in options if CROPS[c]["grow_seconds"] <= until_next and CROPS[c]["seed_cost"] <= self.coins]
                if not fit:
                    continue
                need = {m for g in self.guests for m in g if m != "_at"}
                c = max(fit, key=lambda c: (any(c in RECIPES[m]["inputs"] for m in need), -self.inv.get(c, 0) - sum(1 for p in self.plots if p and p[0] == c), self.rng.random()))
                self.coins -= CROPS[c]["seed_cost"]
                self.plots[i] = (c, t + CROPS[c]["grow_seconds"])

    def run(self, days=7):
        report = []
        for day in range(days):
            for k, s0 in enumerate(SESSIONS):
                start = day * 86400 + s0
                nxt = (SESSIONS + [86400 + SESSIONS[0]])[k + 1] - s0 - SESSION_LEN
                for t in range(int(start), int(start + SESSION_LEN), STEP):
                    last = t + STEP >= start + SESSION_LEN
                    self.act(t, nxt + SESSION_LEN if last else start + SESSION_LEN - t - 2 * STEP)
            report.append({"day": day + 1, "level": self.level, "coins": self.coins, "gems": self.gems, "rep": self.rep,
                           "buildings": len(self.buildings) - 1, "plots": len(self.plots)})
        return report


def tables():
    print("| Crop | Seed | Grow | Yield | Sell each | Profit/harvest | XP | Unlock |\n|---|---|---|---|---|---|---|---|")
    for c, v in CROPS.items():
        print(f"| {ITEMS[c]['name']} | {v['seed_cost']} | {v['grow_seconds'] // 60} min | {v['yield']} | {PRICE[c]} | {PRICE[c] * v['yield'] - v['seed_cost']} | {v['xp']} | {v['unlock_level']} |")
    print("\n| Recipe | Building | Inputs | Output | Input value | Output value | Ratio | Time | XP | Unlock |\n|---|---|---|---|---|---|---|---|---|---|")
    for r, v in sorted(RECIPES.items(), key=lambda kv: (kv[1]["building"], kv[1]["unlock_level"])):
        cost = sum(PRICE[i] * q for i, q in v["inputs"].items())
        val = sum(PRICE[o] * q for o, q in v["outputs"].items())
        ins = ", ".join(f"{q} {ITEMS[i]['name']}" for i, q in v["inputs"].items())
        outs = ", ".join(f"{q} {ITEMS[o]['name']}" for o, q in v["outputs"].items())
        print(f"| {r} | {v['building']} | {ins} | {outs} | {cost} | {val} | {val / cost:.2f} | {v['seconds'] // 60 or v['seconds']}{' min' if v['seconds'] >= 60 else ' s'} | {v['xp']} | {v['unlock_level']} |")
    print("\n| Level | XP to next |  | Level | XP to next |\n|---|---|---|---|---|")
    for L in range(1, 26):
        print(f"| {L} | {xp_to_next(L)} | | {L + 25} | {xp_to_next(L + 25)} |")


if __name__ == "__main__":
    if "--tables" in sys.argv:
        tables()
        sys.exit(0)
    errs = validate()
    for e in errs:
        print("ERROR", e)
    rep = Sim().run()
    print("day | level | coins | gems | rep | workshops | plots")
    for r in rep:
        print(f"{r['day']:>3} | {r['level']:>5} | {r['coins']:>5} | {r['gems']:>4} | {r['rep']:>3} | {r['buildings']:>9} | {r['plots']:>5}")
    for d, (lo, hi) in TARGETS.items():
        lvl = rep[d - 1]["level"]
        if not lo <= lvl <= hi:
            errs.append(f"pacing: day {d} level {lvl} outside target {lo}-{hi}")
            print("ERROR", errs[-1])
    print(f"{len(errs)} problems")
    sys.exit(1 if errs and "--check" in sys.argv else 0)
