## Floating virtual joystick: touch anywhere on the left side, drag to move.
## `value` is -1..1 on both axes (y = down/back), magnitude = walk vs run.
extends Control

const RADIUS := 110.0
var value := Vector2.ZERO
var _finger := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 0.45
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _finger == -1:
			_finger = e.index
			_origin = e.position
			_knob = e.position
		elif not e.pressed and e.index == _finger:
			_finger = -1
			value = Vector2.ZERO
		queue_redraw()
		accept_event()
	elif e is InputEventScreenDrag and e.index == _finger:
		var d: Vector2 = (e.position - _origin).limit_length(RADIUS)
		_knob = _origin + d
		value = d / RADIUS
		queue_redraw()
		accept_event()

func _draw() -> void:
	var o := _origin if _finger != -1 else Vector2(170, size.y - 330)
	var k := _knob if _finger != -1 else o
	draw_circle(o, RADIUS, Color(1, 1, 1, 0.18))
	draw_arc(o, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
	draw_circle(k, 52, Color(1, 1, 1, 0.75 if _finger != -1 else 0.45))
	draw_arc(k, 52, 0, TAU, 32, UI.INK, 3.0)
