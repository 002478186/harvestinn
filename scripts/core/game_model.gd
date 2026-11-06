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
	var cols := int(eco["plots"]["start_cols"])
	var rows := int(eco["plots"]["start_rows"])
	var m := GameModel.new({
		"version": SaveCodec.VERSION,
		"created": now, "last_seen": now,
		"coins": int(eco["start"]["coins"]), "gems": int(eco["start"]["gems"]),
		"xp": 0, "level": 1, "reputation": 0,
		"inv": eco["start"]["items"].duplicate(),
		"cols": cols, "rows": rows, "land": 0,
		"plots": [],
		"storage": {"silo": 0, "barn": 0},
		"stats": {},
	})
	for i in cols * rows:
		m.s["plots"].append(_empty_plot())
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

## True when a building has finished work waiting to be collected (shows a bubble).
func building_has_ready(_id: String, _now: float) -> bool:
	return false

# ------------------------------------------------------------ offline progress

## What finished while the app was closed. Timers are absolute timestamps, so the
## work itself already happened; this only counts it for the "Welcome back" card.
func offline_summary(since: float, now: float) -> Dictionary:
	var out := {"away": now - since, "crops": 0}
	for p in s["plots"]:
		if p["crop"] != "" and float(p["ready_at"]) > since and float(p["ready_at"]) <= now:
			out["crops"] += 1
	return out

# ------------------------------------------------------------ tutorial

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
