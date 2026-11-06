## Versioned, crash-safe save format (JSON).
## write: temp file -> keep previous as .bak -> rename.  read: main file, else .bak.
## Every save carries "version"; MIGRATIONS[v] upgrades a v save to v+1.
class_name SaveCodec
extends RefCounted

const VERSION := 2

## v1 -> v2: buildings, animals, inn, orders and the rest arrived after the first
## farm-only format; fill_defaults() supplies their empty state.
const MIGRATIONS := {
	1: "_m1_to_2",
}

static func _m1_to_2(d: Dictionary) -> Dictionary:
	d["stats"] = d.get("stats", {})
	if d.has("gold"):                # pre-release builds called coins "gold"
		d["coins"] = d["gold"]
		d.erase("gold")
	return d

static func encode(s: Dictionary) -> String:
	return JSON.stringify(s)

## Returns {} when the text is not a usable save. Refuses saves from a newer build.
static func decode(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not d is Dictionary or not d.has("version"):
		return {}
	d = _ints(d)
	var v := int(d["version"])
	if v > VERSION:
		push_warning("save is from a newer version (%d)" % v)
		return {}
	while v < VERSION:
		d = Callable(SaveCodec, MIGRATIONS[v]).call(d)
		v += 1
		d["version"] = v
	fill_defaults(d)
	return d if _valid(d) else {}

## Keys added after v1 start empty; keeps old saves and new code compatible.
static func fill_defaults(d: Dictionary) -> void:
	var defaults := {
		"reputation": 0, "stats": {}, "storage": {"silo": 0, "barn": 0}, "land": 0,
		"buildings": {}, "animals": {}, "decor": [], "pos": {}, "owned": [],
		"avatar": {"skin": 1, "hair": "short", "hair_color": 0, "outfit": "outfit_overalls", "hat": "hat_straw"},
		"inn": {}, "deliveries": [], "market": {}, "daily": {}, "achievements": [],
		"events": {}, "tutorial": 0, "flags": {}, "outbox": [], "rng": 1, "name": "",
	}
	for k in defaults:
		if not d.has(k):
			d[k] = defaults[k].duplicate(true) if defaults[k] is Dictionary or defaults[k] is Array else defaults[k]

static func _valid(d: Dictionary) -> bool:
	for k in ["coins", "gems", "xp", "level", "inv", "plots", "cols", "rows"]:
		if not d.has(k): return false
	return int(d["level"]) >= 1 and d["plots"] is Array and d["plots"].size() == int(d["cols"]) * int(d["rows"]) \
		and int(d["coins"]) >= 0 and int(d["gems"]) >= 0

## JSON numbers load as floats; whole numbers become ints so counters stay ints.
static func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Dictionary:
		for k in v: v[k] = _ints(v[k])
	elif v is Array:
		for i in v.size(): v[i] = _ints(v[i])
	return v

static func write_atomic(path: String, s: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if not f.store_string(encode(s)):
		return ERR_FILE_CANT_WRITE
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(tmp, path)

static func read(path: String) -> Dictionary:
	for p in [path, path + ".bak"]:
		if FileAccess.file_exists(p):
			var d := decode(FileAccess.get_file_as_string(p))
			if not d.is_empty():
				return d
	return {}
