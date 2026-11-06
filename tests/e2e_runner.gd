## End-to-end: the real Net client against tools/dev_backend.py (Postgres + PostgREST).
## Run: python3 tools/dev_backend.py --e2e
extends SceneTree

var failed := 0
var passed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)

func _initialize() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	var net: Node = root.get_node("Net")
	game.save_path = "user://e2e_save.json"
	net.url = OS.get_environment("HARVEST_BACKEND_URL")
	net.key = OS.get_environment("HARVEST_BACKEND_KEY")
	net.session = {}

	# --- player A signs in as a guest; first cloud save is pushed
	var a := GameModel.new_game(game.now())
	game.set_model(a)
	check(await net.connect_now(), "A online")
	check(int(a.s["flags"].get("cloud_rev", 0)) == 1, "A cloud save pushed (rev 1)")
	var a_session: Dictionary = net.session.duplicate(true)

	# --- A lists 5 eggs at 20
	a.add_items({"egg": 10}, true)
	check(a.queue_deposit({"egg": 5}, 0) == "", "A queues deposit")
	check(await net.trade_call("create_listing", {"p_item": "egg", "p_qty": 5, "p_price_each": 20}) == "", "A lists eggs")
	check(a.count("egg") == 5 and a.s["outbox"].is_empty(), "eggs left A's farm, outbox clear")
	check(await net.trade_call("create_listing", {"p_item": "egg", "p_qty": 5, "p_price_each": 999}) == "price_out_of_range", "server rejects price")

	# --- player B buys it
	net.session = {}
	var b := GameModel.new_game(game.now())
	b.s["coins"] = 500
	game.set_model(b)
	check(await net.connect_now(), "B online")
	var r: Dictionary = await net.call_rpc("browse_listings", {"p_items": ["egg"], "p_limit": 10})
	check(r["code"] == 200 and r["data"].size() == 1, "B sees the listing")
	var lid := int(r["data"][0]["id"])
	b.queue_deposit({}, 100)
	check(await net.trade_call("buy_listing", {"p_listing": lid}) == "", "B buys")
	check(await net.trade_call("buy_listing", {"p_listing": lid}) == "already_sold", "no double purchase")
	await net.collect_all()
	check(b.count("egg") == 5 and int(b.s["coins"]) == 400, "B received eggs, paid 100")

	# --- idempotency: same request id twice deposits once
	b.add_items({"milk": 3}, true)
	b.queue_deposit({"milk": 3}, 0)
	var op: Dictionary = b.s["outbox"][0].duplicate()
	await net.process_outbox()
	r = await net.call_rpc("deposit", {"p_request_id": op["id"], "p_items": op["items"], "p_coins": 0})   # "lost response" retry
	var mine: Dictionary = (await net.call_rpc("my_trading"))["data"]
	check(int(mine["escrow"].get("milk", 0)) == 3, "retried deposit counted once")

	# --- A collects the sale (100 - 5% fee)
	net.session = a_session
	game.set_model(a)
	var before := int(a.s["coins"])
	await net.collect_all()
	check(int(a.s["coins"]) - before == 95, "A got 95 coins")

	# --- cloud conflict: another device moved the cloud ahead while A also changed
	var got := []
	net.cloud_conflict.connect(func(s): got.append(s))
	a.s["flags"]["cloud_rev"] = 0
	a.s["flags"]["cloud_dirty"] = true
	await net.sync()
	check(got.size() == 1, "conflict detected")
	await net.keep_local(got[0])
	check(int(a.s["flags"]["cloud_rev"]) >= 2, "kept this device's save")

	# --- friends + help
	var codes: Dictionary = await net.get_rows("profiles", "select=friend_code&id=eq." + net.user_id())
	var a_code: String = codes["data"][0]["friend_code"]
	net.session = {}
	game.set_model(GameModel.new_game(game.now()))
	await net.connect_now()
	check(await net.trade_call("add_friend", {"p_code": a_code}) == "", "C adds A")
	check(await net.trade_call("add_friend", {"p_code": "ZZZZZZZZ"}) == "unknown_code", "bad code")
	var fr: Dictionary = await net.call_rpc("list_friends")
	check(fr["data"].size() == 1, "C has 1 friend")
	var v: Dictionary = await net.call_rpc("visit_farm", {"p_friend": fr["data"][0]["id"]})
	check(v["code"] == 200 and v["data"].has("plots"), "visit snapshot")

	print("E2E: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
