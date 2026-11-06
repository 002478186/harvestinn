## Loads and caches every balancing/content file under res://data.
## Pure static access so core logic and tests can use it without the scene tree.
class_name GameData
extends RefCounted

static var _cache: Dictionary = {}

static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: missing or empty %s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("GameData: invalid JSON in %s" % path)
		return {}
	if parsed is Dictionary:
		parsed.erase("_doc")
	_cache[path] = parsed
	return parsed

static func items() -> Dictionary: return load_json("res://data/items.json")
static func crops() -> Dictionary: return load_json("res://data/crops.json")
static func recipes() -> Dictionary: return load_json("res://data/recipes.json")
static func buildings() -> Dictionary: return load_json("res://data/buildings.json")
static func animals() -> Dictionary: return load_json("res://data/animals.json")["animals"]
static func animal_rules() -> Dictionary: return load_json("res://data/animals.json")["happiness"]
static func economy() -> Dictionary: return load_json("res://data/economy.json")
static func cosmetics() -> Dictionary: return load_json("res://data/cosmetics.json")
static func achievements() -> Dictionary: return load_json("res://data/achievements.json")
static func daily_rewards() -> Array: return load_json("res://data/daily_rewards.json")["rewards"]
static func events() -> Dictionary: return load_json("res://data/events.json")
static func characters() -> Dictionary: return load_json("res://data/characters.json")
static func dialogue(lang: String = "en") -> Dictionary: return load_json("res://data/dialogue/%s.json" % lang)
static func tutorial() -> Array: return load_json("res://data/tutorial.json")["steps"]

static func item_name(id: String) -> String:
	return str(items().get(id, {}).get("name", id))

static func item_price(id: String) -> int:
	return int(items().get(id, {}).get("price", 0))

static func item_category(id: String) -> String:
	return str(items().get(id, {}).get("category", "goods"))

## Crops go to the silo; everything else to the barn.
static func storage_kind(id: String) -> String:
	return "silo" if item_category(id) == "crop" else "barn"

static func recipes_for(building_id: String) -> Array[String]:
	var out: Array[String] = []
	for rid in recipes():
		if recipes()[rid]["building"] == building_id:
			out.append(rid)
	out.sort_custom(func(a, b): return int(recipes()[a]["unlock_level"]) < int(recipes()[b]["unlock_level"]))
	return out

## Everything that unlocks exactly at `level` — used by the level-up popup.
static func unlocks_at(level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in crops():
		if int(crops()[id]["unlock_level"]) == level:
			out.append({"kind": "crop", "id": id, "name": item_name(id)})
	for id in recipes():
		if int(recipes()[id]["unlock_level"]) == level:
			out.append({"kind": "recipe", "id": id, "name": item_name(id)})
	for id in buildings():
		if int(buildings()[id]["unlock_level"]) == level and id != "inn" and id != "kitchen":
			out.append({"kind": "building", "id": id, "name": str(buildings()[id]["name"])})
	for id in animals():
		if int(animals()[id]["unlock_level"]) == level:
			out.append({"kind": "animal", "id": id, "name": str(animals()[id]["name"])})
	var feats: Dictionary = economy()["features"]
	for f in feats:
		if int(feats[f]) == level:
			out.append({"kind": "feature", "id": f, "name": f.capitalize()})
	for exp in economy()["land_expansions"]:
		if int(exp["unlock_level"]) == level:
			out.append({"kind": "land", "id": "land", "name": "Land expansion"})
	for c in cosmetics():
		if int(cosmetics()[c].get("unlock_level", 999)) == level:
			out.append({"kind": "cosmetic", "id": c, "name": str(cosmetics()[c]["name"])})
	return out
