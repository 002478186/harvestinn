## Builders for every sheet/popup. Each takes `main` (main.gd) for hud + helpers.
## Screens read the model and call its methods; they never change state directly.
class_name Screens
extends RefCounted

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
		_: main.hud.toast(tr_("Coming soon"))

static func open_building(main, id: String) -> void:
	main.hud.toast(GameData.buildings().get(id, {}).get("name", id))

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
		var b := UI.button(btn_text, on_press, color)
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
		body.add_child(row(UI.item_tex(cid), tr_(GameData.item_name(cid)), sub, tr_("Plant") if ok else "🔒", func():
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
