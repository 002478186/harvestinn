## A radial picker that opens around a point in the world (a plot, a workshop station):
## round icon buttons pop out in a ring; the centre button opens the full sheet.
## It takes the HUD's sheet slot, so the player freezes and tapping outside closes it.
class_name Radial
extends Control

const BTN := 104

## item: {tex: Texture2D, label: String, sub: String, enabled: bool, act: Callable, why: String (toast when disabled)}
static func open(hud, world_pos: Vector3, items: Array, more: Callable, more_label := "") -> Radial:
	hud.close_sheet()
	hud.clear_banner()
	var r := Radial.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: hud.close_sheet())
	r.add_child(dim)
	hud.root.add_child(r)
	hud._sheet = r
	var view: Vector2 = hud.root.get_viewport_rect().size
	var radius := clampf(70.0 + items.size() * 17.0, 150.0, 290.0)
	var cam: Camera3D = hud.get_viewport().get_camera_3d()
	var c: Vector2 = cam.unproject_position(world_pos) if cam else view / 2
	c = c.clamp(Vector2(radius + BTN * 0.6, radius + 220), view - Vector2(radius + BTN * 0.6, radius + 260))
	var pts := ring(items.size(), radius, c)
	for k in items.size():
		var it: Dictionary = items[k]
		var b := _bubble(it["tex"], it.get("label", ""), it.get("sub", ""), it.get("enabled", true))
		b.position = c - Vector2(BTN, BTN) / 2
		r.add_child(b)
		if it.get("enabled", true):
			var act: Callable = it["act"]
			b.pressed.connect(func(): Sfx.play("click"); hud.close_sheet(); act.call())
		else:
			var why: String = it.get("why", "")
			b.pressed.connect(func():
				Sfx.play("error")
				if why != "": hud.toast(why))
		b.scale = Vector2.ZERO
		b.pivot_offset = Vector2(BTN, BTN) / 2
		var tw := b.create_tween().set_parallel()
		tw.tween_property(b, "position", pts[k] - Vector2(BTN, BTN) / 2, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(k * 0.02)
		tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(k * 0.02)
	var mid := UI.button(more_label if more_label != "" else TranslationServer.translate("More"), func(): hud.close_sheet(); more.call(), UI.WOOD_DARK)
	mid.custom_minimum_size = Vector2(BTN, BTN) * 0.85
	mid.position = c - mid.custom_minimum_size / 2
	r.add_child(mid)
	return r

## Evenly spaced points on a circle, the first one straight up.
static func ring(n: int, radius: float, centre: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in n:
		var a := -PI / 2.0 + TAU * k / maxf(1.0, n)
		out.append(centre + Vector2(cos(a), sin(a)) * radius)
	return out

static func _bubble(tex: Texture2D, label: String, sub: String, enabled: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(BTN, BTN)
	b.size = Vector2(BTN, BTN)
	var bg := UI.box(UI.CREAM if enabled else Color("#CFC6B6"), BTN / 2, 4)
	for st in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(st, bg)
	var ic := UI.icon_rect(tex, 68)
	ic.position = Vector2(18, 10)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enabled: ic.modulate = Color(0.5, 0.5, 0.5, 0.8)
	b.add_child(ic)
	for line in [[label, 24, 0.0], [sub, 19, 26.0]]:
		if line[0] == "": continue
		var l := UI.label(line[0], line[1], Color.WHITE, 700, false)
		l.add_theme_color_override("font_outline_color", UI.INK)
		l.add_theme_constant_override("outline_size", 7)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(-30, BTN - 12 + line[2])
		l.size = Vector2(BTN + 60, 28)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	return b
