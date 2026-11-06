extends TestCase

func test_price_bounds_match_server_seed() -> bool:
	eq(TradeRules.min_price("egg"), 6, "egg min (server seed: 6)")
	eq(TradeRules.max_price("egg"), 36, "egg max (server seed: 36)")
	eq(TradeRules.listing_error("egg", 5, 40, 0), "price_out_of_range", "too high")
	eq(TradeRules.listing_error("egg", 5, 20, 4), "listing_slots_full", "slots")
	eq(TradeRules.listing_error("egg", 0, 20, 0), "bad_quantity", "qty")
	eq(TradeRules.listing_error("egg", 5, 20, 0), "", "ok")
	return true

func test_uuid_v4_format() -> bool:
	var u := TradeRules.uuid()
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	truthy(re.search(u) != null, u)
	truthy(u != TradeRules.uuid(), "unique")
	return true

func test_deposit_removes_first_and_refunds_on_refusal() -> bool:
	var m := GameModel.new_game(0.0)
	eq(m.queue_deposit({"wheat": 3}, 10), "", "queued")
	eq(m.count("wheat"), 1, "left the farm immediately")
	eq(m.s["coins"], 40, "coins too")
	var id: String = m.s["outbox"][0]["id"]
	m.finish_op(id, {"error": "deposit_cap"})
	eq(m.count("wheat"), 4, "refunded")
	eq(m.s["coins"], 50, "coins refunded")
	eq(m.queue_deposit({"wheat": 99}, 0), "missing_items", "can't deposit what you don't have")
	return true

func test_collect_adds_server_items_once() -> bool:
	var m := GameModel.new_game(0.0)
	m.queue_collect()
	m.queue_collect()
	eq(m.s["outbox"].size(), 1, "one pending collect")
	var id: String = m.s["outbox"][0]["id"]
	m.finish_op(id, {"ok": true, "items": {"egg": 5}, "coins": 70})
	m.finish_op(id, {"ok": true, "items": {"egg": 5}, "coins": 70})   # duplicate answer ignored
	eq(m.count("egg"), 5, "eggs once")
	eq(m.s["coins"], 120, "coins once")
	return true

func test_server_rules_seed_matches_items() -> bool:
	var sql := FileAccess.get_file_as_string("res://backend/supabase/migrations/20261106000003_item_rules_seed.sql")
	for id in GameData.items():
		truthy(sql.contains("('%s', %d, %d, %d)" % [id, GameData.item_price(id), TradeRules.min_price(id), TradeRules.max_price(id)]), id + " in seed (re-run tools/gen_item_rules_sql.py)")
	return true
