## Looks up character lines (by trigger) and tutorial text from the string table.
class_name Dialogue
extends RefCounted

static var lang := "en"

static func text(line_id: String, player_name := "") -> String:
	var t := str(GameData.dialogue(lang).get(line_id, GameData.dialogue("en").get(line_id, line_id)))
	return t.replace("{name}", player_name if player_name != "" else "friend")

## Every {speaker, line} that reacts to `trigger` (e.g. "level_5", "unlock:mill").
static func reactions(trigger: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cast := GameData.characters()
	for cid in cast:
		var ids: Array = cast[cid].get("lines", {}).get(trigger, [])
		if not ids.is_empty():
			out.append({"speaker": cid, "line": ids.pick_random()})
	return out

## Reactions for a level-up: the level line plus one per unlock.
static func for_level_up(level: int, unlocks: Array) -> Array[Dictionary]:
	var out := reactions("level_%d" % level)
	for u in unlocks:
		out.append_array(reactions("unlock:%s" % u["id"]))
	return out
