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
}

static func open(main, screen: String) -> void:
	match screen:
		"barn": barn(main)
		"settings": settings(main)
		"shop": shop(main)
		"inn": main.show_farm() if main.inn.visible else main.show_inn()
		_: main.hud.toast(tr_("Coming soon"))

static func open_building(main, id: String) -> void:
	var b: Dictionary = GameData.buildings().get(id, {})
	if id == "inn": open(main, "inn")
	elif b.get("kind", "") == "workshop": workshop(main, id)
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
		else: main.hud.toast(tr_("Nice to meet you, %s!") % m.s["name"]), UI.MEADOW))
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

## Farm upgrades + cosmetics tabs (filled in by the market/shop milestone).
static func shop_extra(_main, body: VBoxContainer, _tab: String) -> void:
	body.add_child(UI.label(tr_("Coming soon"), 26))
