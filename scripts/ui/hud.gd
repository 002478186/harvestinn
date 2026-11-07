## Always-on HUD: currencies/level/reputation on top, main nav at the bottom,
## plus toasts, flying reward icons, popups and one bottom sheet at a time.
## Updates only from Game.event (never polls the model).
extends CanvasLayer

signal nav(screen: String)

var root := Control.new()
var _coins: Label
var _gems: Label
var _level: Label
var _rep: Label
var _xp: ProgressBar
var _targets := {}            # name -> Control (fly destinations)
var _sheet: Control
var _toast: Label
var _banner: PanelContainer
var _popup_queue: Array[Callable] = []
var _popup_open := false

func _ready() -> void:
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var safe := _safe_margins()
	_build_top(safe)
	_build_bottom(safe)
	_build_side(safe)
	_build_ribbon(safe)
	_build_goals(safe)
	edge_arrow.polygon = PackedVector2Array([Vector2(34, 0), Vector2(-18, -26), Vector2(-8, 0), Vector2(-18, 26)])
	edge_arrow.color = Color("#FFD54A")
	edge_arrow.visible = false
	edge_arrow.scale = Vector2(1.6, 1.6)
	root.add_child(edge_arrow)
	var ap := edge_arrow.create_tween().set_loops()   # pulse so it catches the eye
	ap.tween_property(edge_arrow, "scale", Vector2(1.9, 1.9), 0.4).set_trans(Tween.TRANS_SINE)
	ap.tween_property(edge_arrow, "scale", Vector2(1.6, 1.6), 0.4).set_trans(Tween.TRANS_SINE)
	clock = UI.label("", 24, Color.WHITE, 700, false)
	clock.add_theme_color_override("font_outline_color", UI.INK)
	clock.add_theme_constant_override("outline_size", 8)
	clock.position = Vector2(24, safe.x + 184)
	root.add_child(clock)
	_toast = UI.label("", 30, Color.WHITE)
	_toast.add_theme_color_override("font_outline_color", UI.INK)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-330, safe.y + 150)
	_toast.size = Vector2(660, 80)
	_toast.modulate.a = 0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	Game.event.connect(_on_event)
	_refresh()

## Notch / home-indicator margins in viewport units.
func _safe_margins() -> Vector2:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.y <= 0 or safe.size.y <= 0: return Vector2(16, 16)
	var k := root.get_viewport_rect().size.y / float(win.y)
	var top := maxf(16.0, (safe.position.y - DisplayServer.window_get_position().y) * k)
	var bottom := maxf(16.0, (win.y - safe.end.y) * k)
	return Vector2(clampf(top, 16, 140), clampf(bottom, 16, 120))

func _build_top(safe: Vector2) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = safe.x
	bar.offset_left = 16
	bar.offset_right = -16
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	var lvl_box := _pill(bar, UI.icon("xp"), "level")
	_level = lvl_box[0]
	_xp = ProgressBar.new()
	_xp.custom_minimum_size = Vector2(90, 20)
	_xp.show_percentage = false
	_xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvl_box[1].add_child(_xp)
	_coins = _pill(bar, UI.icon("coin"), "coins")[0]
	_gems = _pill(bar, UI.icon("gem"), "gems")[0]
	_rep = _pill(bar, UI.icon("rep"), "rep")[0]

func _pill(parent: Control, ic: Texture2D, target: String) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(UI.CREAM, 40, 4))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	var r := UI.icon_rect(ic, 44)
	h.add_child(r)
	var l := UI.label("0", 28, UI.INK, 700, false)
	h.add_child(l)
	parent.add_child(p)
	_targets[target] = r
	return [l, h]

var joystick: Control
var clock: Label
var action_btn: Button

## Joystick (left), context action (bottom right). The farm is walked, not menu-driven.
func _build_bottom(safe: Vector2) -> void:
	joystick = preload("res://scripts/ui/joystick.gd").new()
	root.add_child(joystick)
	root.move_child(joystick, 0)
	action_btn = UI.button("", func(): nav.emit("action"), UI.MEADOW)
	action_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action_btn.offset_left = -430
	action_btn.offset_right = -24
	action_btn.offset_top = -safe.y - 200
	action_btn.offset_bottom = -safe.y - 60
	action_btn.add_theme_font_size_override("font_size", 34)
	action_btn.add_theme_constant_override("icon_max_width", 72)
	action_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_btn.visible = false
	action_btn.button_down.connect(func(): nav.emit("sweep_on"))
	action_btn.button_up.connect(func(): nav.emit("sweep_off"))
	root.add_child(action_btn)
	_targets["action"] = action_btn
	seed_btn = UI.button("", func(): nav.emit("seed"), UI.WHEAT)   # swap seeds while standing on a plot
	seed_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	seed_btn.offset_left = -430
	seed_btn.offset_right = -310
	seed_btn.offset_top = -safe.y - 330
	seed_btn.offset_bottom = -safe.y - 210
	seed_btn.add_theme_constant_override("icon_max_width", 72)
	seed_btn.visible = false
	root.add_child(seed_btn)

var seed_btn: Button

## Shown while plots are selected: plant them all, harvest the ripe ones, select all empty, clear.
var sel_bar: PanelContainer

func show_selection(count: int, ripe: int) -> void:
	if sel_bar: sel_bar.queue_free()
	sel_bar = null
	if count == 0: return
	sel_bar = PanelContainer.new()
	sel_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sel_bar.offset_left = 16
	sel_bar.offset_right = -16
	sel_bar.offset_top = -_safe_margins().y - 380
	sel_bar.offset_bottom = -_safe_margins().y - 230
	var v := VBoxContainer.new()
	sel_bar.add_child(v)
	var l := UI.label(tr("%d plots selected") % count, 24, UI.RED, 600, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var h := HBoxContainer.new()
	v.add_child(h)
	var btns := [[tr("Plant"), "sel_plant", UI.MEADOW], [tr("All empty"), "sel_all", UI.WOOD_DARK], ["✕", "sel_clear", UI.WOOD_DARK]]
	if ripe > 0: btns.insert(1, [tr("Harvest %d") % ripe, "sel_harvest", UI.WHEAT])
	for b in btns:
		var bt := UI.button(b[0], func(): nav.emit(b[1]), b[2])
		bt.add_theme_font_size_override("font_size", 24)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL if b[1] != "sel_clear" else Control.SIZE_FILL
		h.add_child(bt)
	root.add_child(sel_bar)

## Shows the current seed on a chip above the action button (only while on a plot).
func set_seed(crop: String) -> void:
	seed_btn.visible = crop != ""
	if crop != "": seed_btn.icon = UI.item_tex(crop)

func set_action(label: String, icon_name: String) -> void:
	action_btn.visible = label != ""
	action_btn.text = label
	action_btn.icon = UI.icon(icon_name) if icon_name != "" else null
	if action_btn.visible:
		action_btn.pivot_offset = action_btn.size / 2
		var tw := action_btn.create_tween()
		tw.tween_property(action_btn, "scale", Vector2(1.08, 1.08), 0.08)
		tw.tween_property(action_btn, "scale", Vector2.ONE, 0.12)

## Off-screen target: a golden arrow on the screen edge pointing at it.
var edge_arrow := Polygon2D.new()

func point_to(screen: Vector2, behind: bool) -> void:
	var view := root.get_viewport_rect().size
	var margin := Vector2(70, 200)
	var inside := not behind and Rect2(margin * 0.5, view - margin).has_point(screen)
	edge_arrow.visible = not inside and screen.x < INF
	if not edge_arrow.visible: return
	var c := view / 2
	var dir := (screen - c) * (-1.0 if behind else 1.0)
	if dir.length() < 1.0: dir = Vector2.DOWN
	var k := minf((c.x - margin.x) / maxf(absf(dir.x), 0.001), (c.y - margin.y) / maxf(absf(dir.y), 0.001))
	edge_arrow.position = c + dir * k
	edge_arrow.rotation = dir.angle()

## The goal ribbon under the top bar: how far the inn is from its next tier (the game's
## objective) and what the next level unlocks. Tap it to open the journal.
var _ribbon: PanelContainer
var _goal_text: Label
var _goal_bar: ProgressBar
var _next_text: Label

func _build_ribbon(safe: Vector2) -> void:
	_ribbon = PanelContainer.new()
	_ribbon.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ribbon.offset_top = safe.x + 70
	_ribbon.offset_left = 16
	_ribbon.offset_right = -112
	_ribbon.add_theme_stylebox_override("panel", UI.box(Color(1, 0.97, 0.88, 0.92), 18, 3))
	_ribbon.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: nav.emit("journal"))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var ic := UI.icon_rect(UI.icon("inn"), 30)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	_goal_text = UI.label("", 22, UI.INK, 700, false)
	_goal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_goal_text)
	_goal_bar = ProgressBar.new()
	_goal_bar.show_percentage = false
	_goal_bar.custom_minimum_size = Vector2(0, 12)
	_goal_bar.max_value = 1.0
	_goal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_goal_bar)
	_next_text = UI.label("", 19, UI.WOOD_DARK, 700, false)
	_next_text.clip_text = true
	v.add_child(_next_text)
	root.add_child(_ribbon)
	_refresh_ribbon()

func _refresh_ribbon() -> void:
	if _ribbon == null: return
	var m: GameModel = Game.model
	var g := m.inn_goal()
	_goal_text.text = tr("%s · top tier!") % tr(g["name"]) if g["top"] else tr("%s · %d/%d rep → %d tables") % [tr(g["name"]), g["rep"], g["next_rep"], g["next_tables"]]
	_goal_bar.value = g["progress"]
	var lv := int(m.s["level"]) + 1
	var names: Array = GameData.unlocks_at(lv).map(func(u): return tr(u["name"]))
	_next_text.text = tr("Level %d unlocks: %s") % [lv, ", ".join(names.slice(0, 3)) + ("…" if names.size() > 3 else "")] if not names.is_empty() else tr("Level %d: keep growing!") % lv

## Today's goals, top left (after the tutorial): progress, then a Claim button when done.
var goals_box := VBoxContainer.new()

func _build_goals(safe: Vector2) -> void:
	goals_box.position = Vector2(16, safe.x + 216)
	goals_box.custom_minimum_size.x = 330
	goals_box.add_theme_constant_override("separation", 6)
	goals_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(goals_box)
	_refresh_goals()

func _refresh_goals() -> void:
	for c in goals_box.get_children(): c.queue_free()
	var goals: Array = Game.model.daily_goals(Game.now())
	if goals.is_empty() or goals.all(func(g): return g["claimed"]): return
	var head := UI.label(tr("Today's goals"), 20, Color.WHITE, 700, false)
	head.add_theme_color_override("font_outline_color", UI.INK)
	head.add_theme_constant_override("outline_size", 7)
	goals_box.add_child(head)
	for i in goals.size():
		var g: Dictionary = goals[i]
		if g["claimed"]: continue
		if g["done"]:
			var b := UI.button(tr("%s · claim %d") % [tr(g["text"]), g["coins"]], func(): pass, UI.MEADOW, UI.icon("coin"))
			b.pressed.connect(func(): _claim(i, b))
			b.add_theme_font_size_override("font_size", 20)
			b.custom_minimum_size = Vector2(330, 64)
			goals_box.add_child(b)
			continue
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.box(Color(1, 0.97, 0.88, 0.88), 16, 3))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		p.add_child(h)
		var l := UI.label(tr(g["text"]), 19, UI.INK, 700, false)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UI.label("%d/%d" % [g["progress"], g["n"]], 19, UI.RED, 700, false))
		goals_box.add_child(p)

func _claim(i: int, from: Control) -> void:
	if Game.model.claim_goal(i, Game.now()) != "": return
	Sfx.play("achieve")
	Sfx.buzz("medium")
	var at := from.get_global_rect().get_center() if is_instance_valid(from) else root.get_viewport_rect().size / 2
	for k in 4: fly(UI.icon("coin"), at, "coins")
	fly(UI.icon("xp"), at, "xp")

## Right-hand column for secondary screens (orders, daily reward, achievements).
var side := VBoxContainer.new()

func _build_side(safe: Vector2) -> void:
	side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	side.offset_left = -112
	side.offset_right = -12
	side.offset_top = safe.x + 100
	side.add_theme_constant_override("separation", 8)
	root.add_child(side)
	for b in [["barn", "Barn"], ["shop", "Shop"], ["menu", "More"]]:
		add_side_button(b[0], b[1])

func add_side_button(id: String, tip: String) -> void:
	var b := UI.button("", func(): nav.emit(id), Color(1, 0.97, 0.88, 0.92), UI.icon({"event": "xp", "menu": "settings"}.get(id, id)))
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(88, 88)
	b.add_theme_constant_override("icon_max_width", 60)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(b)
	_targets[id] = b

func _on_event(name: String, d: Dictionary) -> void:
	match name:
		"level_up":
			queue_popup(func(): _level_up_popup(d))
		_:
			pass
	if name in ["coins", "gems", "xp", "reputation", "reset", "level_up"]:
		_refresh()
	if name in ["reputation", "level_up", "reset", "rep_tier"]: _refresh_ribbon()
	if name in ["harvest", "plot", "served", "sold", "collect", "animal", "job", "goal", "tutorial", "level_up", "reset"]:
		_refresh_goals.call_deferred()

func _refresh() -> void:
	var s := Game.model.s
	_coins.text = _short(int(s["coins"]))
	_gems.text = str(int(s["gems"]))
	_level.text = str(int(s["level"]))
	_rep.text = _short(int(s["reputation"]))
	_xp.max_value = GameModel.xp_to_next(int(s["level"]))
	_xp.value = float(s["xp"])

static func _short(n: int) -> String:
	if n >= 1_000_000: return "%.1fM" % (n / 1_000_000.0)
	if n >= 10_000: return "%.1fK" % (n / 1000.0)
	return str(n)

# ------------------------------------------------------------------ feedback

func toast(text: String) -> void:
	_toast.text = text
	var tw := _toast.create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

## Icon flies from a screen position to a HUD element, which then bounces.
func fly(tex: Texture2D, from: Vector2, target: String) -> void:
	var dest: Control = _targets.get(target, _targets["coins"])
	var r := UI.icon_rect(tex, 56)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = from - Vector2(28, 28) + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	root.add_child(r)
	var end := dest.get_global_rect().get_center() - Vector2(28, 28)
	var tw := r.create_tween()
	tw.tween_property(r, "position", r.position + Vector2(0, -60), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "position", end, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		r.queue_free()
		var bt := dest.create_tween()
		dest.pivot_offset = dest.size / 2
		bt.tween_property(dest, "scale", Vector2(1.25, 1.25), 0.06)
		bt.tween_property(dest, "scale", Vector2.ONE, 0.12))

## Persistent hint strip (e.g. "Planting Carrot — tap empty plots").
func banner(text: String, on_close: Callable) -> void:
	clear_banner()
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_banner.offset_top = -340
	_banner.offset_bottom = -240
	_banner.offset_left = 24
	_banner.offset_right = -24
	var h := HBoxContainer.new()
	_banner.add_child(h)
	var l := UI.label(text, 28)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UI.button(tr("Done"), func(): clear_banner(); on_close.call(), UI.MEADOW))
	root.add_child(_banner)

func clear_banner() -> void:
	if _banner:
		_banner.queue_free()
		_banner = null

# ------------------------------------------------------------------ sheets + popups

## Opens a bottom sheet and returns its content box; replaces any open sheet.
func sheet(title: String, height := 0.72) -> VBoxContainer:
	close_sheet()
	clear_banner()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close_sheet())
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_top = 1.0 - height
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_bottom = -_safe_margins().y
	dim.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var head := HBoxContainer.new()
	var t := UI.label(title, 40, UI.RED, 600)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.button("✕", close_sheet, UI.WOOD_DARK))
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_sheet = dim
	panel.position.y += 200
	panel.create_tween().tween_property(panel, "position:y", panel.position.y - 200, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return body

func close_sheet() -> void:
	if _sheet:
		_sheet.queue_free()
		_sheet = null

func sheet_open() -> bool:
	return _sheet != null

## Popups (level up, welcome back, dialogue) show one at a time, in order.
func queue_popup(show: Callable) -> void:
	_popup_queue.append(show)
	if not _popup_open:
		_next_popup()

func _next_popup() -> void:
	if _popup_queue.is_empty():
		_popup_open = false
		return
	_popup_open = true
	_popup_queue.pop_front().call()

## Centered card; returns its VBox. Call `done` (passed to on_close) to dismiss.
func popup(title: String, art: Texture2D = null) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(600, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	if art:
		var r := UI.icon_rect(art, 180)
		v.add_child(r)
	var t := UI.label(title, 44, UI.RED, 600)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.set_meta("dim", dim)
	p.scale = Vector2(0.6, 0.6)
	p.pivot_offset = Vector2(300, 200)
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return v

func close_popup(v: VBoxContainer) -> void:
	v.get_meta("dim").queue_free()
	_next_popup()

func _level_up_popup(d: Dictionary) -> void:
	Sfx.play("level_up")
	var v := popup(tr("Level %d!") % int(d["level"]), UI.icon("xp"))
	v.add_child(UI.label(tr("+%d gems") % int(d["gems"]), 30))
	if not d["unlocks"].is_empty():
		v.add_child(UI.label(tr("New unlocks:"), 30, UI.MEADOW))
		var g := GridContainer.new()
		g.columns = 2
		for u in d["unlocks"]:
			var h := HBoxContainer.new()
			var t: Texture2D = UI.item_tex(u["id"]) if u["kind"] in ["crop", "recipe"] else UI.tex("res://assets/art/buildings/%s.svg" % u["id"])
			if u["kind"] == "animal": t = UI.tex("res://assets/art/animals/%s.svg" % u["id"])
			h.add_child(UI.icon_rect(t if t else UI.icon("gift"), 48))
			h.custom_minimum_size.x = 270
			h.add_child(UI.label(tr(u["name"]), 24, UI.INK, 700, false))   # no wrap: a wrapping label in a box shrinks to one letter per line
			g.add_child(h)
		v.add_child(g)
	v.add_child(UI.button(tr("Hooray!"), func(): close_popup(v), UI.MEADOW))
