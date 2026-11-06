## Builders for every sheet/popup. Each takes `main` (main.gd) for hud + helpers.
## Screens read the model and call its methods; they never change state directly.
class_name Screens
extends RefCounted

const LOCK := "<lock>"
const ERRORS := {
	"no_coins": "Not enough coins", "no_gems": "Not enough gems", "locked": "Unlocks at a higher level",
	"silo_full": "Silo is full: upgrade it in the Shop", "barn_full": "Barn is full: upgrade it in the Shop",
	"plot_busy": "Something is already growing here", "not_ready": "Not ready yet",
	"missing_items": "You don't have the ingredients", "queue_full": "All slots are busy",
	"offline": "Connect to the internet to trade", "not_owned": "Build it first in the Shop",
	"sell_cap": "The stall can't take more of that today", "max_level": "Already at the maximum",
	"price_out_of_range": "That price is outside the allowed range", "listing_slots_full": "All listing slots are in use",
	"not_enough_items": "Not enough items in your trade storage", "not_enough_coins": "Not enough coins in your trade wallet",
	"already_sold": "Someone was quicker: that listing just sold", "expired": "That listing has expired",
	"own_listing": "That's your own listing", "deposit_cap": "Daily trading limit reached for that item",
	"rate_limited": "Slow down a little and try again", "unknown_code": "No farmer has that code",
	"own_code": "That's your own code", "not_friends": "You need to be friends first", "already_helped": "You already helped this friend today",
	"help_limit": "You've helped 5 friends today: come back tomorrow", "not_pending": "That offer was already answered",
	"empty_offer": "Add something to give", "housing_full": "No room: upgrade the building",
	"no_feed": "You need Animal Feed: make it at the Windmill", "not_hungry": "Already fed",
	"pet_cooldown": "They loved that! Pet again in a little while", "banned": "This account can't trade", "server_error": "The server had a hiccup, try again",
}

static func open(main, screen: String) -> void:
	match screen:
		"barn": barn(main)
		"settings": settings(main)
		"shop": shop(main)
		"market": market(main)
		"orders": deliveries(main)
		"friends": TradeScreens.friends(main)
		"gift": daily(main, true)
		"trophy": achievements(main)
		"event": events(main)
		"inn": main.show_farm() if main.inn.visible else main.show_inn()
		_: main.hud.toast(tr_("Coming soon"))

static func open_building(main, id: String) -> void:
	var b: Dictionary = GameData.buildings().get(id, {})
	if id == "inn": open(main, "inn")
	elif b.get("kind", "") == "workshop": workshop(main, id)
	elif b.get("kind", "") == "housing": animals(main, id)
	else: main.hud.toast(tr_(b.get("name", id)))

static func tr_(s: String) -> String:
	return TranslationServer.translate(s)

## A row: icon, title + subtitle, and an action button on the right.
static func row(tex: Texture2D, title: String, sub: String, btn_text: String, on_press: Callable, enabled := true, color := UI.RED) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color.WHITE if enabled else Color("#EFE6D6"), 20, 3))
	var h := HBoxContainer.new()
	p.add_child(h)
	h.add_child(UI.icon_rect(tex, 80))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.add_child(UI.label(title, 30))
	if sub != "":
		v.add_child(UI.label(sub, 22, UI.WOOD_DARK, 600))
	h.add_child(v)
	if btn_text != "":
		var b := UI.button("" if btn_text == LOCK else btn_text, on_press, color, UI.icon("lock") if btn_text == LOCK else null)
		b.disabled = not enabled
		b.custom_minimum_size.x = 150
		h.add_child(b)
	return p

# ------------------------------------------------------------------ farm

static func seed_picker(main, plot: int) -> void:
	var body: VBoxContainer = main.hud.sheet(tr_("Plant a seed"))
	var m: GameModel = Game.model
	for cid in GameData.crops():
		var c: Dictionary = GameData.crops()[cid]
		var ok := m.is_unlocked(c["unlock_level"])
		var sub := ("%s · %d coins · sells %d" % [UI.fmt_time(c["grow_seconds"]), int(c["seed_cost"]), GameData.item_price(cid)]) if ok \
			else tr_("Unlocks at level %d") % int(c["unlock_level"])
		body.add_child(row(UI.item_tex(cid), tr_(GameData.item_name(cid)), sub, tr_("Plant") if ok else LOCK, func():
			var err := m.plant(plot, cid, Game.now())
			main.hud.close_sheet()
			if err != "":
				main.say_error(err)
				return
			Sfx.play("plant")
			main.start_planting(cid), ok))

static func growing_plot(main, i: int) -> void:
	var m: GameModel = Game.model
	var p: Dictionary = m.s["plots"][i]
	var rem := m.plot_remaining(i, Game.now())
	var v: VBoxContainer = main.hud.popup(tr_(GameData.item_name(p["crop"])), UI.item_tex(p["crop"]))
	v.add_child(UI.label(tr_("Ready in %s") % UI.fmt_time(rem), 30))
	var cost := GameModel.speedup_cost(rem)
	v.add_child(UI.button(tr_("Finish now · %d gems") % cost, func():
		var err := m.speed_up_plot(i, Game.now())
		main.hud.close_popup(v)
		if err != "": main.say_error(err), UI.SKY, UI.icon("gem")))
	v.add_child(UI.button(tr_("Close"), func(): main.hud.close_popup(v), UI.WOOD_DARK))

# ------------------------------------------------------------------ barn

static func barn(main) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("Barn & Silo"))
	for kind in ["silo", "barn"]:
		body.add_child(UI.label("%s %d / %d" % [tr_(kind.capitalize()), m.storage_used(kind), m.storage_cap(kind)], 30, UI.RED, 600))
		var g := GridContainer.new()
		g.columns = 4
		var ids: Array = m.s["inv"].keys().filter(func(id): return GameData.storage_kind(id) == kind)
		ids.sort()
		for id in ids:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 0)
			cell.add_child(UI.icon_rect(UI.item_tex(id), 96))
			var l := UI.label("%s\n×%d" % [tr_(GameData.item_name(id)), m.count(id)], 20)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size.x = 150
			cell.add_child(l)
			g.add_child(cell)
		if ids.is_empty():
			body.add_child(UI.label(tr_("Empty"), 24, UI.WOOD_DARK))
		body.add_child(g)

# ------------------------------------------------------------------ welcome back

static func welcome_back(main, w: Dictionary) -> void:
	main.hud.queue_popup(func():
		var v: VBoxContainer = main.hud.popup(tr_("Welcome back!"), UI.tex("res://assets/art/characters/innkeeper.svg"))
		v.add_child(UI.label(tr_("You were away %s. While you were gone:") % UI.fmt_time(w["away"]), 28))
		var lines := {
			"crops": "%d crops ready to harvest", "jobs": "%d workshop goods finished",
			"animals": "%d animals have goods for you", "guests": "%d guests are waiting at the inn",
			"room_coins": "%d coins earned by guest rooms",
		}
		var any := false
		for k in lines:
			if int(w.get(k, 0)) > 0:
				v.add_child(UI.label("• " + tr_(lines[k]) % int(w[k]), 26, UI.MEADOW))
				any = true
		if not any:
			v.add_child(UI.label(tr_("• The farm rested peacefully"), 26))
		v.add_child(UI.button(tr_("Let's go!"), func(): main.hud.close_popup(v), UI.MEADOW)))

# ------------------------------------------------------------------ dialogue

## Shows character lines one after another as popups ({speaker, line} dicts).
static func talk(main, lines: Array) -> void:
	for l in lines:
		main.hud.queue_popup(func():
			var c: Dictionary = GameData.characters()[l["speaker"]]
			var v: VBoxContainer = main.hud.popup(c["name"])
			v.add_child(UI.label(tr_(c["role"]), 24, UI.WOOD_DARK, 600))
			v.move_child(v.get_child(v.get_child_count() - 1), 0)
			var por := Portrait.make(l["speaker"], 200)
			v.add_child(por)
			v.move_child(por, 0)
			v.add_child(UI.label(Dialogue.text(l["line"], Game.model.s["name"]), 28))
			v.add_child(UI.button(tr_("Continue"), func(): main.hud.close_popup(v), UI.MEADOW)))

# ------------------------------------------------------------------ settings, avatar, cast

static func settings(main) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("Settings"), 0.85)
	body.add_child(UI.label(tr_("Sound"), 32, UI.RED, 600))
	var sfx := CheckButton.new()
	sfx.text = tr_("Sound effects")
	sfx.button_pressed = Sfx.sfx_on
	sfx.toggled.connect(func(on): Sfx.set_audio(on, Sfx.music_on))
	body.add_child(sfx)
	var mus := CheckButton.new()
	mus.text = tr_("Music")
	mus.button_pressed = Sfx.music_on
	mus.toggled.connect(func(on): Sfx.set_audio(Sfx.sfx_on, on))
	body.add_child(mus)
	account_section(main, body)
	body.add_child(UI.button(tr_("My Farmer"), func(): avatar_editor(main), UI.MEADOW))
	body.add_child(UI.button(tr_("Villagers"), func(): cast(main), UI.WOOD_DARK))
	if not m.tutorial_step().is_empty():
		body.add_child(UI.button(tr_("Skip tutorial"), func(): m.skip_tutorial(); main.hud.close_sheet(), UI.WOOD_DARK))
	body.add_child(UI.label(tr_("HarvestInn v%s · Credits in CREDITS.md") % ProjectSettings.get_setting("application/config/version"), 20, UI.WOOD_DARK))

static func avatar_editor(main) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("My Farmer"), 0.9)
	var a: Dictionary = m.s["avatar"]
	var preview := CenterContainer.new()
	preview.add_child(Avatar.make(a, 260))
	body.add_child(preview)
	var name_row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = m.s["name"]
	name_edit.placeholder_text = tr_("Your name")
	name_edit.max_length = 16
	name_edit.custom_minimum_size.y = UI.MIN_TAP
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	name_row.add_child(UI.button(tr_("Save"), func():
		var err := m.set_player_name(name_edit.text)
		if err == "name_short": main.say_error("Name is too short")
		elif err == "name_blocked": main.say_error("Please choose a kinder name")
		else:
			Net.call_rpc("set_display_name", {"p_name": m.s["name"]})
			main.hud.toast(tr_("Nice to meet you, %s!") % m.s["name"]), UI.MEADOW))
	body.add_child(name_row)
	var redo := func(): avatar_editor(main)
	_choice_row(body, tr_("Skin"), Avatar.SKINS.size(), func(i): return Color(Avatar.SKINS[i]), func(i): m.set_avatar("skin", i); redo.call())
	_choice_row(body, tr_("Hair colour"), Avatar.HAIR_COLORS.size(), func(i): return Color(Avatar.HAIR_COLORS[i]), func(i): m.set_avatar("hair_color", i); redo.call())
	var styles := HBoxContainer.new()
	for st in Avatar.HAIR_STYLES:
		styles.add_child(UI.button(tr_(st.capitalize()), func(): m.set_avatar("hair", st); redo.call(), UI.MEADOW if a["hair"] == st else UI.WOOD_DARK))
	body.add_child(styles)
	for slot in ["outfit", "hat"]:
		body.add_child(UI.label(tr_(slot.capitalize()), 28, UI.RED, 600))
		var g := GridContainer.new()
		g.columns = 2
		for cid in GameData.cosmetics():
			var c: Dictionary = GameData.cosmetics()[cid]
			if c["slot"] != slot: continue
			var owned := m.owns(cid)
			var b := UI.button(tr_(c["name"]), func():
				if m.set_avatar(slot, cid) != "": main.say_error("Buy it in the Shop first")
				else: redo.call(), UI.MEADOW if a[slot] == cid else (UI.WOOD_DARK if owned else Color("#B8A89A")))
			b.add_theme_font_size_override("font_size", 22)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not owned: b.icon = UI.icon("lock")
			g.add_child(b)
		body.add_child(g)

static func _choice_row(body: VBoxContainer, title: String, n: int, color_of: Callable, pick: Callable) -> void:
	body.add_child(UI.label(title, 28, UI.RED, 600))
	var h := HBoxContainer.new()
	for i in n:
		var b := UI.button("", func(): pick.call(i), color_of.call(i))
		h.add_child(b)
	body.add_child(h)

static func cast(main) -> void:
	var body: VBoxContainer = main.hud.sheet(tr_("Villagers & Guests"), 0.9)
	for cid in GameData.characters():
		var c: Dictionary = GameData.characters()[cid]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.box(Color.WHITE, 20, 3))
		var h := HBoxContainer.new()
		p.add_child(h)
		h.add_child(Portrait.make(cid, 120))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		v.add_child(UI.label("%s · %s" % [c["name"], tr_(c["role"])], 26, UI.RED, 600))
		v.add_child(UI.label(tr_(c["backstory"]), 22))
		v.add_child(UI.label(tr_(c["personality"]), 20, UI.WOOD_DARK))
		h.add_child(v)
		body.add_child(p)

# ------------------------------------------------------------------ workshops

static func workshop(main, bid: String) -> void:
	var m: GameModel = Game.model
	var b: Dictionary = GameData.buildings()[bid]
	var body: VBoxContainer = main.hud.sheet("%s · %s %d" % [tr_(b["name"]), tr_("Lv"), m.building_level(bid) + 1], 0.85)
	var redo := func(): workshop(main, bid)
	var levels: Array = b["levels"]
	var next := m.building_level(bid) + 1
	if next < levels.size():
		body.add_child(UI.button(tr_("Upgrade to %d slots · %d coins") % [int(levels[next]["slots"]), int(levels[next]["cost"])], func():
			var err := m.upgrade_building(bid)
			if err != "": main.say_error(err)
			else: Sfx.play("build"); redo.call(), UI.WOOD_DARK, UI.icon("coin")))
	var qbox := VBoxContainer.new()
	body.add_child(qbox)
	var fill := func():
		for c in qbox.get_children(): c.queue_free()
		_queue_rows(main, qbox, bid, redo)
	fill.call()
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(fill)
	qbox.add_child.call_deferred(t)
	qbox.set_meta("timer", t)
	body.add_child(UI.label(tr_("Recipes"), 32, UI.RED, 600))
	for rid in GameData.recipes_for(bid):
		var r: Dictionary = GameData.recipes()[rid]
		var out_id: String = r["outputs"].keys()[0]
		var ok := m.is_unlocked(r["unlock_level"])
		var parts := []
		for i in r["inputs"]:
			parts.append("%s %d/%d" % [tr_(GameData.item_name(i)), m.count(i), int(r["inputs"][i])])
		var sub := ("%s · %s" % [", ".join(parts), UI.fmt_time(r["seconds"])]) if ok else tr_("Unlocks at level %d") % int(r["unlock_level"])
		body.add_child(row(UI.item_tex(out_id), "%s ×%d · %d" % [tr_(GameData.item_name(out_id)), int(r["outputs"][out_id]), GameData.item_price(out_id)], sub,
			tr_("Make") if ok else LOCK, func():
				var err := m.queue_recipe(bid, rid, Game.now())
				if err != "": main.say_error(err)
				else: Sfx.play("craft"); redo.call(), ok and m.has_items(r["inputs"])))

static func _queue_rows(main, box: VBoxContainer, bid: String, redo: Callable) -> void:
	var m: GameModel = Game.model
	var now := Game.now()
	var q: Array = m.s["buildings"][bid]["queue"]
	box.add_child(UI.label(tr_("Working: %d / %d slots") % [q.size(), m.slots(bid)], 26, UI.WOOD_DARK, 600))
	var first_running := true
	for j in q:
		var r: Dictionary = GameData.recipes()[j["recipe"]]
		var out_id: String = r["outputs"].keys()[0]
		var done := float(j["end"]) <= now
		var h := HBoxContainer.new()
		h.add_child(UI.icon_rect(UI.item_tex(out_id), 64))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 28)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var running := float(j["start"]) <= now
		bar.value = 100.0 if done else (100.0 * (now - float(j["start"])) / (float(j["end"]) - float(j["start"])) if running else 0.0)
		h.add_child(bar)
		if done:
			h.add_child(UI.button(tr_("Collect"), func():
				var err := m.collect_building(bid, Game.now())
				if err != "": main.say_error(err)
				else:
					Sfx.play("collect")
					main.hud.fly(UI.item_tex(out_id), main.hud.root.get_viewport_rect().size / 2, "barn")
					redo.call(), UI.MEADOW))
		elif first_running:
			first_running = false
			h.add_child(UI.label(UI.fmt_time(float(j["end"]) - now), 24, UI.INK, 700, false))
			h.add_child(UI.button("%d" % GameModel.speedup_cost(float(j["end"]) - now), func():
				var err := m.speed_up_job(bid, Game.now())
				if err != "": main.say_error(err)
				else: redo.call(), UI.SKY, UI.icon("gem")))
		else:
			h.add_child(UI.label(tr_("Waiting"), 24, UI.WOOD_DARK, 700, false))
		box.add_child(h)

# ------------------------------------------------------------------ shop

static func shop(main, tab := "buildings") -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("Shop"), 0.85)
	var tabs := HBoxContainer.new()
	for t in [["buildings", "Buildings"], ["farm", "Farm"], ["style", "Style"]]:
		var b := UI.button(tr_(t[1]), func(): shop(main, t[0]), UI.MEADOW if t[0] == tab else UI.WOOD_DARK)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	body.add_child(tabs)
	if tab == "buildings":
		for bid in GameData.buildings():
			var b: Dictionary = GameData.buildings()[bid]
			if bid == "inn" or b.get("internal", false): continue
			var owned := m.owns_building(bid)
			var ok := m.is_unlocked(b["unlock_level"]) and not owned
			var sub := tr_("Owned") if owned else (("%d coins" % int(b["levels"][0]["cost"])) if m.is_unlocked(b["unlock_level"]) else tr_("Unlocks at level %d") % int(b["unlock_level"]))
			body.add_child(row(UI.tex("res://assets/art/buildings/%s.svg" % bid), tr_(b["name"]), sub, tr_("Build") if not owned else tr_("Owned"), func():
				var err := m.build(bid)
				if err != "": main.say_error(err)
				else:
					Sfx.play("build")
					main.hud.close_sheet()
					main.hud.toast(tr_("%s built! Long-press to move it.") % tr_(b["name"])), ok, UI.MEADOW))
	else:
		shop_extra(main, body, tab)

static func shop_extra(main, body: VBoxContainer, tab: String) -> void:
	var m: GameModel = Game.model
	var again := func(): shop(main, tab)
	var act := func(err: String):
		if err != "": main.say_error(err)
		else: Sfx.play("coins"); again.call()
	if tab == "farm":
		var ex := m.next_land()
		if not ex.is_empty():
			var ok := m.is_unlocked(ex["unlock_level"])
			body.add_child(row(UI.icon("farm"), tr_("Land expansion → %d×%d plots") % [int(ex["cols"]), int(ex["rows"])],
				tr_("%d coins") % int(ex["cost"]) if ok else tr_("Unlocks at level %d") % int(ex["unlock_level"]),
				tr_("Buy") if ok else LOCK, func(): act.call(m.buy_land()), ok, UI.MEADOW))
		for kind in ["silo", "barn"]:
			var levels: Array = GameData.economy()["storage"][kind]
			var next := int(m.s["storage"][kind]) + 1
			if next < levels.size():
				body.add_child(row(UI.icon("barn"), tr_("%s: %d → %d") % [tr_(kind.capitalize()), m.storage_cap(kind), int(levels[next]["capacity"])],
					tr_("%d coins") % int(levels[next]["cost"]), tr_("Upgrade"), func(): act.call(m.upgrade_storage(kind)), true, UI.MEADOW))
	for cid in GameData.cosmetics():
		var c: Dictionary = GameData.cosmetics()[cid]
		var slot: String = c["slot"]
		if (tab == "farm") != (slot == "decor"): continue
		var ok := m.is_unlocked(c["unlock_level"])
		var owned := slot != "decor" and m.owns(cid)
		var price := (tr_("%d gems") % int(c["cost_gems"])) if c.has("cost_gems") else (tr_("%d coins") % int(c["cost"]))
		var sub := tr_("Owned") if owned else (price if ok else tr_("Unlocks at level %d") % int(c["unlock_level"]))
		if slot == "furniture": sub += " · +%d %s" % [int(c["reputation"]), tr_("reputation")]
		var tex: Texture2D = UI.tex("res://assets/art/decor/%s.svg" % cid) if slot == "decor" else (UI.tex("res://assets/art/avatar/hat_%s.svg" % cid) if slot == "hat" else UI.item_tex("blanket" if slot == "furniture" else "sweater"))
		body.add_child(row(tex, tr_(c["name"]), sub, tr_("Buy") if ok and not owned else (LOCK if not ok else tr_("Owned")), func():
			var t: Vector2i = main.farm.free_tile()
			act.call(m.buy_cosmetic(cid, t.x, t.y)), ok and not owned, UI.MEADOW))

# ------------------------------------------------------------------ market + deliveries

static func market(main, tab := "village") -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("Market"), 0.85)
	var tabs := HBoxContainer.new()
	for t in [["village", "Village stall"], ["online", "Online market"]]:
		var b := UI.button(tr_(t[1]), func(): market(main, t[0]), UI.MEADOW if t[0] == tab else UI.WOOD_DARK)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	body.add_child(tabs)
	if tab == "online":
		online_market(main, body)
		return
	var head := HBoxContainer.new()
	head.add_child(Portrait.make("merchant", 110))
	head.add_child(UI.label(Dialogue.text(GameData.characters()["merchant"]["lines"]["greet"].pick_random(), m.s["name"]), 24))
	head.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(head)
	var now := Game.now()
	var ids: Array = m.s["inv"].keys()
	ids.sort()
	if ids.is_empty():
		body.add_child(UI.label(tr_("Nothing to sell yet. Harvest something!"), 26))
	for id in ids:
		var price := GameModel.market_price(id, now)
		var pct := int(round((GameModel.demand(id, GameModel.day_of(now)) - 1.0) * 100))
		var trend := ("+%d%%" % pct) if pct >= 0 else ("%d%%" % pct)
		var n := m.count(id)
		var p := row(UI.item_tex(id), "%s ×%d" % [tr_(GameData.item_name(id)), n], tr_("%d coins each · today %s") % [price, trend], tr_("Sell 1"),
			func(): _sell(main, id, 1, tab), true, UI.MEADOW)
		var all := UI.button(tr_("All"), func(): _sell(main, id, mini(m.count(id), 200 - m.sold_today(id, Game.now())), tab), UI.WOOD_DARK)
		p.get_child(0).add_child(all)
		body.add_child(p)

static func _sell(main, id: String, qty: int, tab: String) -> void:
	var err: String = Game.model.sell(id, qty, Game.now())
	if err != "":
		main.say_error(err)
		return
	Sfx.play("coins")
	main.hud.fly(UI.icon("coin"), main.hud.root.get_viewport_rect().size / 2, "coins")
	market(main, tab)

static func online_market(main, body: VBoxContainer) -> void:
	TradeScreens.market(main, body)

static func deliveries(main) -> void:
	var m: GameModel = Game.model
	if not m.is_unlocked(GameData.economy()["features"]["delivery_board"]):
		main.say_error("locked")
		return
	var body: VBoxContainer = main.hud.sheet(tr_("Village orders"), 0.8)
	var now := Game.now()
	m.refresh_deliveries(now)
	for i in m.s["deliveries"].size():
		var d: Dictionary = m.s["deliveries"][i]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.box(Color.WHITE, 20, 3))
		var v := VBoxContainer.new()
		p.add_child(v)
		if d["items"].is_empty():
			v.add_child(UI.label(tr_("New order in %s") % UI.fmt_time(float(d["ready_at"]) - now), 26, UI.WOOD_DARK))
			body.add_child(p)
			continue
		var flow := HFlowContainer.new()
		for it in d["items"]:
			var have := m.count(it)
			var need := int(d["items"][it])
			var h := HBoxContainer.new()
			h.add_child(UI.icon_rect(UI.item_tex(it), 64))
			h.add_child(UI.label("%d/%d" % [mini(have, need), need], 26, UI.MEADOW if have >= need else UI.RED, 700, false))
			flow.add_child(h)
		v.add_child(flow)
		var r := HBoxContainer.new()
		var go := UI.button(tr_("Deliver · %d coins · %d XP") % [int(d["coins"]), int(d["xp"])], func():
			var err := m.fulfill_delivery(i, Game.now())
			if err != "": main.say_error(err)
			else:
				Sfx.play("coins")
				main.hud.fly(UI.icon("coin"), main.hud.root.get_viewport_rect().size / 2, "coins")
				deliveries(main), UI.MEADOW)
		go.disabled = not m.has_items(d["items"])
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(go)
		r.add_child(UI.button(tr_("Skip"), func(): m.skip_delivery(i, Game.now()); deliveries(main), UI.WOOD_DARK))
		v.add_child(r)
		body.add_child(p)

# ------------------------------------------------------------------ account + cloud

static func account_section(main, body: VBoxContainer) -> void:
	body.add_child(UI.label(tr_("Account"), 32, UI.RED, 600))
	if not Net.configured():
		body.add_child(UI.label(tr_("Offline build: online features are not set up (see backend/README.md)."), 22, UI.WOOD_DARK))
		return
	if not Net.online:
		body.add_child(UI.label(tr_("You're offline. Your farm keeps working; we'll sync when you're back."), 22, UI.WOOD_DARK))
		body.add_child(UI.button(tr_("Try to connect"), func():
			await Net.connect_now()
			settings(main), UI.SKY))
		return
	var guest := Net.is_guest()
	body.add_child(UI.label(tr_("Signed in as a guest. Link an account so you never lose your farm.") if guest else tr_("Your account is linked. Progress is saved to the cloud."), 22))
	if guest:
		var h := HBoxContainer.new()
		for prov in [["apple", "Sign in with Apple"], ["google", "Sign in with Google"]]:
			var b := UI.button(tr_(prov[1]), func():
				if await Net.link_identity(prov[0]) != "": main.say_error("Could not reach the sign-in page")
				else: main.hud.toast(tr_("Finish signing in, then come back and tap Check")), UI.INK if prov[0] == "apple" else UI.SKY)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 22)
			h.add_child(b)
		body.add_child(h)
		body.add_child(UI.button(tr_("Check sign-in"), func():
			await Net.refresh_user()
			settings(main), UI.WOOD_DARK))
	body.add_child(UI.button(tr_("Sync now"), func():
		await Net.sync()
		main.hud.toast(tr_("Synced")), UI.MEADOW))

static func cloud_conflict(main, server: Dictionary) -> void:
	main.hud.queue_popup(func():
		var v: VBoxContainer = main.hud.popup(tr_("Two saves found"), UI.icon("settings"))
		v.add_child(UI.label(tr_("This farm was played on another device. Which progress do you want to keep?"), 26))
		v.add_child(UI.button(tr_("This device: %s") % CloudSync.summary(Game.model.s), func():
			main.hud.close_popup(v)
			Net.keep_local(server), UI.MEADOW))
		v.add_child(UI.button(tr_("Cloud: %s") % CloudSync.summary(server.get("data", {})), func():
			main.hud.close_popup(v)
			Net.adopt(server), UI.SKY)))

# ------------------------------------------------------------------ animals

static func animals(main, h: String) -> void:
	var m: GameModel = Game.model
	var b: Dictionary = GameData.buildings()[h]
	var kind: String = b["animal"]
	var info: Dictionary = GameData.animals()[kind]
	var now := Game.now()
	var body: VBoxContainer = main.hud.sheet("%s · %d/%d" % [tr_(b["name"]), m.s["animals"][h].size(), m.housing_capacity(h)], 0.85)
	var redo := func(): animals(main, h)
	var act := func(err: String, sfx: String):
		if err != "": main.say_error(err)
		else: Sfx.play(sfx); redo.call()
	var vet := HBoxContainer.new()
	vet.add_child(Portrait.make("vet", 100))
	var feed_name := ", ".join(info["feed"].keys().map(func(k): return "%d %s" % [int(info["feed"][k]), tr_(GameData.item_name(k))]))
	var tip := UI.label(tr_("Each %s eats %s and gives goods every %s. Happy animals (75+) give a bonus!") % [tr_(info["name"]), feed_name, UI.fmt_time(info["cycle_seconds"])], 22)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vet.add_child(tip)
	body.add_child(vet)
	var top := HBoxContainer.new()
	var tend := UI.button(tr_("Tend all"), func():
		var r := m.tend_all(h, Game.now())
		if r["collected"] + r["fed"] == 0 and r["error"] != "": main.say_error(r["error"])
		else:
			Sfx.play("collect")
			main.hud.toast(tr_("Collected %d · fed %d") % [r["collected"], r["fed"]])
			redo.call(), UI.MEADOW)
	tend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tend)
	top.add_child(UI.label(tr_("Feed: %d") % m.count("animal_feed"), 24, UI.WOOD_DARK, 700, false))
	body.add_child(top)
	for i in m.s["animals"][h].size():
		var st := m.animal_state(h, i, now)
		var hap := m.happiness(h, i, now)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.box(Color.WHITE, 20, 3))
		var line := HBoxContainer.new()
		p.add_child(line)
		var pic := UI.icon_rect(UI.tex("res://assets/art/animals/%s.svg" % kind), 96)
		line.add_child(pic)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		var status: String = {"hungry": tr_("Hungry"), "producing": tr_("Making goods: %s") % UI.fmt_time(float(m.s["animals"][h][i]["cycle_end"]) - now), "ready": tr_("Goods ready!")}[st]
		v.add_child(UI.label("%s %d · %s" % [tr_(info["name"]), i + 1, status], 24, UI.RED if st == "ready" else UI.INK, 600))
		var bar := ProgressBar.new()
		bar.value = hap
		bar.show_percentage = false
		bar.custom_minimum_size.y = 22
		bar.tooltip_text = tr_("Happiness %d") % hap
		v.add_child(bar)
		v.add_child(UI.label(tr_("Happiness %d%s") % [hap, tr_(" · happy bonus!") if hap >= 75 else ""], 20, UI.WOOD_DARK, 700, false))
		line.add_child(v)
		var btns := VBoxContainer.new()
		if st == "ready":
			btns.add_child(UI.button(tr_("Collect"), func(): act.call(m.collect_animal(h, i, Game.now()), "collect"), UI.MEADOW))
		elif st == "hungry":
			btns.add_child(UI.button(tr_("Feed"), func(): act.call(m.feed_animal(h, i, Game.now()), "plant"), UI.WHEAT))
		btns.add_child(UI.button(tr_("Pet"), func():
			act.call(m.pet_animal(h, i, Game.now()), "pet")
			main.hud.toast(tr_("So happy!")), UI.SKY, UI.icon("heart_hand")))
		line.add_child(btns)
		body.add_child(p)
	var ok := m.is_unlocked(info["unlock_level"])
	if m.s["animals"][h].size() < m.housing_capacity(h):
		body.add_child(row(UI.tex("res://assets/art/animals/%s.svg" % kind), tr_("Adopt a %s") % tr_(info["name"]), tr_("%d coins") % int(info["cost"]) if ok else tr_("Unlocks at level %d") % int(info["unlock_level"]),
			tr_("Adopt") if ok else LOCK, func(): act.call(m.buy_animal(h, Game.now()), "pet"), ok, UI.MEADOW))
	var levels: Array = b["levels"]
	var next := m.building_level(h) + 1
	if next < levels.size():
		body.add_child(UI.button(tr_("Bigger home: %d animals · %d coins") % [int(levels[next]["capacity"]), int(levels[next]["cost"])], func(): act.call(m.upgrade_building(h), "build"), UI.WOOD_DARK, UI.icon("coin")))

# ------------------------------------------------------------------ daily, achievements, events

static func _reward_text(r: Dictionary) -> String:
	var parts := []
	if r.has("coins"): parts.append("%d coins" % int(r["coins"]))
	if r.has("gems"): parts.append("%d gems" % int(r["gems"]))
	for it in r.get("items", {}): parts.append("%d %s" % [int(r["items"][it]), tr_(GameData.item_name(it))])
	if r.has("decor"): parts.append(tr_(GameData.cosmetics()[r["decor"]]["name"]))
	return ", ".join(parts)

static func daily(main, from_button := false) -> void:
	var m: GameModel = Game.model
	var today := m.daily_index(Game.now())
	if today < 0:
		if from_button: main.hud.toast(tr_("Come back tomorrow for your next gift!"))
		return
	main.hud.queue_popup(func():
		var v: VBoxContainer = main.hud.popup(tr_("Daily gift: day %d") % (today + 1), UI.icon("gift"))
		var g := GridContainer.new()
		g.columns = 4
		var rewards := GameData.daily_rewards()
		for i in rewards.size():
			var cell := PanelContainer.new()
			cell.add_theme_stylebox_override("panel", UI.box(UI.MEADOW.lightened(0.5) if i < today else (UI.WHEAT if i == today else Color.WHITE), 14, 3))
			cell.add_child(UI.label(tr_("Day %d\n%s") % [i + 1, _reward_text(rewards[i])], 18))
			cell.custom_minimum_size = Vector2(130, 110)
			g.add_child(cell)
		v.add_child(g)
		v.add_child(UI.button(tr_("Claim %s") % _reward_text(rewards[today]), func():
			m.claim_daily(Game.now())
			Sfx.play("coins")
			main.hud.fly(UI.icon("gift"), main.hud.root.get_viewport_rect().size / 2, "coins")
			main.hud.close_popup(v), UI.MEADOW)))

static func achievements(main) -> void:
	var m: GameModel = Game.model
	var body: VBoxContainer = main.hud.sheet(tr_("Achievements"), 0.85)
	for id in GameData.achievements():
		var a: Dictionary = GameData.achievements()[id]
		var have := mini(int(m.s["stats"].get(a["stat"], 0)), int(a["goal"]))
		var claimed: bool = id in m.s["achievements"]
		var done := m.achievement_done(id)
		body.add_child(row(UI.icon("trophy"), tr_(a["name"]), "%s · %d/%d · %s" % [tr_(a["desc"]), have, int(a["goal"]), _reward_text(a["reward"])],
			tr_("Claimed") if claimed else tr_("Claim"), func():
				if m.claim_achievement(id) == "": Sfx.play("coins")
				achievements(main), done and not claimed, UI.MEADOW))

static func events(main) -> void:
	var m: GameModel = Game.model
	var now := Game.now()
	var body: VBoxContainer = main.hud.sheet(tr_("Seasonal events"), 0.85)
	var list := GameModel.active_events(now)
	if list.is_empty():
		body.add_child(UI.label(tr_("No event right now. Check back soon!"), 26))
	for e in list:
		var head := HBoxContainer.new()
		head.add_child(Portrait.make(e["host"], 110))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(tr_(e["name"]), 30, UI.RED, 600))
		v.add_child(UI.label(tr_(e["text"]), 22))
		v.add_child(UI.label(tr_("Until %s · featured items sell for ×%.1f at the stall") % [e["end"], float(e["sell_mult"])], 20, UI.WOOD_DARK))
		head.add_child(v)
		body.add_child(head)
		var p := m.event_progress(e["id"], now)
		var goal: Dictionary = e["goal"]["items"]
		for it in goal:
			var given := int(p["given"].get(it, 0))
			body.add_child(row(UI.item_tex(it), "%s %d/%d" % [tr_(GameData.item_name(it)), given, int(goal[it])], tr_("You have %d") % m.count(it), tr_("Give"),
				func():
					var err := m.contribute_event(e["id"], it, m.count(it), Game.now())
					if err != "": main.say_error(err)
					else: Sfx.play("collect")
					events(main), given < int(goal[it]) and m.count(it) > 0, UI.MEADOW))
		body.add_child(UI.button(tr_("Claim reward: %s") % _reward_text(e["reward"]) if not p["claimed"] else tr_("Reward claimed"), func():
			var err := m.claim_event(e["id"], Game.now())
			if err != "": main.say_error(err)
			else: Sfx.play("level_up"); events(main), UI.WHEAT))
