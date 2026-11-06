extends TestCase

var m: GameModel

func setup() -> void:
	m = new_farm(0.0)
	m.s["coins"] = 100_000

func test_demand_is_bounded_deterministic_and_changes_daily() -> bool:
	var a := GameModel.demand("wheat", 100)
	eq(a, GameModel.demand("wheat", 100), "same day same price")
	var differs := false
	for d in 10:
		var v := GameModel.demand("tomato", d)
		truthy(v >= 0.8 and v <= 1.3, "bounded %f" % v)
		if not is_equal_approx(v, GameModel.demand("tomato", 0)): differs = true
	truthy(differs, "changes across days")
	return true

func test_sell_pays_market_price_and_caps() -> bool:
	var price := GameModel.market_price("wheat", 0.0)
	var coins: int = m.s["coins"]
	eq(m.sell("wheat", 4, 0.0), "", "sell")
	eq(m.s["coins"] - coins, price * 4, "paid")
	eq(m.sell("wheat", 1, 0.0), "missing_items", "none left")
	m.add_items({"wheat": 300}, true)
	eq(m.sell("wheat", 197, 0.0), "sell_cap", "200/day cap")
	eq(m.sell("wheat", 196, 86400.0), "", "new day resets")
	return true

func test_deliveries_generate_from_producible_and_pay_bonus() -> bool:
	m.s["level"] = 3
	m.tick(0.0)
	eq(m.s["deliveries"].size(), 3, "3 slots")
	var d: Dictionary = m.s["deliveries"][0]
	var value := 0
	for it in d["items"]:
		truthy(it in m.producible(), it)
		value += GameData.item_price(it) * int(d["items"][it])
	eq(d["coins"], round(value * 1.5), "bonus 1.5x")
	m.add_items(d["items"], true)
	eq(m.fulfill_delivery(0, 0.0), "", "fulfil")
	truthy(m.s["deliveries"][0]["items"].is_empty(), "cooling down")
	m.tick(1800.0)
	truthy(not m.s["deliveries"][0]["items"].is_empty(), "refilled after 30 min")
	return true

func test_fields_are_bought_one_by_one() -> bool:
	var g := GameModel.new_game(0.0)
	eq(g.s["plots"].size(), 0, "a new farm owns no land")
	eq(g.plant(0, "wheat", 0.0), "bad_plot", "nothing to plant on")
	eq(g.buy_parcel(), "", "first field: 20 coins")
	eq(g.s["coins"], 30, "paid")
	eq(g.s["plots"].size(), 6, "6 plots")
	g.plant(2, "wheat", 0.0)
	g.s["coins"] = 10_000
	eq(g.buy_parcel(), "", "second field")
	eq(g.s["plots"][2]["crop"], "wheat", "existing crops stay put")
	eq(g.s["plots"].size(), 12, "12 plots")
	eq(g.buy_parcel(), "locked", "third field needs level 2")
	return true

func test_storage_and_cosmetics() -> bool:
	eq(m.upgrade_storage("silo"), "", "silo up")
	eq(m.storage_cap("silo"), 100, "100")
	m.s["level"] = 13
	eq(m.buy_cosmetic("furn_fireplace"), "", "furniture")
	eq(m.s["reputation"], 5, "+5 rep")
	eq(m.buy_cosmetic("furn_fireplace"), "owned", "once")
	eq(m.buy_cosmetic("decor_well", 2, 3), "", "decor")
	eq(m.s["decor"][0], {"id": "decor_well", "x": 2, "y": 3}, "placed")
	eq(m.buy_cosmetic("hat_sunflower"), "no_gems", "20 gems, has 10")
	m.s["gems"] = 25
	eq(m.buy_cosmetic("hat_sunflower"), "", "gem item")
	eq(m.s["gems"], 5, "paid 20 gems")
	truthy(m.owns("hat_sunflower"), "owned")
	return true
