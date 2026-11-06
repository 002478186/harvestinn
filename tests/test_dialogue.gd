extends TestCase

func test_every_line_id_exists_in_english() -> bool:
	var table := GameData.dialogue("en")
	for cid in GameData.characters():
		for trig in GameData.characters()[cid].get("lines", {}):
			for id in GameData.characters()[cid]["lines"][trig]:
				truthy(table.has(id), "%s.%s -> %s" % [cid, trig, id])
	for st in GameData.tutorial():
		truthy(table.has(st["line"]), "tutorial " + st["line"])
	return true

func test_cast_has_core_roles_and_8_guests() -> bool:
	var c := GameData.characters()
	for id in ["innkeeper", "chef", "merchant", "vet", "craftsperson"]:
		truthy(c.has(id), id)
	eq(c.values().filter(func(x): return x.get("guest", false)).size() >= 8, true, "8+ guests")
	return true

func test_level_up_reactions() -> bool:
	var r := Dialogue.for_level_up(10, GameData.unlocks_at(10))
	truthy(r.any(func(x): return x["speaker"] == "vet"), "vet reacts to chickens at 10")
	truthy(r.any(func(x): return x["speaker"] == "innkeeper"), "innkeeper level line")
	return true

func test_tutorial_advances_on_goals() -> bool:
	var m := GameModel.new_game(0.0)
	eq(m.s["tutorial"], 0, "starts")
	m.tutorial_tap()
	eq(m.s["tutorial"], 1, "welcome tapped")
	m.plant(0, "wheat", 0.0)
	eq(m.s["tutorial"], 2, "plant goal")
	m.harvest(0, 100.0)
	eq(m.s["tutorial"], 2, "still waiting on cook")
	m.stat("cooked")
	eq(m.s["tutorial"], 4, "cook then harvest already done -> serve")
	m.skip_tutorial()
	truthy(m.tutorial_step().is_empty(), "skipped")
	return true

func test_name_filter() -> bool:
	truthy(NameFilter.is_clean("Farmer Joy"), "clean")
	truthy(not NameFilter.is_clean("Sh1t Farmer"), "l33t blocked")
	truthy(not NameFilter.is_clean("f.u.c.k"), "spacing blocked")
	var m := GameModel.new_game(0.0)
	eq(m.set_player_name("a"), "name_short", "short")
	eq(m.set_player_name("Hazel"), "", "ok")
	return true
