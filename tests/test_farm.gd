extends TestCase

var m: GameModel

func setup() -> void:
	m = GameModel.new_game(1000.0)

func test_new_game_has_start_resources() -> bool:
	eq(m.s["coins"], 50, "coins")
	eq(m.s["plots"].size(), 12, "plots 4x3")
	eq(m.count("wheat"), 4, "start wheat")
	return true

func test_plant_costs_seed_and_harvest_after_timer() -> bool:
	eq(m.plant(0, "wheat", 1000.0), "", "plant ok")
	eq(m.s["coins"], 49, "seed cost")
	eq(m.plant(0, "wheat", 1000.0), "plot_busy", "busy")
	eq(m.harvest(0, 1059.0), "not_ready", "not ready at 59s")
	eq(m.plot_progress(0, 1030.0), 0.5, "half grown")
	eq(m.harvest(0, 1060.0), "", "ready at 60s")
	eq(m.count("wheat"), 6, "yield 2")
	eq(m.s["xp"], 1, "xp")
	return true

func test_locked_crop_and_no_coins() -> bool:
	eq(m.plant(0, "pumpkin", 0.0), "locked", "pumpkin locked at L1")
	m.s["coins"] = 0
	eq(m.plant(0, "carrot", 0.0), "no_coins", "broke")
	return true

func test_level_up_awards_gems_and_lists_unlocks() -> bool:
	var ups: Array = []
	m.event.connect(func(n, d): if n == "level_up": ups.append(d))
	m.add_xp(GameModel.xp_to_next(1))
	eq(m.s["level"], 2, "level 2")
	eq(m.s["gems"], 11, "+1 gem")
	truthy(ups[0]["unlocks"].any(func(u): return u["id"] == "potato"), "potato unlocks at 2")
	return true

func test_multi_level_and_cap() -> bool:
	m.add_xp(10_000_000)
	eq(m.s["level"], 50, "capped at 50")
	return true

func test_silo_full_blocks_harvest() -> bool:
	m.s["inv"]["wheat"] = m.storage_cap("silo")
	m.plant(0, "carrot", 0.0)
	eq(m.harvest(0, 1e9), "silo_full", "full")
	return true

func test_speedup_costs_gems() -> bool:
	m.plant(0, "carrot", 0.0)
	eq(GameModel.speedup_cost(300.0), 1, "5 min = 1 gem")
	eq(m.speed_up_plot(0, 0.0), "", "sped")
	eq(m.s["gems"], 9, "paid")
	eq(m.harvest(0, 0.0), "", "harvest now")
	return true
