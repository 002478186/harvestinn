class_name TestCase
extends RefCounted

var failures: Array[String] = []
var tree: SceneTree

func setup() -> void:
	pass

## New game that already owns its first field (6 plots); coins unchanged.
static func new_farm(now: float) -> GameModel:
	var m := GameModel.new_game(now)
	var cost := int(GameData.economy()["parcels"]["list"][0]["cost"])
	m.s["coins"] += cost
	m.buy_parcel()
	return m

func eq(actual, expected, label: String = "") -> bool:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		if is_equal_approx(float(actual), float(expected)):
			return true
	elif actual == expected:
		return true
	failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
	return false

func truthy(v, label: String = "") -> bool:
	if v:
		return true
	failures.append("%s: expected truthy, got %s" % [label, str(v)])
	return false
