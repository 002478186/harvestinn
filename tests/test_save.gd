extends TestCase

const PATH := "user://test_codec.json"

func setup() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)

func test_roundtrip_keeps_ints_and_state() -> bool:
	var m := new_farm(1000.0)
	m.plant(0, "wheat", 1000.0)
	m.add_xp(5)
	eq(SaveCodec.write_atomic(PATH, m.s), OK, "write")
	var d := SaveCodec.read(PATH)
	eq(d["coins"], m.s["coins"], "coins")
	eq(typeof(d["level"]), TYPE_INT, "level stays int")
	eq(d["plots"][0]["crop"], "wheat", "plot")
	eq(d["plots"][0]["ready_at"], 1000 + int(GameData.crops()["wheat"]["grow_seconds"]), "timer")
	return true

func test_corrupt_main_falls_back_to_bak() -> bool:
	var m := new_farm(0.0)
	SaveCodec.write_atomic(PATH, m.s)
	m.s["coins"] = 999
	SaveCodec.write_atomic(PATH, m.s)          # first save is now .bak
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{\"version\": 2, \"coi")  # truncated by a crash
	f.close()
	eq(SaveCodec.read(PATH)["coins"], 50, "loaded .bak")
	return true

func test_migrates_v1_save() -> bool:
	var v1 := {"version": 1, "gold": 77, "gems": 3, "xp": 0, "level": 2, "inv": {}, "cols": 1, "rows": 1,
		"plots": [{"crop": "", "ready_at": 0, "planted_at": 0}], "last_seen": 0}
	var d := SaveCodec.decode(JSON.stringify(v1))
	eq(d["version"], SaveCodec.VERSION, "upgraded")
	eq(d["coins"], 77, "gold renamed to coins")
	truthy(d.has("buildings") and d.has("inn"), "defaults filled")
	eq(d["parcels"], 1, "v2 grid -> 1 parcel")
	eq(d["plots"].size(), 6, "padded to a whole field")
	return true

func test_rejects_newer_and_garbage() -> bool:
	eq(SaveCodec.decode("{\"version\": 999}"), {}, "newer refused")
	eq(SaveCodec.decode("not json"), {}, "garbage")
	eq(SaveCodec.decode("{\"version\": 2, \"coins\": -5}"), {}, "invalid")
	return true

func test_offline_summary_counts_finished_crops() -> bool:
	var m := new_farm(0.0)
	m.plant(0, "wheat", 0.0)     # ready at 45
	m.plant(1, "carrot", 0.0)    # ready at 150
	var w := m.offline_summary(10.0, 100.0)
	eq(w["crops"], 1, "only wheat finished while away")
	eq(m.harvest(0, 100.0), "", "and it's harvestable")
	return true
