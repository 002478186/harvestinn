extends TestCase

var m: GameModel

func setup() -> void:
	m = GameModel.new_game(0.0)

func test_tutorial_guest_orders_stew_and_pays_markup() -> bool:
	m.tick(0.0)
	eq(m.inn()["guests"].size(), 1, "one table at start")
	eq(m.inn()["guests"][0]["order"], {"carrot_stew": 1}, "tutorial order")
	eq(m.serve_guest(0), "missing_items", "no stew yet")
	m.add_items({"carrot_stew": 1})
	var coins: int = m.s["coins"]
	eq(m.serve_guest(0), "", "served")
	eq(m.s["coins"] - coins, 38, "30 × 1.25 markup")
	eq(m.s["reputation"], 1, "+1 rep")
	return true

func test_tables_limit_guests_and_no_backlog() -> bool:
	m.tick(0.0)
	m.tick(100000.0)
	eq(m.inn()["guests"].size(), 1, "1 table")
	m.s["reputation"] = 80
	m.tick(100000.0 + 90 * 5)
	eq(m.inn()["guests"].size(), 3, "Village Favourite has 3 tables")
	return true

func test_orders_only_use_unlocked_meals_and_tip_grows() -> bool:
	m.s["stats"]["served"] = 5
	m.s["level"] = 4
	m.s["reputation"] = 200
	m.tick(0.0)
	m.tick(1000.0)
	for g in m.inn()["guests"]:
		for meal in g["order"]:
			truthy(meal in m.meals_available(), meal)
	eq(m.order_value({"carrot_stew": 1}), 43, "30 × 1.25 × 1.15 tip at tier 3")
	return true

func test_rooms_build_furnish_and_earn_capped() -> bool:
	m.s["level"] = 20
	m.s["coins"] = 5000
	eq(m.build_room(0.0), "", "build")
	eq(m.room_income(0, 3600.0), 0, "unfurnished earns nothing")
	eq(m.furnish_room(0, 0.0), "missing_items", "needs blanket+pillows")
	m.add_items({"blanket": 1, "pillow": 2}, true)
	eq(m.furnish_room(0, 0.0), "", "furnished")
	eq(m.room_income(0, 7200.0), 80, "40/h × 2h")
	eq(m.room_income(0, 3600.0 * 100), 480, "capped at 12h")
	eq(m.collect_room(0, 7200.0), "", "collect")
	eq(m.room_income(0, 7200.0), 0, "reset")
	return true

func test_serving_beats_selling_ingredients() -> bool:
	# The inn tier must pay more than selling the stew's raw carrots + wheat.
	var raw := GameData.item_price("carrot") * 2 + GameData.item_price("wheat") * 2
	truthy(m.order_value({"carrot_stew": 1}) > raw * 1.5, "serve %d vs raw %d" % [m.order_value({"carrot_stew": 1}), raw])
	return true
