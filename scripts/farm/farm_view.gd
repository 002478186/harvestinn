## The farm world: grass, plot grid, buildings, animals, decorations, and touch camera.
## Tap = act, drag = pan, pinch / wheel = zoom, long-press a building or decoration = move it.
extends Node2D

signal plot_tapped(index: int)
signal building_tapped(id: String)
signal fly(tex: Texture2D, screen_pos: Vector2, target: String)

const TILE := 128.0
const WORLD := Vector2i(14, 20)
const PLOT_ORIGIN := Vector2i(3, 8)
const LONG_PRESS := 0.5

## Default tile slot per building id; the player can long-press to move them.
const SLOTS := {
	"inn": Vector2i(4, 3), "mill": Vector2i(1, 5), "bakery": Vector2i(11, 5), "jam_kitchen": Vector2i(1, 2),
	"craft_table": Vector2i(11, 2), "dairy": Vector2i(1, 17), "soap_maker": Vector2i(11, 17), "loom": Vector2i(6, 17),
	"coop": Vector2i(0, 13), "barn_stall": Vector2i(12, 13), "goat_pen": Vector2i(3, 17), "sheep_pen": Vector2i(9, 17),
}

var cam := Camera2D.new()
var _plots: Array[Node2D] = []
var _objects := {}            # id -> Node2D (buildings + decor)
var _touches := {}            # index -> position
var _press := {}              # {pos, time, moved, obj}
var _dragging_obj := ""
var _pinch_start := 0.0
var _zoom_start := 1.0

func _ready() -> void:
	var grass := Sprite2D.new()
	grass.texture = UI.tex("res://assets/art/tiles/grass.svg")
	grass.region_enabled = true
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.region_rect = Rect2(Vector2.ZERO, Vector2(WORLD) * TILE)
	grass.centered = false
	add_child(grass)
	cam.position = Vector2(PLOT_ORIGIN.x + Game.model.s["cols"] / 2.0, 6.5) * TILE
	cam.zoom = Vector2.ONE * 0.8
	add_child(cam)
	Game.event.connect(_on_event)
	rebuild()
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_refresh_plots)
	add_child(t)

func _on_event(name: String, _d: Dictionary) -> void:
	if name in ["reset", "plot", "land", "building", "decor", "animal"]:
		rebuild()

func rebuild() -> void:
	for p in _plots: p.queue_free()
	_plots.clear()
	for o in _objects.values(): o.queue_free()
	_objects.clear()
	var m := Game.model
	for i in m.s["plots"].size():
		var n := Node2D.new()
		n.position = plot_pos(i)
		var soil := Sprite2D.new()
		soil.texture = UI.tex("res://assets/art/tiles/soil.svg")
		n.add_child(soil)
		var crop := Sprite2D.new()
		crop.name = "Crop"
		n.add_child(crop)
		var lbl := UI.label("", 22, Color.WHITE)
		lbl.name = "Timer"
		lbl.position = Vector2(-60, 26)
		lbl.size = Vector2(120, 30)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_outline_color", UI.INK)
		lbl.add_theme_constant_override("outline_size", 8)
		n.add_child(lbl)
		add_child(n)
		_plots.append(n)
	_add_object("inn", "res://assets/art/buildings/inn.svg", 3)
	for b in m.s.get("buildings", {}):
		if b == "kitchen": continue
		_add_object(b, "res://assets/art/buildings/%s.svg" % b, 2)
	for i in m.s.get("decor", []).size():
		var d: Dictionary = m.s["decor"][i]
		_add_object("decor:%d" % i, "res://assets/art/decor/%s.svg" % d["id"], 1)
	_refresh_plots()

func _add_object(id: String, tex_path: String, tiles: int) -> void:
	var spr := Sprite2D.new()
	spr.texture = UI.tex(tex_path)
	if spr.texture:
		spr.scale = Vector2.ONE * (tiles * TILE) / spr.texture.get_size().x
	var tile := object_tile(id)
	spr.position = (Vector2(tile) + Vector2.ONE * tiles / 2.0) * TILE
	spr.set_meta("tiles", tiles)
	add_child(spr)
	_objects[id] = spr
	if Game.model.s.get("buildings", {}).has(id) or id == "inn":
		_badge(spr, id)

## A small "ready" bubble over buildings with finished work.
func _badge(spr: Sprite2D, id: String) -> void:
	var bubble := Sprite2D.new()
	bubble.name = "Ready"
	bubble.texture = UI.icon("xp")
	bubble.position = Vector2(0, -spr.texture.get_size().y * 0.45)
	bubble.scale = Vector2.ONE * 0.9 / spr.scale.x
	bubble.visible = false
	spr.add_child(bubble)

func object_tile(id: String) -> Vector2i:
	var pos: Dictionary = Game.model.s.get("pos", {})
	if pos.has(id):
		return Vector2i(int(pos[id][0]), int(pos[id][1]))
	if id.begins_with("decor:"):
		var d: Dictionary = Game.model.s["decor"][int(id.split(":")[1])]
		return Vector2i(int(d["x"]), int(d["y"]))
	return SLOTS.get(id, Vector2i(0, 0))

func plot_pos(i: int) -> Vector2:
	var cols := int(Game.model.s["cols"])
	return (Vector2(PLOT_ORIGIN) + Vector2(i % cols, i / cols) + Vector2(0.5, 0.5)) * TILE

func plot_at(world: Vector2) -> int:
	var cell := Vector2i((world / TILE).floor()) - PLOT_ORIGIN
	var cols := int(Game.model.s["cols"])
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= int(Game.model.s["rows"]):
		return -1
	var i := cell.y * cols + cell.x
	return i if i < _plots.size() else -1

func object_at(world: Vector2) -> String:
	for id in _objects:
		var spr: Sprite2D = _objects[id]
		var half: float = float(spr.get_meta("tiles")) * TILE / 2.0
		if Rect2(spr.position - Vector2(half, half), Vector2(half, half) * 2).has_point(world):
			return id
	return ""

func _refresh_plots() -> void:
	var m := Game.model
	var now := Game.now()
	for i in _plots.size():
		var p: Dictionary = m.s["plots"][i]
		var crop: Sprite2D = _plots[i].get_node("Crop")
		var lbl: Label = _plots[i].get_node("Timer")
		if p["crop"] == "":
			crop.texture = null
			lbl.text = ""
			continue
		var prog := m.plot_progress(i, now)
		var stage := "sprout" if prog < 0.34 else ("%s_growing" % p["crop"] if prog < 1.0 else "%s_ready" % p["crop"])
		crop.texture = UI.tex("res://assets/art/crops/%s.svg" % stage)
		lbl.text = "" if prog >= 1.0 else UI.fmt_time(m.plot_remaining(i, now))
	for id in _objects:
		var r: Node = _objects[id].get_node_or_null("Ready")
		if r:
			r.visible = m.building_has_ready(id, now)

# ------------------------------------------------------------------ feedback

func harvest_feedback(i: int, crop: String, qty: int) -> void:
	var n := _plots[i]
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(1.25, 0.8), 0.07)
	tw.tween_property(n, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst(n.position, GameData.items()[crop]["color"])
	var screen := get_global_transform_with_canvas() * n.position
	for k in mini(qty, 3):
		fly.emit(UI.item_tex(crop), screen, "barn")
	fly.emit(UI.icon("xp"), screen, "xp")

func burst(at: Vector2, color: String) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 6.0
	p.scale_amount_max = 12.0
	p.color = Color(color)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

# ------------------------------------------------------------------ input

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_set_zoom(cam.zoom.x * (1.1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9))
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_press = {"pos": ev.position, "time": Time.get_ticks_msec(), "moved": false}
			elif _touches.size() == 2:
				_press["moved"] = true
				_pinch_start = _touch_spread()
				_zoom_start = cam.zoom.x
		else:
			_touches.erase(ev.index)
			if _dragging_obj != "":
				_drop_object()
			elif _touches.is_empty() and not _press.get("moved", true):
				_tap(_to_world(ev.position))
			if _touches.is_empty():
				_press = {}
	elif ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _dragging_obj != "":
			var spr: Sprite2D = _objects[_dragging_obj]
			spr.position = _to_world(ev.position)
		elif _touches.size() >= 2:
			if _pinch_start > 0.0:
				_set_zoom(_zoom_start * _touch_spread() / _pinch_start)
		elif _press and (ev.position - _press["pos"]).length() > 24.0:
			_press["moved"] = true
			cam.position -= ev.relative / cam.zoom
			_clamp_cam()
		elif _press.get("moved", false):
			cam.position -= ev.relative / cam.zoom
			_clamp_cam()

func _process(_dt: float) -> void:
	# Long-press on a building/decoration (finger held still) picks it up.
	if _press and not _press.get("moved", true) and _dragging_obj == "" and _touches.size() == 1:
		if Time.get_ticks_msec() - int(_press["time"]) > LONG_PRESS * 1000:
			var id := object_at(_to_world(_press["pos"]))
			if id != "":
				_dragging_obj = id
				_objects[id].modulate.a = 0.7
				Sfx.play("pickup")
			_press["moved"] = true

func _drop_object() -> void:
	var id := _dragging_obj
	_dragging_obj = ""
	var spr: Sprite2D = _objects[id]
	var tiles := int(spr.get_meta("tiles"))
	var tile := Vector2i((spr.position / TILE - Vector2.ONE * tiles / 2.0).round())
	tile = tile.clamp(Vector2i.ZERO, WORLD - Vector2i(tiles, tiles))
	if not Game.model.move_object(id, tile.x, tile.y, tiles, _occupied(id)):
		Sfx.play("error")
	rebuild()

## Tiles taken by plots and every other object (for move validation).
func _occupied(except: String) -> Array:
	var out := []
	var cols := int(Game.model.s["cols"])
	var rows := int(Game.model.s["rows"])
	out.append([PLOT_ORIGIN.x, PLOT_ORIGIN.y, cols, rows])
	for id in _objects:
		if id == except: continue
		var t := object_tile(id)
		var n := int(_objects[id].get_meta("tiles"))
		out.append([t.x, t.y, n, n])
	return out

func _tap(world: Vector2) -> void:
	var i := plot_at(world)
	if i >= 0:
		plot_tapped.emit(i)
		return
	var id := object_at(world)
	if id != "" and not id.begins_with("decor:"):
		building_tapped.emit(id)

func _to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen

func _touch_spread() -> float:
	var pts := _touches.values()
	return (pts[0] - pts[1]).length() if pts.size() >= 2 else 0.0

func _set_zoom(z: float) -> void:
	cam.zoom = Vector2.ONE * clampf(z, 0.45, 1.6)
	_clamp_cam()

func _clamp_cam() -> void:
	cam.position = cam.position.clamp(Vector2.ZERO, Vector2(WORLD) * TILE)
