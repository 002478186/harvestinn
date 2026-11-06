## Online marketplace, trade offers, friends, farm visits and price charts.
## Every action goes through Net (server-authoritative); this file only shows state.
class_name TradeScreens
extends RefCounted

static func tr_(s: String) -> String:
	return TranslationServer.translate(s)

## True if online features can be shown; otherwise adds the offline / locked card.
static func gate(main, body: VBoxContainer, feature: String) -> bool:
	var lvl := int(GameData.economy()["features"][feature])
	if not Game.model.is_unlocked(lvl):
		body.add_child(UI.label(tr_("Unlocks at level %d") % lvl, 28, UI.WOOD_DARK))
		return false
	if not Net.online:
		var p := PanelContainer.new()
		var v := VBoxContainer.new()
		p.add_child(v)
		v.add_child(UI.icon_rect(UI.icon("market"), 96))
		v.add_child(UI.label(tr_("Connect to the internet to trade"), 30, UI.RED, 600))
		v.add_child(UI.label(tr_("Your farm, inn and village market all work offline. Trades sync when you're back."), 24))
		if Net.configured():
			v.add_child(UI.button(tr_("Try again"), func():
				await Net.connect_now()
				main.hud.toast(tr_("Connected!") if Net.online else tr_("Still offline")), UI.SKY))
		body.add_child(p)
		return false
	return true

static func _fail(main, err: String) -> bool:
	if err == "": return false
	main.say_error(err)
	return true

# ------------------------------------------------------------------ marketplace

static func market(main, body: VBoxContainer, query := "") -> void:
	if not gate(main, body, "online_market"): return
	var loading := UI.label(tr_("Loading the traders' network…"), 26, UI.WOOD_DARK)
	body.add_child(loading)
	var mine: Dictionary = (await Net.call_rpc("my_trading"))["data"]
	if not is_instance_valid(body): return
	loading.queue_free()
	if not mine is Dictionary or not mine.has("wallet"):
		body.add_child(UI.label(tr_("The market is busy, try again in a moment."), 26))
		return
	var again := func(): Screens.market(main, "online")
	# wallet + collect
	var esc: Dictionary = mine["escrow"]
	var w := Screens.row(UI.icon("coin"), tr_("Trade wallet: %d coins") % int(mine["wallet"]),
		tr_("%d items waiting") % esc.values().reduce(func(a, b): return a + int(b), 0), tr_("Collect"), func():
			await Net.collect_all()
			Sfx.play("coins")
			again.call(), int(mine["wallet"]) > 0 or not esc.is_empty(), UI.MEADOW)
	body.add_child(w)
	# offers
	for o in mine["offers_in"]:
		body.add_child(_offer_row(main, o, true, again))
	for o in mine["offers_out"]:
		body.add_child(_offer_row(main, o, false, again))
	# my listings
	body.add_child(UI.label(tr_("My listings (%d/%d)") % [mine["listings"].filter(func(l): return l["status"] == "active").size(), int(GameData.economy()["trade"]["listing_slots"])], 30, UI.RED, 600))
	for l in mine["listings"]:
		var active: bool = l["status"] == "active"
		body.add_child(Screens.row(UI.item_tex(l["item"]), "%s ×%d · %d each" % [tr_(GameData.item_name(l["item"])), int(l["qty"]), int(l["price_each"])],
			tr_(str(l["status"]).capitalize()), tr_("Cancel") if active else "", func():
				if not _fail(main, await Net.trade_call("cancel_listing", {"p_listing": int(l["id"])})): again.call(), active, UI.WOOD_DARK))
	body.add_child(UI.button(tr_("Sell something"), func(): sell_picker(main), UI.MEADOW))
	# market news
	var news: Dictionary = await Net.call_rpc("market_news")
	if news["code"] == 200 and news["data"] is Array and not news["data"].is_empty():
		body.add_child(UI.label(tr_("Market news"), 30, UI.RED, 600))
		for n in news["data"]:
			var pct := int(round((float(n["avg_price"]) / float(n["base_price"]) - 1.0) * 100))
			body.add_child(UI.label("• %s: %d sold today, %s%d%% vs base" % [tr_(GameData.item_name(n["item"])), int(n["volume"]), "+" if pct >= 0 else "", pct], 24))
	# browse
	body.add_child(UI.label(tr_("Browse"), 30, UI.RED, 600))
	var search := LineEdit.new()
	search.placeholder_text = tr_("Search items (e.g. egg, jam)")
	search.text = query
	search.custom_minimum_size.y = UI.MIN_TAP
	search.text_submitted.connect(func(t): _browse(main, body, t))
	body.add_child(search)
	_browse(main, body, query)

static func _browse(main, body: VBoxContainer, query: String) -> void:
	var old := body.find_child("Results", false, false)
	if old: old.queue_free()
	var box := VBoxContainer.new()
	box.name = "Results"
	body.add_child(box)
	var ids := []
	if query.strip_edges() != "":
		for id in GameData.items():
			if GameData.item_name(id).to_lower().contains(query.to_lower().strip_edges()): ids.append(id)
		if ids.is_empty():
			box.add_child(UI.label(tr_("No items match “%s”") % query, 24))
			return
	var r := await Net.call_rpc("browse_listings", {"p_items": ids if not ids.is_empty() else null, "p_limit": 40})
	if not is_instance_valid(box): return
	if r["code"] != 200 or not r["data"] is Array or r["data"].is_empty():
		box.add_child(UI.label(tr_("Nothing for sale right now. Be the first to list!"), 24))
		return
	for l in r["data"]:
		var total := int(l["qty"]) * int(l["price_each"])
		var row := Screens.row(UI.item_tex(l["item"]), "%s ×%d" % [tr_(GameData.item_name(l["item"])), int(l["qty"])],
			tr_("%d each · from %s") % [int(l["price_each"]), l["seller_name"]], tr_("Buy %d") % total, func(): _buy(main, l, total), true, UI.MEADOW)
		var chart := UI.button("", func(): price_chart(main, l["item"]), UI.WOOD, UI.icon("market"))
		chart.tooltip_text = tr_("Price history")
		row.get_child(0).add_child(chart)
		box.add_child(row)

static func _buy(main, l: Dictionary, total: int) -> void:
	var m: GameModel = Game.model
	var mine: Dictionary = (await Net.call_rpc("my_trading"))["data"]
	var need := total - int(mine.get("wallet", 0)) if mine is Dictionary else total
	if need > 0:
		if _fail(main, m.queue_deposit({}, need)): return
	if _fail(main, await Net.trade_call("buy_listing", {"p_listing": int(l["id"])})):
		Screens.market(main, "online")    # coins stay safely in the trade wallet
		return
	await Net.collect_all()
	Sfx.play("coins")
	main.hud.toast(tr_("Bought %s! It's in your barn.") % tr_(GameData.item_name(l["item"])))
	Screens.market(main, "online")

static func sell_picker(main) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("What will you sell?"), 0.8)
	var g := GridContainer.new()
	g.columns = 4
	var ids: Array = m.s["inv"].keys()
	ids.sort()
	for id in ids:
		var b := UI.button("×%d" % m.count(id), func(): listing_form(main, id), UI.CREAM, UI.item_tex(id))
		b.add_theme_color_override("font_color", UI.INK)
		b.custom_minimum_size = Vector2(150, 130)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		g.add_child(b)
	body.add_child(g)

static func listing_form(main, item: String) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("List %s") % tr_(GameData.item_name(item)), 0.7)
	body.add_child(UI.item_row(item, m.count(item), 96))
	var qty := SpinBox.new()
	qty.min_value = 1
	qty.max_value = mini(m.count(item), 999)
	qty.value = mini(m.count(item), 10)
	qty.prefix = tr_("Quantity")
	qty.custom_minimum_size.y = UI.MIN_TAP
	body.add_child(qty)
	var price := SpinBox.new()
	price.min_value = TradeRules.min_price(item)
	price.max_value = TradeRules.max_price(item)
	price.value = GameData.item_price(item)
	price.prefix = tr_("Price each")
	price.custom_minimum_size.y = UI.MIN_TAP
	body.add_child(price)
	var info := UI.label("", 24, UI.WOOD_DARK)
	var upd := func(_v = 0):
		var total := int(qty.value) * int(price.value)
		info.text = tr_("Allowed %d–%d each · market price today %d · you get %d after the %d coin fee") % [
			TradeRules.min_price(item), TradeRules.max_price(item), GameModel.market_price(item, Game.now()), total - TradeRules.fee(total), TradeRules.fee(total)]
	qty.value_changed.connect(upd)
	price.value_changed.connect(upd)
	upd.call()
	body.add_child(info)
	body.add_child(UI.button(tr_("List for 48 hours"), func():
		var n := int(qty.value)
		var p := int(price.value)
		if _fail(main, TradeRules.listing_error(item, n, p, 0)): return
		if _fail(main, m.queue_deposit({item: n}, 0)): return
		if not _fail(main, await Net.trade_call("create_listing", {"p_item": item, "p_qty": n, "p_price_each": p})):
			Sfx.play("coins")
			main.hud.toast(tr_("Listed! Coins arrive in your trade wallet when it sells."))
		Screens.market(main, "online"), UI.MEADOW))

static func price_chart(main, item: String) -> void:
	var r := await Net.call_rpc("price_history", {"p_item": item, "p_days": 14})
	main.hud.queue_popup(func():
		var v: VBoxContainer = main.hud.popup(tr_("%s price, last 14 days") % tr_(GameData.item_name(item)), UI.item_tex(item))
		var pts: Array = r["data"] if r["code"] == 200 and r["data"] is Array else []
		if pts.is_empty():
			v.add_child(UI.label(tr_("No trades yet. Base price %d coins.") % GameData.item_price(item), 26))
		else:
			var chart := PriceChart.new()
			chart.points = pts.map(func(p): return float(p["avg_price"]))
			chart.base = GameData.item_price(item)
			v.add_child(chart)
			v.add_child(UI.label(tr_("Dashed line = base price %d") % GameData.item_price(item), 22, UI.WOOD_DARK))
		v.add_child(UI.button(tr_("Close"), func(): main.hud.close_popup(v), UI.WOOD_DARK)))

class PriceChart extends Control:
	var points: Array = []
	var base := 1
	func _init() -> void:
		custom_minimum_size = Vector2(520, 220)
	func _draw() -> void:
		var hi: float = maxf(points.max(), base) * 1.15
		var lo: float = minf(points.min(), base) * 0.85
		var to := func(i: int, v: float) -> Vector2:
			var x := 10.0 + (size.x - 20.0) * (float(i) / maxf(1.0, points.size() - 1))
			return Vector2(x, size.y - 10.0 - (size.y - 20.0) * (v - lo) / maxf(1.0, hi - lo))
		draw_dashed_line(to.call(0, base), Vector2(size.x - 10, to.call(0, base).y), UI.WOOD_DARK, 3.0, 10.0)
		var line := PackedVector2Array()
		for i in points.size(): line.append(to.call(i, points[i]))
		if line.size() > 1: draw_polyline(line, UI.MEADOW, 6.0, true)
		for p in line: draw_circle(p, 7.0, UI.RED)

# ------------------------------------------------------------------ offers

static func _offer_row(main, o: Dictionary, incoming: bool, again: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color("#FFF6D8"), 20, 3, UI.WHEAT))
	var v := VBoxContainer.new()
	p.add_child(v)
	var desc := func(items: Dictionary, coins: int) -> String:
		var parts := []
		for k in items: parts.append("%d %s" % [int(items[k]), tr_(GameData.item_name(k))])
		if coins > 0: parts.append("%d coins" % coins)
		return ", ".join(parts) if not parts.is_empty() else tr_("nothing")
	v.add_child(UI.label((tr_("Offer from %s") % o.get("from_name", "?")) if incoming else tr_("Your offer"), 26, UI.RED, 600))
	v.add_child(UI.label(tr_("Gives: %s") % desc.call(o["give_items"], int(o["give_coins"])), 24))
	v.add_child(UI.label(tr_("Wants: %s") % desc.call(o["want_items"], int(o["want_coins"])), 24))
	var h := HBoxContainer.new()
	if incoming:
		h.add_child(UI.button(tr_("Accept"), func():
			# deposit what they want from my farm first (server checks it again)
			var m: GameModel = Game.model
			if _fail(main, m.queue_deposit(o["want_items"], 0)): return
			var mine: Dictionary = (await Net.call_rpc("my_trading"))["data"]
			var need := int(o["want_coins"]) - int(mine.get("wallet", 0))
			if need > 0 and _fail(main, m.queue_deposit({}, need)): return
			if not _fail(main, await Net.trade_call("respond_offer", {"p_offer": int(o["id"]), "p_accept": true})):
				await Net.collect_all()
				main.hud.toast(tr_("Trade complete!"))
			again.call(), UI.MEADOW))
		h.add_child(UI.button(tr_("Decline"), func():
			_fail(main, await Net.trade_call("respond_offer", {"p_offer": int(o["id"]), "p_accept": false}))
			again.call(), UI.WOOD_DARK))
	else:
		h.add_child(UI.button(tr_("Cancel offer"), func():
			_fail(main, await Net.trade_call("cancel_offer", {"p_offer": int(o["id"])}))
			again.call(), UI.WOOD_DARK))
	v.add_child(h)
	return p

static func offer_form(main, friend: Dictionary) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("Trade with %s") % friend["display_name"], 0.85)
	var give_item := OptionButton.new()
	give_item.add_item(tr_("(no item)"))
	give_item.set_item_metadata(0, "")
	for id in m.s["inv"]:
		give_item.add_item("%s (×%d)" % [tr_(GameData.item_name(id)), m.count(id)])
		give_item.set_item_metadata(give_item.item_count - 1, id)
	var want_item := OptionButton.new()
	want_item.add_item(tr_("(no item)"))
	want_item.set_item_metadata(0, "")
	for id in GameData.items():
		want_item.add_item(tr_(GameData.item_name(id)))
		want_item.set_item_metadata(want_item.item_count - 1, id)
	var spin := func(label: String, mx: int) -> SpinBox:
		var sp := SpinBox.new()
		sp.prefix = label
		sp.max_value = mx
		sp.custom_minimum_size.y = UI.MIN_TAP
		return sp
	var give_qty: SpinBox = spin.call(tr_("Qty"), 999)
	var give_coins: SpinBox = spin.call(tr_("Coins"), int(m.s["coins"]))
	var want_qty: SpinBox = spin.call(tr_("Qty"), 999)
	var want_coins: SpinBox = spin.call(tr_("Coins"), 1_000_000)
	for c in [UI.label(tr_("You give"), 28, UI.RED, 600), give_item, give_qty, give_coins, UI.label(tr_("You want"), 28, UI.RED, 600), want_item, want_qty, want_coins]:
		c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, 72)
		body.add_child(c)
	body.add_child(UI.button(tr_("Send offer"), func():
		var gi: String = give_item.get_item_metadata(give_item.selected)
		var wi: String = want_item.get_item_metadata(want_item.selected)
		var give := {gi: int(give_qty.value)} if gi != "" and give_qty.value > 0 else {}
		var want := {wi: int(want_qty.value)} if wi != "" and want_qty.value > 0 else {}
		if give.is_empty() and give_coins.value <= 0:
			main.say_error("Add something to give")
			return
		if _fail(main, m.queue_deposit(give, int(give_coins.value))): return
		if not _fail(main, await Net.trade_call("send_offer", {"p_to": friend["id"], "p_give_items": give, "p_give_coins": int(give_coins.value), "p_want_items": want, "p_want_coins": int(want_coins.value)})):
			main.hud.toast(tr_("Offer sent to %s") % friend["display_name"])
		main.hud.close_sheet(), UI.MEADOW))

# ------------------------------------------------------------------ friends

static func friends(main) -> void:
	var body: VBoxContainer = main.hud.sheet(tr_("Friends"), 0.85)
	if not gate(main, body, "friends"): return
	var me := await Net.call_rpc("my_profile")
	if not is_instance_valid(body): return
	var code: String = str(me["data"].get("friend_code", "?")) if me["data"] is Dictionary else "?"
	var h := HBoxContainer.new()
	var cl := UI.label(tr_("Your friend code: %s") % code, 30, UI.RED, 600)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cl)
	h.add_child(UI.button(tr_("Copy"), func(): DisplayServer.clipboard_set(code); main.hud.toast(tr_("Copied!")), UI.WOOD_DARK))
	body.add_child(h)
	var add := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = tr_("Friend's code")
	edit.max_length = 8
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = UI.MIN_TAP
	add.add_child(edit)
	add.add_child(UI.button(tr_("Add"), func():
		if not _fail(main, await Net.trade_call("add_friend", {"p_code": edit.text})):
			main.hud.toast(tr_("Friend added!"))
			friends(main), UI.MEADOW))
	body.add_child(add)
	var r := await Net.call_rpc("list_friends")
	if not is_instance_valid(body): return
	var list: Array = r["data"] if r["code"] == 200 and r["data"] is Array else []
	if list.is_empty():
		body.add_child(UI.label(tr_("No friends yet. Share your code!"), 24, UI.WOOD_DARK))
	for f in list:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.box(Color.WHITE, 20, 3))
		var v := VBoxContainer.new()
		p.add_child(v)
		v.add_child(UI.label("%s · %s %d" % [f["display_name"], tr_("Level"), int(f["level"])], 28, UI.RED, 600))
		var btns := HFlowContainer.new()
		btns.add_child(UI.button(tr_("Visit"), func(): visit(main, f), UI.MEADOW, UI.icon("farm")))
		btns.add_child(UI.button(tr_("Trade"), func(): offer_form(main, f), UI.SKY, UI.icon("market")))
		btns.add_child(UI.button(tr_("Report"), func(): report(main, f), UI.WOOD_DARK))
		btns.add_child(UI.button(tr_("Remove"), func():
			await Net.trade_call("remove_friend", {"p_friend": f["id"]})
			friends(main), UI.WOOD_DARK))
		v.add_child(btns)
		body.add_child(p)

## Read-only view of a friend's farm; tap a growing crop to water it (once per friend per day).
static func visit(main, f: Dictionary) -> void:
	var r := await Net.call_rpc("visit_farm", {"p_friend": f["id"]})
	if r["code"] != 200 or not r["data"] is Dictionary:
		main.say_error(Net.err(r))
		return
	var snap: Dictionary = r["data"]
	var body: VBoxContainer = main.hud.sheet(tr_("%s's farm (Level %d)") % [f["display_name"], int(snap.get("level", 1))], 0.85)
	if snap.has("avatar") and snap["avatar"] is Dictionary:
		var c := CenterContainer.new()
		c.add_child(Avatar.make(snap["avatar"], 160))
		body.add_child(c)
	body.add_child(UI.label(tr_("Tap a growing crop to water it: it grows 5 minutes faster and you earn a little thank-you."), 22, UI.WOOD_DARK))
	var g := GridContainer.new()
	g.columns = int(snap.get("cols", 4))
	var plots: Array = snap.get("plots", []) if snap.get("plots") is Array else []
	for i in plots.size():
		var crop: String = plots[i].get("crop", "")
		var b := Button.new()
		b.custom_minimum_size = Vector2(100, 100)
		b.icon = UI.tex("res://assets/art/crops/%s_ready.svg" % crop) if crop != "" else UI.tex("res://assets/art/tiles/soil.svg")
		b.expand_icon = true
		b.add_theme_stylebox_override("normal", UI.box(Color("#A8724A"), 12, 3))
		b.disabled = crop == ""
		b.pressed.connect(func():
			var res := await Net.call_rpc("help_friend", {"p_friend": f["id"], "p_plot": i})
			if res["code"] == 200 and res["data"] is Dictionary and res["data"].get("ok", false):
				Game.model.add_xp(int(res["data"]["xp"]))
				Sfx.play("plant")
				main.hud.toast(tr_("Watered! +%d coins in your trade wallet") % int(res["data"]["coins"]))
			else:
				main.say_error(Net.err(res)))
		g.add_child(b)
	body.add_child(g)
	var deco: Array = snap.get("decor", []) if snap.get("decor") is Array else []
	body.add_child(UI.label(tr_("%d buildings · %d decorations") % [(snap.get("buildings", {}) as Dictionary).size() if snap.get("buildings") is Dictionary else 0, deco.size()], 22))

static func report(main, f: Dictionary) -> void:
	var body: VBoxContainer = main.hud.sheet(tr_("Report %s") % f["display_name"], 0.6)
	body.add_child(UI.label(tr_("Tell us what's wrong. Reports are private and reviewed by a moderator."), 24))
	for reason in ["Offensive name", "Scam or unfair trade", "Harassment", "Other"]:
		body.add_child(UI.button(tr_(reason), func():
			if not _fail(main, await Net.trade_call("report_player", {"p_player": f["id"], "p_reason": reason})):
				main.hud.toast(tr_("Thanks. We'll take a look."))
			main.hud.close_sheet(), UI.WOOD_DARK))
