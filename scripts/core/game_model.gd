## The whole game state as plain JSON-safe data (`s`) plus the rules that change it.
## No nodes, no UI: every method takes `now` (unix seconds) so tests control time.
## Methods that can fail return "" on success or an error code string.
class_name GameModel
extends RefCounted

## UI listens to this (via EventBus). name: "coins", "xp", "level_up", "inventory", "plot", ...
signal event(name: String, data: Dictionary)

var s: Dictionary

func _init(state: Dictionary = {}) -> void:
	s = state

static func new_game(now: float) -> GameModel:
	var eco := GameData.economy()
	var m := GameModel.new({
		"version": SaveCodec.VERSION,
		"created": now, "last_seen": now,
		"coins": int(eco["start"]["coins"]), "gems": int(eco["start"]["gems"]),
		"xp": 0, "level": 1, "reputation": 0,
		"inv": eco["start"]["items"].duplicate(),
		"parcels": 0, "plots": [],
		"storage": {"silo": 0, "barn": 0},
		"stats": {},
	})
	SaveCodec.fill_defaults(m.s)
	return m

static func _empty_plot() -> Dictionary:
	return {"crop": "", "ready_at": 0.0, "planted_at": 0.0}

# ------------------------------------------------------------ currencies, xp, levels

## XP needed to go from `level` to level + 1 (see docs/ECONOMY.md).
static func xp_to_next(level: int) -> int:
	var c: Dictionary = GameData.economy()["xp_curve"]
	return int(round(float(c["base"]) * pow(level, float(c["exponent"]))))

func add_coins(n: int) -> void:
	s["coins"] += n
	if n > 0:
		stat("coins_earned", n)
	event.emit("coins", {"value": s["coins"], "delta": n})

func spend(n: int) -> bool:
	if s["coins"] < n:
		return false
	add_coins(-n)
	return true

func add_gems(n: int) -> void:
	s["gems"] += n
	event.emit("gems", {"value": s["gems"], "delta": n})

func add_xp(n: int) -> void:
	var max_level := int(GameData.economy()["max_level"])
	s["xp"] += n
	while s["level"] < max_level and s["xp"] >= xp_to_next(s["level"]):
		s["xp"] -= xp_to_next(s["level"])
		s["level"] += 1
		var lg: Dictionary = GameData.economy()["level_up_gems"]
		var gems := int(lg["every_level"]) + (int(lg["every_5th_bonus"]) if s["level"] % 5 == 0 else 0)
		add_gems(gems)
		event.emit("level_up", {"level": s["level"], "gems": gems, "unlocks": GameData.unlocks_at(s["level"])})
	event.emit("xp", {"xp": s["xp"], "level": s["level"], "delta": n})

func stat(key: String, n: int = 1) -> void:
	s["stats"][key] = int(s["stats"].get(key, 0)) + n
	_tutorial_check()
	for id in GameData.achievements():
		var a: Dictionary = GameData.achievements()[id]
		if a["stat"] == key and int(s["stats"][key]) >= int(a["goal"]) and int(s["stats"][key]) - n < int(a["goal"]):
			event.emit("achievement", {"id": id})

# ------------------------------------------------------------ inventory + storage

func count(item: String) -> int:
	return int(s["inv"].get(item, 0))

func storage_cap(kind: String) -> int:
	return int(GameData.economy()["storage"][kind][int(s["storage"][kind])]["capacity"])

func storage_used(kind: String) -> int:
	var n := 0
	for item in s["inv"]:
		if GameData.storage_kind(item) == kind:
			n += int(s["inv"][item])
	return n

## Room for these items (item -> qty), counting what `freed` gives back first.
func has_room(items: Dictionary, freed: Dictionary = {}) -> bool:
	var need := {"silo": 0, "barn": 0}
	for item in items:
		need[GameData.storage_kind(item)] += int(items[item])
	for item in freed:
		need[GameData.storage_kind(item)] -= int(freed[item])
	for kind in need:
		if need[kind] > 0 and storage_used(kind) + need[kind] > storage_cap(kind):
			return false
	return true

## Adds items; with `force` storage limits are ignored (used for rewards, trade collection).
func add_items(items: Dictionary, force: bool = false) -> bool:
	if not force and not has_room(items):
		return false
	for item in items:
		s["inv"][item] = count(item) + int(items[item])
	event.emit("inventory", {"items": items})
	return true

func has_items(items: Dictionary) -> bool:
	for item in items:
		if count(item) < int(items[item]):
			return false
	return true

func remove_items(items: Dictionary) -> bool:
	if not has_items(items):
		return false
	for item in items:
		s["inv"][item] = count(item) - int(items[item])
		if s["inv"][item] == 0:
			s["inv"].erase(item)
	event.emit("inventory", {"items": items})
	return true

# ------------------------------------------------------------ crops

func is_unlocked(level_req) -> bool:
	return s["level"] >= int(level_req)

func plant(i: int, crop: String, now: float) -> String:
	var c: Dictionary = GameData.crops().get(crop, {})
	if c.is_empty(): return "unknown_crop"
	if i < 0 or i >= s["plots"].size(): return "bad_plot"
	if s["plots"][i]["crop"] != "": return "plot_busy"
	if not is_unlocked(c["unlock_level"]): return "locked"
	if not spend(int(c["seed_cost"])): return "no_coins"
	s["plots"][i] = {"crop": crop, "planted_at": now, "ready_at": now + float(c["grow_seconds"])}
	stat("planted")
	event.emit("plot", {"index": i})
	return ""

func plot_remaining(i: int, now: float) -> float:
	var p: Dictionary = s["plots"][i]
	return 0.0 if p["crop"] == "" else maxf(0.0, float(p["ready_at"]) - now)

## 0..1 growth, for the sprite stage.
func plot_progress(i: int, now: float) -> float:
	var p: Dictionary = s["plots"][i]
	if p["crop"] == "": return 0.0
	var total := float(p["ready_at"]) - float(p["planted_at"])
	return 1.0 if total <= 0.0 else clampf((now - float(p["planted_at"])) / total, 0.0, 1.0)

func harvest(i: int, now: float) -> String:
	var p: Dictionary = s["plots"][i]
	if p["crop"] == "": return "empty"
	if plot_remaining(i, now) > 0.0: return "not_ready"
	var c: Dictionary = GameData.crops()[p["crop"]]
	if not add_items({p["crop"]: int(c["yield"])}): return "silo_full"
	var crop: String = p["crop"]
	s["plots"][i] = _empty_plot()
	stat("harvests")
	add_xp(int(c["xp"]))
	event.emit("harvest", {"index": i, "crop": crop, "qty": int(c["yield"])})
	return ""

# ------------------------------------------------------------ gems speed-up

static func speedup_cost(remaining: float) -> int:
	var sp: Dictionary = GameData.economy()["speedup"]
	return maxi(int(sp["min_gems"]), ceili(remaining / float(sp["seconds_per_gem"])))

func speed_up_plot(i: int, now: float) -> String:
	var rem := plot_remaining(i, now)
	if rem <= 0.0: return "not_needed"
	var cost := speedup_cost(rem)
	if s["gems"] < cost: return "no_gems"
	add_gems(-cost)
	s["plots"][i]["ready_at"] = now
	event.emit("plot", {"index": i})
	return ""

# ------------------------------------------------------------ farm layout

## Moves a building ("inn", "mill", ...) or decoration ("decor:<i>") to a tile if the area is free.
## `occupied` = [[x, y, w, h], ...] of everything else (computed by the view, which knows the layout).
func move_object(id: String, x: int, y: int, size: int, occupied: Array) -> bool:
	var r := Rect2i(x, y, size, size)
	for o in occupied:
		if r.intersects(Rect2i(int(o[0]), int(o[1]), int(o[2]), int(o[3]))):
			return false
	if id.begins_with("decor:"):
		var d: Dictionary = s["decor"][int(id.split(":")[1])]
		d["x"] = x
		d["y"] = y
	else:
		if not s.has("pos"): s["pos"] = {}
		s["pos"][id] = [x, y]
	event.emit("building", {"id": id})
	return true


# ------------------------------------------------------------ offline progress

## What finished while the app was closed. Timers are absolute timestamps, so the
## work itself already happened; this only counts it for the "Welcome back" card.
func offline_summary(since: float, now: float) -> Dictionary:
	var out := {"away": now - since, "crops": 0, "jobs": 0}
	for p in s["plots"]:
		if p["crop"] != "" and float(p["ready_at"]) > since and float(p["ready_at"]) <= now:
			out["crops"] += 1
	for b in s["buildings"]:
		for j in s["buildings"][b]["queue"]:
			if float(j["end"]) > since and float(j["end"]) <= now:
				out["jobs"] += 1
	out["animals"] = 0
	for h in s["animals"]:
		for a in s["animals"][h]:
			if float(a["cycle_end"]) > since and float(a["cycle_end"]) <= now: out["animals"] += 1
	tick(now)
	out["guests"] = inn()["guests"].filter(func(g): return float(g["arrived"]) > since and float(g["arrived"]) < now).size()
	out["room_coins"] = 0
	for i in inn()["rooms"].size():
		out["room_coins"] += room_income(i, now)
	return out

## Periodic world update (called every second by the Game autoload and on load).
func tick(now: float) -> void:
	tick_inn(now)
	if is_unlocked(GameData.economy()["features"]["delivery_board"]):
		refresh_deliveries(now)

# ------------------------------------------------------------ tutorial

# ------------------------------------------------------------ daily goals

## Today's three goals (after the tutorial): progress counts from the stats at the day's start.
## [{stat, n, text, progress, done, claimed, coins, xp}]
func daily_goals(now: float) -> Array:
	if not tutorial_step().is_empty(): return []
	var cfg: Dictionary = GameData.economy()["daily_goals"]
	var day := local_day(now)
	var g: Dictionary = s.get("goals", {})
	if not g.has("picks") or int(g["day"]) != day:
		var pool: Array = []
		for k in cfg["pool"].size():
			if is_unlocked(int(cfg["pool"][k]["unlock_level"])): pool.append(k)
		var picks: Array = []
		var h := absi(("goals:%d" % day).hash())
		while picks.size() < mini(int(cfg["count"]), pool.size()):
			var k: int = pool[h % pool.size()]
			if not k in picks: picks.append(k)
			h = absi(str(h).hash())
		var t := clampf((int(s["level"]) - 1) / 19.0, 0.0, 1.0)
		var base := {}
		for k in picks: base[cfg["pool"][k]["stat"]] = int(s["stats"].get(cfg["pool"][k]["stat"], 0))
		g = {"day": day, "picks": picks, "base": base, "claimed": picks.map(func(_k): return false), "bonus": false,
			"n": picks.map(func(k): return int(round(lerpf(cfg["pool"][k]["n"][0], cfg["pool"][k]["n"][1], t)))),
			"coins": int(round(lerpf(cfg["reward"]["coins"][0], cfg["reward"]["coins"][1], t))), "xp": int(round(lerpf(cfg["reward"]["xp"][0], cfg["reward"]["xp"][1], t)))}
		s["goals"] = g
	var out := []
	for i in g["picks"].size():
		var p: Dictionary = cfg["pool"][int(g["picks"][i])]
		var n := int(g["n"][i])
		var prog := mini(n, int(s["stats"].get(p["stat"], 0)) - int(g["base"].get(p["stat"], 0)))
		out.append({"stat": p["stat"], "n": n, "text": p["text"] % n, "progress": prog, "done": prog >= n, "claimed": bool(g["claimed"][i]), "coins": int(g["coins"]), "xp": int(g["xp"])})
	return out

func claim_goal(i: int, now: float) -> String:
	var goals := daily_goals(now)
	if i < 0 or i >= goals.size(): return "unknown"
	if not goals[i]["done"]: return "not_ready"
	if goals[i]["claimed"]: return "claimed"
	s["goals"]["claimed"][i] = true
	add_coins(int(goals[i]["coins"]))
	add_xp(int(goals[i]["xp"]))
	if not s["goals"]["bonus"] and s["goals"]["claimed"].all(func(c): return c):
		s["goals"]["bonus"] = true
		add_gems(int(GameData.economy()["daily_goals"]["bonus"]["gems"]))
	event.emit("goal", {"index": i})
	return ""

func tutorial_step() -> Dictionary:
	var steps := GameData.tutorial()
	var i := int(s["tutorial"])
	return steps[i] if i < steps.size() else {}

## Advances when the current step's stat goal is met.
func _tutorial_check() -> void:
	var st := tutorial_step()
	if st.is_empty() or not st["goal"] is Dictionary: return
	if int(s["stats"].get(st["goal"]["stat"], 0)) >= int(st["goal"]["n"]):
		_tutorial_next()

## The "Continue" button on tap-goal steps.
func tutorial_tap() -> void:
	var st := tutorial_step()
	if not st.is_empty() and st["goal"] is String:
		_tutorial_next()

func _tutorial_next() -> void:
	var r: Dictionary = tutorial_step().get("reward", {})
	s["tutorial"] = int(s["tutorial"]) + 1
	if r.has("coins"): add_coins(int(r["coins"]))
	if r.has("gems"): add_gems(int(r["gems"]))
	event.emit("tutorial", {"step": s["tutorial"]})
	_tutorial_check()   # the next goal may already be met

func skip_tutorial() -> void:
	s["tutorial"] = GameData.tutorial().size()
	event.emit("tutorial", {"step": s["tutorial"]})

# ------------------------------------------------------------ cosmetics + avatar

func owns(cosmetic_id: String) -> bool:
	var c: Dictionary = GameData.cosmetics().get(cosmetic_id, {})
	return int(c.get("cost", 1)) == 0 and not c.has("cost_gems") or cosmetic_id in s["owned"]

func set_avatar(key: String, value) -> String:
	if key in ["outfit", "hat"] and not owns(str(value)): return "locked"
	s["avatar"][key] = value
	event.emit("avatar", {})
	return ""

func set_player_name(n: String) -> String:
	n = n.strip_edges().left(16)
	if n.length() < 2: return "name_short"
	if not NameFilter.is_clean(n): return "name_blocked"
	s["name"] = n
	event.emit("name", {"name": n})
	return ""

# ------------------------------------------------------------ buildings + workshops

## The inn kitchen exists from the start; other buildings are bought in the Shop.
func owns_building(id: String) -> bool:
	if id == "kitchen" and not s["buildings"].has("kitchen"):
		s["buildings"]["kitchen"] = {"level": 0, "queue": []}
	return s["buildings"].has(id)

func building_level(id: String) -> int:
	return int(s["buildings"][id]["level"]) if owns_building(id) else -1

func build(id: String) -> String:
	var b: Dictionary = GameData.buildings().get(id, {})
	if b.is_empty() or b.get("internal", false) or id == "inn": return "unknown"
	if owns_building(id): return "owned"
	if not is_unlocked(b["unlock_level"]): return "locked"
	if not spend(int(b["levels"][0]["cost"])): return "no_coins"
	s["buildings"][id] = {"level": 0, "queue": []}
	if b["kind"] == "housing": s["animals"][id] = []
	stat("built")
	event.emit("building", {"id": id})
	return ""

func upgrade_building(id: String) -> String:
	if not owns_building(id): return "not_owned"
	var levels: Array = GameData.buildings()[id]["levels"]
	var next := building_level(id) + 1
	if next >= levels.size(): return "max_level"
	if not spend(int(levels[next]["cost"])): return "no_coins"
	s["buildings"][id]["level"] = next
	event.emit("building", {"id": id})
	return ""

func slots(id: String) -> int:
	return int(GameData.buildings()[id]["levels"][building_level(id)].get("slots", 0))

func queue_recipe(bid: String, rid: String, now: float) -> String:
	var r: Dictionary = GameData.recipes().get(rid, {})
	if r.is_empty() or r["building"] != bid: return "unknown"
	if not owns_building(bid): return "not_owned"
	if not is_unlocked(r["unlock_level"]): return "locked"
	var q: Array = s["buildings"][bid]["queue"]
	if q.size() >= slots(bid): return "queue_full"
	if not remove_items(r["inputs"]): return "missing_items"
	var start := maxf(now, float(q.back()["end"])) if not q.is_empty() else now
	q.append({"recipe": rid, "start": start, "end": start + float(r["seconds"])})
	event.emit("job", {"building": bid})
	return ""

## Collects every finished job at the front of the queue that fits in storage.
func collect_building(bid: String, now: float) -> String:
	if not owns_building(bid): return "not_owned"
	var q: Array = s["buildings"][bid]["queue"]
	var got := 0
	while not q.is_empty() and float(q[0]["end"]) <= now:
		var r: Dictionary = GameData.recipes()[q[0]["recipe"]]
		if not add_items(r["outputs"]):
			return "barn_full" if got == 0 else ""
		q.pop_front()
		got += 1
		stat("cooked" if bid == "kitchen" else "crafted")
		add_xp(int(r["xp"]))
		event.emit("collect", {"building": bid, "items": r["outputs"]})
	return "" if got > 0 else "not_ready"

func building_has_ready(id: String, now: float) -> bool:
	if id == "inn": return owns_building("kitchen") and building_has_ready("kitchen", now)
	if s["animals"].has(id): return animals_ready(id, now) > 0
	if not s["buildings"].has(id): return false
	var q: Array = s["buildings"][id]["queue"]
	return not q.is_empty() and float(q[0]["end"]) <= now

## Pays gems to finish the first unfinished job; later jobs move up by the same amount.
func speed_up_job(bid: String, now: float) -> String:
	var q: Array = s["buildings"][bid]["queue"]
	for j in q:
		var rem := float(j["end"]) - now
		if rem <= 0.0: continue
		var cost := speedup_cost(rem)
		if s["gems"] < cost: return "no_gems"
		add_gems(-cost)
		for k in q:
			if float(k["end"]) > now:
				k["start"] = float(k["start"]) - rem
				k["end"] = float(k["end"]) - rem
		event.emit("job", {"building": bid})
		return ""
	return "not_needed"


# ------------------------------------------------------------ the inn

func inn() -> Dictionary:
	var d: Dictionary = s["inn"]
	if not d.has("guests"):
		d.merge({"guests": [], "next_guest": 0.0, "rooms": []})
	return d

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.state = int(s["rng"])
	return r

func _save_rng(r: RandomNumberGenerator) -> void:
	s["rng"] = r.state

func rep_tier() -> Dictionary:
	var tiers: Array = GameData.economy()["inn"]["reputation_tiers"]
	var best: Dictionary = tiers[0]
	for t in tiers:
		if int(s["reputation"]) >= int(t["reputation"]): best = t
	var out := best.duplicate()
	out["index"] = tiers.find(best)
	return out

func add_reputation(n: int) -> void:
	var before := int(rep_tier()["index"])
	s["reputation"] = int(s["reputation"]) + n
	event.emit("reputation", {"value": s["reputation"]})
	if int(rep_tier()["index"]) > before:
		event.emit("rep_tier", rep_tier())

## Kitchen meals the player can cook now: unlocked, and every ingredient is something
## they can produce (so guests never order a meal that needs a workshop you don't own).
func meals_available() -> Array[String]:
	var can := producible()
	return GameData.recipes_for("kitchen").filter(func(r):
		var rec: Dictionary = GameData.recipes()[r]
		return is_unlocked(rec["unlock_level"]) and rec["inputs"].keys().all(func(i): return i in can))

func tick_inn(now: float) -> void:
	var d := inn()
	var interval := float(GameData.economy()["inn"]["guest_interval_seconds"])
	if float(d["next_guest"]) == 0.0:
		d["next_guest"] = now
	while float(d["next_guest"]) <= now:
		if d["guests"].size() >= int(rep_tier()["tables"]):
			d["next_guest"] = now + interval
			break
		_spawn_guest(float(d["next_guest"]))
		d["next_guest"] = float(d["next_guest"]) + interval

func _spawn_guest(at: float) -> void:
	var d := inn()
	var r := _rng()
	var present: Array = d["guests"].map(func(g): return g["char"])
	var pool: Array = []
	for cid in GameData.characters():
		var c: Dictionary = GameData.characters()[cid]
		if c.get("guest", false) and int(c["min_reputation"]) <= int(s["reputation"]) and not cid in present:
			pool.append(cid)
	if pool.is_empty(): return
	var who: String = pool[r.randi_range(0, pool.size() - 1)]
	var order := {}
	if int(s["stats"].get("served", 0)) == 0 and d["guests"].is_empty():
		order = {"carrot_stew": 1}      # tutorial guest: the meal the player can already cook
	else:
		var meals := meals_available()
		var favs: Array = GameData.characters()[who].get("favourites", [])
		var weighted: Array = []
		for meal in meals:
			for k in (3 if meal in favs else 1): weighted.append(meal)
		var kinds := r.randi_range(1, int(rep_tier()["max_order_items"]))
		for k in kinds:
			var meal: String = weighted[r.randi_range(0, weighted.size() - 1)]
			order[meal] = int(order.get(meal, 0)) + (r.randi_range(1, 2) if int(rep_tier()["index"]) >= 2 else 1)
	_save_rng(r)
	d["guests"].append({"char": who, "order": order, "arrived": at})
	event.emit("guest", {"char": who})

## Coins a guest pays for their order: meal value × markup × (1 + tip from reputation tier).
func order_value(order: Dictionary) -> int:
	var inn_cfg: Dictionary = GameData.economy()["inn"]
	var base := 0
	for meal in order: base += GameData.item_price(meal) * int(order[meal])
	var tip := float(inn_cfg["tip_per_reputation_tier"]) * int(rep_tier()["index"])
	return int(round(base * float(inn_cfg["meal_markup"]) * (1.0 + tip)))

func serve_guest(i: int) -> String:
	var d := inn()
	if i < 0 or i >= d["guests"].size(): return "unknown"
	var g: Dictionary = d["guests"][i]
	if not remove_items(g["order"]): return "missing_items"
	var coins := order_value(g["order"])
	var qty := 0
	var xp := 0
	for meal in g["order"]:
		qty += int(g["order"][meal])
		xp += int(GameData.recipes()[meal]["xp"]) * int(g["order"][meal])
	d["guests"].remove_at(i)
	add_coins(coins)
	add_xp(xp)
	add_reputation(int(GameData.economy()["inn"]["reputation_per_meal"]) * qty)
	stat("served")
	event.emit("served", {"char": g["char"], "coins": coins, "xp": xp})
	return ""

## A guest leaves without eating (no penalty — it's a cozy inn).
func dismiss_guest(i: int, now: float) -> void:
	inn()["guests"].remove_at(i)
	inn()["next_guest"] = minf(float(inn()["next_guest"]), now + 10.0)
	event.emit("guest", {})

# guest rooms ------------------------------------------------

func room_config(i: int) -> Dictionary:
	return GameData.economy()["inn"]["guest_rooms"][i]

func build_room(now: float) -> String:
	var rooms: Array = inn()["rooms"]
	var cfgs: Array = GameData.economy()["inn"]["guest_rooms"]
	if rooms.size() >= cfgs.size(): return "max_level"
	var c: Dictionary = cfgs[rooms.size()]
	if not is_unlocked(c["unlock_level"]): return "locked"
	if not spend(int(c["cost"])): return "no_coins"
	rooms.append({"furnished": false, "collected": now})
	event.emit("room", {})
	return ""

func furnish_room(i: int, now: float) -> String:
	var room: Dictionary = inn()["rooms"][i]
	if room["furnished"]: return "owned"
	if not remove_items(room_config(i)["requires"]): return "missing_items"
	room["furnished"] = true
	room["collected"] = now
	event.emit("room", {})
	return ""

func room_income(i: int, now: float) -> int:
	var room: Dictionary = inn()["rooms"][i]
	if not room["furnished"]: return 0
	var cap := float(GameData.economy()["inn"]["room_storage_hours"])
	var hours := minf((now - float(room["collected"])) / 3600.0, cap)
	return int(floor(float(room_config(i)["coins_per_hour"]) * maxf(hours, 0.0)))

func collect_room(i: int, now: float) -> String:
	var n := room_income(i, now)
	if n <= 0: return "not_ready"
	inn()["rooms"][i]["collected"] = now
	add_coins(n)
	event.emit("collect", {"room": i, "coins": n})
	return ""

# ------------------------------------------------------------ local market

static func day_of(now: float) -> int:
	return int(floor(now / 86400.0))

## Today's demand multiplier for an item: deterministic per (item, day), so every
## player sees the same prices and they change at midnight UTC.
static func demand(item: String, day: int) -> float:
	var m: Dictionary = GameData.economy()["market"]
	var h := ("%s:%d" % [item, day]).hash()
	var t := float(posmod(h, 1000)) / 999.0
	return lerpf(float(m["demand_min"]), float(m["demand_max"]), t)

static func market_price(item: String, now: float) -> int:
	var bonus := 1.0
	for e in active_events(now):
		if item in e["featured"]: bonus = maxf(bonus, float(e["sell_mult"]))
	return maxi(1, int(round(GameData.item_price(item) * demand(item, day_of(now)) * bonus)))

func sold_today(item: String, now: float) -> int:
	var mk: Dictionary = s["market"]
	if int(mk.get("day", -1)) != day_of(now):
		mk["day"] = day_of(now)
		mk["sold"] = {}
	return int(mk["sold"].get(item, 0))

func sell(item: String, qty: int, now: float) -> String:
	if qty <= 0 or count(item) < qty: return "missing_items"
	var cap := int(GameData.economy()["market"]["sell_cap_per_item_per_day"])
	if sold_today(item, now) + qty > cap: return "sell_cap"
	var coins := market_price(item, now) * qty
	remove_items({item: qty})
	s["market"]["sold"][item] = sold_today(item, now) + qty
	add_coins(coins)
	stat("sold", qty)
	event.emit("sold", {"item": item, "qty": qty, "coins": coins})
	return ""

# ------------------------------------------------------------ delivery board

## Items the player can currently make: unlocked crops + outputs of unlocked recipes in owned buildings.
func producible() -> Array[String]:
	var out: Array[String] = []
	for c in GameData.crops():
		if is_unlocked(GameData.crops()[c]["unlock_level"]): out.append(c)
	for rid in GameData.recipes():
		var r: Dictionary = GameData.recipes()[rid]
		if is_unlocked(r["unlock_level"]) and owns_building(r["building"]):
			for o in r["outputs"]:
				if not o in out: out.append(o)
	for a in s["animals"]:
		for pr in GameData.animals()[GameData.buildings()[a]["animal"]]["products"]:
			if not pr["item"] in out and not s["animals"][a].is_empty(): out.append(pr["item"])
	return out

func refresh_deliveries(now: float) -> void:
	var cfg: Dictionary = GameData.economy()["delivery"]
	var d: Array = s["deliveries"]
	while d.size() < int(cfg["slots"]):
		d.append({"items": {}, "ready_at": now})
	var changed := false
	for i in d.size():
		if d[i]["items"].is_empty() and float(d[i]["ready_at"]) <= now:
			d[i] = _new_delivery(now)
			changed = true
	if changed:
		event.emit("delivery", {})

func _new_delivery(now: float) -> Dictionary:
	var cfg: Dictionary = GameData.economy()["delivery"]
	var r := _rng()
	var pool := producible()
	var items := {}
	var kinds := mini(r.randi_range(1, int(cfg["max_kinds"])), pool.size())
	for k in kinds:
		var it: String = pool[r.randi_range(0, pool.size() - 1)]
		items[it] = int(items.get(it, 0)) + r.randi_range(int(cfg["min_qty"]), int(cfg["max_qty"]))
	_save_rng(r)
	var value := 0
	for it in items: value += GameData.item_price(it) * int(items[it])
	return {"items": items, "coins": int(round(value * float(cfg["reward_mult"]))),
		"xp": maxi(1, int(round(value * float(cfg["xp_mult"])))), "ready_at": now}

func fulfill_delivery(i: int, now: float) -> String:
	var d: Dictionary = s["deliveries"][i]
	if d["items"].is_empty(): return "not_ready"
	if not remove_items(d["items"]): return "missing_items"
	add_coins(int(d["coins"]))
	add_xp(int(d["xp"]))
	stat("deliveries")
	s["deliveries"][i] = {"items": {}, "ready_at": now + float(GameData.economy()["delivery"]["refresh_seconds"])}
	event.emit("delivery", {"done": i})
	return ""

func skip_delivery(i: int, now: float) -> void:
	s["deliveries"][i] = {"items": {}, "ready_at": now + float(GameData.economy()["delivery"]["refresh_seconds"])}
	event.emit("delivery", {})

# ------------------------------------------------------------ shop: storage, land, cosmetics

func upgrade_storage(kind: String) -> String:
	var levels: Array = GameData.economy()["storage"][kind]
	var next := int(s["storage"][kind]) + 1
	if next >= levels.size(): return "max_level"
	if not spend(int(levels[next]["cost"])): return "no_coins"
	s["storage"][kind] = next
	event.emit("storage", {"kind": kind})
	return ""

static func plots_per_parcel() -> int:
	var p: Dictionary = GameData.economy()["parcels"]
	return int(p["cols"]) * int(p["rows"])

## The next field for sale, or {} when all are owned.
func next_parcel() -> Dictionary:
	var list: Array = GameData.economy()["parcels"]["list"]
	return list[int(s["parcels"])] if int(s["parcels"]) < list.size() else {}

## Buys the next field: adds its plots (each parcel owns a fixed range of plot indices).
func buy_parcel() -> String:
	var p := next_parcel()
	if p.is_empty(): return "max_level"
	if not is_unlocked(p["unlock_level"]): return "locked"
	if not spend(int(p["cost"])): return "no_coins"
	for i in plots_per_parcel():
		s["plots"].append(_empty_plot())
	s["parcels"] = int(s["parcels"]) + 1
	stat("parcels")
	event.emit("land", {"parcel": int(s["parcels"]) - 1})
	return ""

## Buys an outfit/hat/furniture, or a decoration placed at tile (x, y).
func buy_cosmetic(id: String, x := 0, y := 0) -> String:
	var c: Dictionary = GameData.cosmetics().get(id, {})
	if c.is_empty(): return "unknown"
	if not is_unlocked(c["unlock_level"]): return "locked"
	if c["slot"] != "decor" and owns(id): return "owned"
	if c.has("cost_gems"):
		if int(s["gems"]) < int(c["cost_gems"]): return "no_gems"
		add_gems(-int(c["cost_gems"]))
	elif not spend(int(c["cost"])):
		return "no_coins"
	if c["slot"] == "decor":
		s["decor"].append({"id": id, "x": x, "y": y})
		event.emit("decor", {})
	else:
		s["owned"].append(id)
		if c["slot"] == "furniture":
			add_reputation(int(c.get("reputation", 0)))
	stat("purchases")
	event.emit("purchase", {"id": id})
	return ""

# ------------------------------------------------------------ trading outbox (device side)
# Items leave the farm BEFORE the server call and wait in s["outbox"] with a request id.
# Net retries the same id until the server answers; refused deposits are refunded.

func queue_deposit(items: Dictionary, coins: int) -> String:
	var whole := {}
	for k in items: whole[k] = int(items[k])     # JSON may hand us 5.0
	items = whole
	if not has_items(items): return "missing_items"
	if int(s["coins"]) < coins: return "no_coins"
	remove_items(items)
	if coins > 0: add_coins(-coins)
	var op := {"id": TradeRules.uuid(), "kind": "deposit", "items": items, "coins": coins}
	s["outbox"].append(op)
	event.emit("outbox", op)
	return ""

func queue_collect() -> void:
	if s["outbox"].any(func(o): return o["kind"] == "collect"): return
	var op := {"id": TradeRules.uuid(), "kind": "collect"}
	s["outbox"].append(op)
	event.emit("outbox", op)          # saved before the request goes out

## Applies the server's answer for an outbox op. `result` is the RPC data, or {"error": code}.
func finish_op(op_id: String, result: Dictionary) -> void:
	var i := -1
	for k in s["outbox"].size():
		if s["outbox"][k]["id"] == op_id: i = k
	if i < 0: return
	var op: Dictionary = s["outbox"][i]
	s["outbox"].remove_at(i)
	if op["kind"] == "deposit" and not result.get("ok", false):
		add_items(op["items"], true)              # refused: give everything back
		if int(op["coins"]) > 0: add_coins(int(op["coins"]))
	elif op["kind"] == "collect" and result.get("ok", false):
		add_items(result.get("items", {}), true)
		if int(result.get("coins", 0)) > 0: add_coins(int(result["coins"]))
		stat("trades")
	event.emit("outbox", {})

## A friend watered a crop: it finishes 5 minutes sooner.
func apply_help(plot: int, now: float) -> void:
	if plot >= 0 and plot < s["plots"].size() and s["plots"][plot]["crop"] != "":
		s["plots"][plot]["ready_at"] = maxf(now, float(s["plots"][plot]["ready_at"]) - 300.0)
		event.emit("plot", {"index": plot})

# ------------------------------------------------------------ livestock
# Animals are cared for, never harmed: feed -> timed production -> collect.

func housing_capacity(h: String) -> int:
	return int(GameData.buildings()[h]["levels"][building_level(h)]["capacity"]) if owns_building(h) else 0

func buy_animal(h: String, now: float) -> String:
	if not owns_building(h): return "not_owned"
	var kind: String = GameData.buildings()[h]["animal"]
	var a: Dictionary = GameData.animals()[kind]
	if not is_unlocked(a["unlock_level"]): return "locked"
	if s["animals"][h].size() >= housing_capacity(h): return "housing_full"
	if not spend(int(a["cost"])): return "no_coins"
	s["animals"][h].append({"type": kind, "happiness": int(GameData.animal_rules()["start"]), "hap_t": now,
		"cycle_end": 0.0, "cycles": 0, "last_pet": 0.0})
	stat("animals")
	event.emit("animal", {"housing": h})
	return ""

## Current happiness with decay applied (stored lazily).
func happiness(h: String, i: int, now: float) -> int:
	var a: Dictionary = s["animals"][h][i]
	var hours := maxf(0.0, (now - float(a["hap_t"])) / 3600.0)
	var v := clampi(int(a["happiness"]) - int(floor(hours * float(GameData.animal_rules()["decay_per_hour"]))), 0, 100)
	if hours >= 1.0:
		a["happiness"] = v
		a["hap_t"] = now
	return v

func _add_happiness(h: String, i: int, n: int, now: float) -> void:
	var a: Dictionary = s["animals"][h][i]
	a["happiness"] = clampi(happiness(h, i, now) + n, 0, 100)
	a["hap_t"] = now

func animal_state(h: String, i: int, now: float) -> String:
	var a: Dictionary = s["animals"][h][i]
	if float(a["cycle_end"]) == 0.0: return "hungry"
	return "ready" if float(a["cycle_end"]) <= now else "producing"

func feed_animal(h: String, i: int, now: float) -> String:
	if animal_state(h, i, now) != "hungry": return "not_hungry"
	var kind: Dictionary = GameData.animals()[s["animals"][h][i]["type"]]
	if not remove_items(kind["feed"]): return "no_feed"
	s["animals"][h][i]["cycle_end"] = now + float(kind["cycle_seconds"])
	_add_happiness(h, i, int(GameData.animal_rules()["per_feed"]), now)
	stat("animals_fed")
	event.emit("animal", {"housing": h})
	return ""

func pet_animal(h: String, i: int, now: float) -> String:
	var a: Dictionary = s["animals"][h][i]
	if float(a["last_pet"]) > 0.0 and now - float(a["last_pet"]) < float(GameData.animal_rules()["pet_cooldown_seconds"]): return "pet_cooldown"
	a["last_pet"] = now
	_add_happiness(h, i, int(GameData.animal_rules()["per_pet"]), now)
	stat("pets")
	event.emit("animal", {"housing": h, "pet": i})
	return ""

## What one finished cycle gives: main product (+1 when happy) plus "every N cycles" extras.
func animal_products(h: String, i: int, now: float) -> Dictionary:
	var a: Dictionary = s["animals"][h][i]
	var kind: Dictionary = GameData.animals()[a["type"]]
	var out := {}
	var first := true
	for p in kind["products"]:
		var every := int(p.get("every", 1))
		if (int(a["cycles"]) + 1) % every != 0: continue
		var q := int(p["qty"])
		if first and happiness(h, i, now) >= int(GameData.animal_rules()["bonus_happiness"]): q += 1
		first = false
		out[p["item"]] = q
	return out

func collect_animal(h: String, i: int, now: float) -> String:
	if animal_state(h, i, now) != "ready": return "not_ready"
	var got := animal_products(h, i, now)
	if not add_items(got): return "barn_full"
	var a: Dictionary = s["animals"][h][i]
	a["cycles"] = int(a["cycles"]) + 1
	a["cycle_end"] = 0.0
	add_xp(int(GameData.animals()[a["type"]]["xp"]))
	stat("animal_goods")
	event.emit("collect", {"housing": h, "items": got})
	return ""

func animals_ready(h: String, now: float) -> int:
	var n := 0
	for i in s["animals"].get(h, []).size():
		if animal_state(h, i, now) == "ready": n += 1
	return n

## One tap for the whole pen: collect what's ready, then feed everyone hungry.
func tend_all(h: String, now: float) -> Dictionary:
	var r := {"collected": 0, "fed": 0, "error": ""}
	for i in s["animals"][h].size():
		if animal_state(h, i, now) == "ready":
			var e := collect_animal(h, i, now)
			if e == "": r["collected"] += 1
			else: r["error"] = e
		if animal_state(h, i, now) == "hungry":
			var e2 := feed_animal(h, i, now)
			if e2 == "": r["fed"] += 1
			elif r["error"] == "": r["error"] = e2
	return r

# ------------------------------------------------------------ daily rewards, achievements, events

## Local calendar day number (so the streak follows the player's midnight).
static func local_day(now: float) -> int:
	var bias: float = Time.get_time_zone_from_system().get("bias", 0) * 60.0
	return int(floor((now + bias) / 86400.0))

## Index 0..6 of the reward that can be claimed today, or -1 if already claimed.
func daily_index(now: float) -> int:
	var d: Dictionary = s["daily"]
	var today := local_day(now)
	if int(d.get("last", -10)) == today: return -1
	var streak := int(d.get("streak", 0)) if int(d.get("last", -10)) == today - 1 else 0
	return streak % GameData.daily_rewards().size()

func claim_daily(now: float) -> Dictionary:
	var i := daily_index(now)
	if i < 0: return {}
	var r: Dictionary = GameData.daily_rewards()[i]
	s["daily"] = {"last": local_day(now), "streak": i + 1}
	_grant(r)
	if i == GameData.daily_rewards().size() - 1: stat("daily_streak_7")
	event.emit("daily", {"index": i})
	return r

func _grant(r: Dictionary) -> void:
	if r.has("coins"): add_coins(int(r["coins"]))
	if r.has("gems"): add_gems(int(r["gems"]))
	if r.has("items"): add_items(r["items"], true)
	if r.has("decor"): s["decor"].append({"id": r["decor"], "x": 0, "y": 0})

func achievement_done(id: String) -> bool:
	var a: Dictionary = GameData.achievements()[id]
	return int(s["stats"].get(a["stat"], 0)) >= int(a["goal"])

func claim_achievement(id: String) -> String:
	if id in s["achievements"]: return "owned"
	if not achievement_done(id): return "not_ready"
	s["achievements"].append(id)
	_grant(GameData.achievements()[id]["reward"])
	event.emit("achievement_claimed", {"id": id})
	return ""

func unclaimed_achievements() -> int:
	return GameData.achievements().keys().filter(func(id): return achievement_done(id) and not id in s["achievements"]).size()

static func _mmdd(now: float) -> String:
	var bias: float = Time.get_time_zone_from_system().get("bias", 0) * 60.0
	var d := Time.get_date_dict_from_unix_time(int(now + bias))
	return "%02d-%02d" % [d["month"], d["day"]]

## Events whose MM-DD window contains today (windows may wrap over New Year).
static func active_events(now: float) -> Array:
	var today := _mmdd(now)
	var out := []
	for id in GameData.events():
		var e: Dictionary = GameData.events()[id]
		var inside: bool = (today >= e["start"] and today <= e["end"]) if e["start"] <= e["end"] else (today >= e["start"] or today <= e["end"])
		if inside:
			var c := e.duplicate()
			c["id"] = id
			out.append(c)
	return out

## Progress key includes the year so the event can be done again next year.
func _event_key(id: String, now: float) -> String:
	var e: Dictionary = GameData.events()[id]
	var bias: float = Time.get_time_zone_from_system().get("bias", 0) * 60.0
	var year: int = Time.get_date_dict_from_unix_time(int(now + bias))["year"]   # local year, like _mmdd
	if e["start"] > e["end"] and _mmdd(now) <= e["end"]:
		year -= 1                     # January part of a December event counts as last year's
	return "%s:%d" % [id, year]

func event_progress(id: String, now: float) -> Dictionary:
	var k := _event_key(id, now)
	if not s["events"].has(k): s["events"][k] = {"given": {}, "claimed": false}
	return s["events"][k]

func contribute_event(id: String, item: String, qty: int, now: float) -> String:
	var goal: Dictionary = GameData.events()[id]["goal"]["items"]
	var p := event_progress(id, now)
	var left := int(goal.get(item, 0)) - int(p["given"].get(item, 0))
	qty = mini(qty, left)
	if qty <= 0: return "not_needed"
	if not remove_items({item: qty}): return "missing_items"
	p["given"][item] = int(p["given"].get(item, 0)) + qty
	event.emit("event", {"id": id})
	return ""

func claim_event(id: String, now: float) -> String:
	var p := event_progress(id, now)
	if p["claimed"]: return "owned"
	var goal: Dictionary = GameData.events()[id]["goal"]["items"]
	for it in goal:
		if int(p["given"].get(it, 0)) < int(goal[it]): return "not_ready"
	p["claimed"] = true
	_grant(GameData.events()[id]["reward"])
	stat("events")
	event.emit("event", {"id": id, "claimed": true})
	return ""

# ------------------------------------------------------------ monetization rewards (only after Ads/IAP say yes)

## Rewarded ad: finish a crop timer for free.
func ad_finish_plot(i: int, now: float) -> String:
	if plot_remaining(i, now) <= 0.0: return "not_needed"
	s["plots"][i]["ready_at"] = now
	event.emit("plot", {"index": i})
	return ""

## Rewarded ad: deliver an order for double coins.
func fulfill_delivery_doubled(i: int, now: float) -> String:
	var bonus := int(s["deliveries"][i].get("coins", 0))
	var err := fulfill_delivery(i, now)
	if err == "": add_coins(bonus)
	return err

func grant_purchase(id: String, p: Dictionary) -> void:
	if not s["flags"].has("purchases"): s["flags"]["purchases"] = []
	s["flags"]["purchases"].append(id)
	if p.get("remove_ads", false): s["flags"]["remove_ads"] = true
	_grant(p)
	event.emit("purchase", {"id": id})
