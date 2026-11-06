extends TestCase

var m: GameModel

func setup() -> void:
	m = GameModel.new_game(0.0)
	m.s["coins"] = 10_000
	m.s["level"] = 8

func test_kitchen_exists_and_cooks() -> bool:
	eq(m.queue_recipe("kitchen", "carrot_stew", 0.0), "", "queue stew")
	eq(m.count("carrot"), 0, "carrots used")
	eq(m.collect_building("kitchen", 29.0), "not_ready", "29s")
	eq(m.collect_building("kitchen", 30.0), "", "30s")
	eq(m.count("carrot_stew"), 1, "stew")
	eq(m.s["stats"]["cooked"], 1, "stat")
	return true

func test_build_and_sequential_queue() -> bool:
	eq(m.queue_recipe("mill", "flour", 0.0), "not_owned", "need mill")
	eq(m.build("mill"), "", "build")
	eq(m.s["coins"], 10_000 - 150, "cost")
	m.add_items({"wheat": 20})
	m.queue_recipe("mill", "flour", 0.0)
	m.queue_recipe("mill", "flour", 0.0)
	eq(m.queue_recipe("mill", "flour", 0.0), "queue_full", "2 slots")
	eq(m.s["buildings"]["mill"]["queue"][1]["end"], 240, "second job waits for first")
	m.collect_building("mill", 250.0)
	eq(m.count("flour"), 2, "both collected")
	return true

func test_missing_inputs_and_locked() -> bool:
	m.build("bakery")
	eq(m.queue_recipe("bakery", "bread", 0.0), "missing_items", "no flour")
	eq(m.queue_recipe("bakery", "cake", 0.0), "locked", "cake L17")
	return true

func test_upgrade_adds_slots_and_speedup_shifts_queue() -> bool:
	m.build("mill")
	eq(m.upgrade_building("mill"), "", "upgrade")
	eq(m.slots("mill"), 3, "3 slots")
	m.add_items({"wheat": 9})
	for i in 3: m.queue_recipe("mill", "flour", 0.0)
	eq(m.speed_up_job("mill", 0.0), "", "speed up")
	eq(m.s["buildings"]["mill"]["queue"][2]["end"], 240, "all shifted 120s")
	return true

func test_offline_counts_jobs() -> bool:
	m.queue_recipe("kitchen", "carrot_stew", 0.0)
	eq(m.offline_summary(0.0, 100.0)["jobs"], 1, "job finished offline")
	return true

func test_every_recipe_adds_value() -> bool:
	# Processing must beat selling the raw ingredients (feed is exempt: it exists for animals).
	for rid in GameData.recipes():
		var r: Dictionary = GameData.recipes()[rid]
		var cost := 0
		for i in r["inputs"]: cost += GameData.item_price(i) * int(r["inputs"][i])
		var value := 0
		for o in r["outputs"]: value += GameData.item_price(o) * int(r["outputs"][o])
		if rid != "animal_feed":
			truthy(value >= cost * 1.15, "%s value %d vs inputs %d" % [rid, value, cost])
	return true
