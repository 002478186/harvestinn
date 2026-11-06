extends TestCase

var m: GameModel

func setup() -> void:
	m = new_farm(0.0)
	m.s["coins"] = 100_000
	m.s["level"] = 22

func test_buy_feed_produce_collect() -> bool:
	eq(m.buy_animal("coop", 0.0), "not_owned", "need a coop")
	eq(m.build("coop"), "", "build coop")
	eq(m.buy_animal("coop", 0.0), "", "hen")
	eq(m.animal_state("coop", 0, 0.0), "hungry", "hungry")
	eq(m.feed_animal("coop", 0, 0.0), "no_feed", "no feed")
	m.add_items({"animal_feed": 5})
	eq(m.feed_animal("coop", 0, 0.0), "", "fed")
	eq(m.animal_state("coop", 0, 600.0), "producing", "producing")
	eq(m.collect_animal("coop", 0, 1200.0), "", "collect at 20 min")
	eq(m.count("egg"), 1, "1 egg (happiness 68 < 75)")
	eq(m.count("feather"), 0, "feather only every 2nd cycle")
	m.feed_animal("coop", 0, 1200.0)
	m.collect_animal("coop", 0, 2400.0)
	eq(m.count("feather"), 1, "feather on 2nd cycle")
	return true

func test_happy_animals_give_bonus_and_happiness_decays() -> bool:
	m.build("barn_stall")
	m.buy_animal("barn_stall", 0.0)
	m.pet_animal("barn_stall", 0, 1.0)                 # 60 + 15
	eq(m.pet_animal("barn_stall", 0, 10.0), "pet_cooldown", "1h cooldown")
	m.add_items({"animal_feed": 4})
	m.feed_animal("barn_stall", 0, 0.0)                # +8 -> 83
	eq(m.happiness("barn_stall", 0, 0.0), 83, "happy")
	m.collect_animal("barn_stall", 0, 3600.0)
	eq(m.count("milk"), 3, "2 milk + 1 happy bonus")
	eq(m.happiness("barn_stall", 0, 3600.0 * 11), 50, "83 -> 80 at 1h -> 50 at 11h (3/hour)")
	return true

func test_capacity_and_upgrade() -> bool:
	m.build("goat_pen")
	m.buy_animal("goat_pen", 0.0)
	m.buy_animal("goat_pen", 0.0)
	eq(m.buy_animal("goat_pen", 0.0), "housing_full", "2 goats")
	m.upgrade_building("goat_pen")
	eq(m.buy_animal("goat_pen", 0.0), "", "upgrade -> 4")
	return true

func test_locked_until_level_and_tend_all() -> bool:
	m.s["level"] = 9
	m.s["buildings"]["coop"] = {"level": 0, "queue": []}
	m.s["animals"]["coop"] = []
	eq(m.buy_animal("coop", 0.0), "locked", "hens at 10")
	m.s["level"] = 22
	m.buy_animal("coop", 0.0)
	m.buy_animal("coop", 0.0)
	m.add_items({"animal_feed": 10})
	eq(m.tend_all("coop", 0.0)["fed"], 2, "feed all")
	var r := m.tend_all("coop", 1200.0)
	eq(r["collected"], 2, "collect all")
	eq(r["fed"], 2, "and feed again")
	eq(m.offline_summary(1300.0, 2500.0)["animals"], 2, "offline count")
	return true

func test_animal_products_unlock_meals_and_deliveries() -> bool:
	m.s["level"] = 10
	truthy(not "veggie_omelette" in m.meals_available(), "no eggs yet")
	m.build("coop")
	m.buy_animal("coop", 0.0)
	truthy("egg" in m.producible(), "eggs producible")
	truthy("veggie_omelette" in m.meals_available(), "omelette orderable")
	return true
