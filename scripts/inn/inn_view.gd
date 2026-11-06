## Inn interior: reputation, Chef's kitchen, guest tables with orders, and guest rooms.
## Rebuilds from the model on inn-related events; holds no rules itself.
extends Control

var main: Node
var _body: VBoxContainer
var _clock := 0.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)   # must happen before entering the tree

func _ready() -> void:
	theme = UI.theme()
	var floor := Panel.new()
	floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	floor.add_theme_stylebox_override("panel", UI.box(Color("#D9A066"), 0, 0))
	add_child(floor)
	for y in range(0, 2000, 96):  # floorboards
		var line := ColorRect.new()
		line.color = Color("#C08550")
		line.position = Vector2(0, y)
		line.size = Vector2(2000, 6)
		floor.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 130
	scroll.offset_bottom = -140
	scroll.offset_left = 16
	scroll.offset_right = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	Game.event.connect(_on_event)
	visibility_changed.connect(func(): if visible: refresh())
	refresh()

func _on_event(name: String, d: Dictionary) -> void:
	if name in ["guest", "served", "room", "collect", "job", "inventory", "reputation", "reset", "tutorial"] and visible:
		refresh.call_deferred()
	if name == "served" and visible:
		Sfx.play("coins")
		main.hud.fly(UI.icon("coin"), get_viewport_rect().size / 2, "coins")
		main.hud.fly(UI.icon("rep"), get_viewport_rect().size / 2, "rep")
		var lines: Array = GameData.characters()[d["char"]]["lines"].get("served", [])
		if not lines.is_empty():
			main.hud.toast("%s: “%s”  +%d" % [GameData.characters()[d["char"]]["name"], Dialogue.text(lines[0]), d["coins"]])

func _process(dt: float) -> void:
	_clock += dt
	if visible and _clock > 1.0:   # countdown labels
		_clock = 0.0
		var lbl := _body.find_child("NextGuest", true, false) as Label
		if lbl: lbl.text = _next_text()

func _next_text() -> String:
	return tr("Next guest in %s") % UI.fmt_time(maxf(0.0, float(Game.model.inn()["next_guest"]) - Game.now()))

func refresh() -> void:
	if not is_inside_tree(): return
	for c in _body.get_children(): c.queue_free()
	var m: GameModel = Game.model
	var now := Game.now()
	if not m.tutorial_step().is_empty():   # room for the tutorial card
		var gap := Control.new()
		gap.custom_minimum_size.y = 290
		_body.add_child(gap)
	var tier := m.rep_tier()
	var tiers: Array = GameData.economy()["inn"]["reputation_tiers"]
	var head := HBoxContainer.new()
	var title := UI.label("%s\n%s" % [tr("The Harvest Inn"), tr(tier["name"])], 34, UI.CREAM, 600)
	title.add_theme_color_override("font_outline_color", UI.INK)
	title.add_theme_constant_override("outline_size", 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.button(tr("Farm"), func(): main.show_farm(), UI.MEADOW, UI.icon("farm")))
	_body.add_child(head)
	if int(tier["index"]) + 1 < tiers.size():
		var next: Dictionary = tiers[int(tier["index"]) + 1]
		var bar := ProgressBar.new()
		bar.min_value = int(tier["reputation"])
		bar.max_value = int(next["reputation"])
		bar.value = int(m.s["reputation"])
		bar.custom_minimum_size.y = 28
		bar.show_percentage = false
		_body.add_child(bar)
		_body.add_child(_card_label(tr("%d / %d reputation → %s (%d tables)") % [int(m.s["reputation"]), int(next["reputation"]), tr(next["name"]), int(next["tables"])]))
	# Chef's kitchen
	var chef := _card()
	var ch := HBoxContainer.new()
	chef.add_child(ch)
	ch.add_child(Portrait.make("chef", 130))
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(UI.label(GameData.characters()["chef"]["name"], 28, UI.RED, 600))
	var q: Array = m.s["buildings"]["kitchen"]["queue"] if m.owns_building("kitchen") else []
	var ready := q.filter(func(j): return float(j["end"]) <= now).size()
	cv.add_child(UI.label(tr("%d cooking · %d ready") % [q.size() - ready, ready], 24))
	cv.add_child(UI.button(tr("Open kitchen"), func(): Screens.workshop(main, "kitchen"), UI.RED))
	ch.add_child(cv)
	_body.add_child(chef)
	# Tables
	_body.add_child(_section(tr("Tables")))
	var guests: Array = m.inn()["guests"]
	for i in int(tier["tables"]):
		_body.add_child(_table(i, guests[i] if i < guests.size() else {}))
	# Guest rooms
	var rooms_cfg: Array = GameData.economy()["inn"]["guest_rooms"]
	if m.is_unlocked(rooms_cfg[0]["unlock_level"]):
		_body.add_child(_section(tr("Guest rooms")))
		var rooms: Array = m.inn()["rooms"]
		for i in rooms.size():
			_body.add_child(_room(i, rooms[i], now))
		if rooms.size() < rooms_cfg.size():
			var c: Dictionary = rooms_cfg[rooms.size()]
			var ok := m.is_unlocked(c["unlock_level"])
			_body.add_child(Screens.row(UI.icon("inn"), tr("New guest room"), tr("%d coins") % int(c["cost"]) if ok else tr("Unlocks at level %d") % int(c["unlock_level"]),
				tr("Build") if ok else Screens.LOCK, func(): _act(m.build_room(Game.now())), ok, UI.MEADOW))
	_body.add_child(UI.button(tr("Inn furniture (+reputation)"), func(): Screens.shop(main, "style"), UI.WOOD_DARK))

func _table(i: int, g: Dictionary) -> PanelContainer:
	var m: GameModel = Game.model
	var p := _card()
	var h := HBoxContainer.new()
	p.add_child(h)
	if g.is_empty():
		h.add_child(UI.icon_rect(UI.icon("clock"), 80))
		var l := UI.label(_next_text(), 26, UI.WOOD_DARK)
		l.name = "NextGuest"
		h.add_child(l)
		return p
	var c: Dictionary = GameData.characters()[g["char"]]
	h.add_child(Portrait.make(g["char"], 130))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	v.add_child(UI.label("%s · %s" % [c["name"], tr(c["role"])], 24, UI.RED, 600))
	var arrive: Array = c["lines"].get("arrive", [])
	if not arrive.is_empty():
		v.add_child(UI.label("“%s”" % Dialogue.text(arrive[0]), 20, UI.WOOD_DARK))
	var flow := HFlowContainer.new()
	for meal in g["order"]:
		var have := m.count(meal)
		var need := int(g["order"][meal])
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		item.add_child(UI.icon_rect(UI.item_tex(meal), 52))
		item.add_child(UI.label("%d/%d" % [mini(have, need), need], 24, UI.MEADOW if have >= need else UI.RED, 700, false))
		item.tooltip_text = GameData.item_name(meal)
		flow.add_child(item)
	v.add_child(flow)
	var row := HBoxContainer.new()
	var serve := UI.button(tr("Serve · %d") % m.order_value(g["order"]), func(): _act(m.serve_guest(i)), UI.MEADOW, UI.icon("coin"))
	serve.disabled = not m.has_items(g["order"])
	serve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(serve)
	row.add_child(UI.button(tr("Let go"), func(): m.dismiss_guest(i, Game.now()), UI.WOOD_DARK))
	v.add_child(row)
	h.add_child(v)
	return p

func _room(i: int, r: Dictionary, now: float) -> PanelContainer:
	var m: GameModel = Game.model
	var cfg := m.room_config(i)
	if not r["furnished"]:
		var parts := []
		for it in cfg["requires"]:
			parts.append("%s %d/%d" % [GameData.item_name(it), m.count(it), int(cfg["requires"][it])])
		return Screens.row(UI.item_tex("blanket"), tr("Room %d (empty)") % (i + 1), ", ".join(parts), tr("Furnish"),
			func(): _act(m.furnish_room(i, Game.now())), m.has_items(cfg["requires"]), UI.MEADOW)
	var income := m.room_income(i, now)
	return Screens.row(UI.item_tex("pillow"), tr("Room %d · %d coins/hour") % [i + 1, int(cfg["coins_per_hour"])], tr("%d coins waiting") % income,
		tr("Collect"), func(): _act(m.collect_room(i, Game.now())), income > 0, UI.MEADOW)

func _act(err: String) -> void:
	if err != "": main.say_error(err)

func _card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(UI.CREAM, 24, 4))
	return p

func _card_label(t: String) -> Label:
	var l := UI.label(t, 22, UI.CREAM, 600)
	l.add_theme_color_override("font_outline_color", UI.INK)
	l.add_theme_constant_override("outline_size", 6)
	return l

func _section(t: String) -> Label:
	var l := UI.label(t, 34, UI.CREAM, 600)
	l.add_theme_color_override("font_outline_color", UI.INK)
	l.add_theme_constant_override("outline_size", 8)
	return l
