## The whole screen is the joystick: touch anywhere (not on a button) and drag to move;
## the stick appears under your finger. A quick tap without dragging is a world tap
## (select plots). Two fingers: pinch to zoom, twist or drag to turn the camera.
## `value` is -1..1 on both axes (y = down/back), magnitude = walk vs run.
extends Control

signal tapped(pos: Vector2)

const RADIUS := 110.0
const TAP_PX := 18.0          # a touch that moves less than this...
const TAP_SECONDS := 0.35     # ...and lifts within this is a tap, not a walk
var value := Vector2.ZERO
var rig: Node3D               # camera rig, for two-finger gestures
var _finger := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _down_at := 0
var _moved := false
var _touches := {}            # index -> position
var _pinch := 0.0
var _twist := 0.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)   # before entering the tree, or size stays 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_finger = e.index
				_origin = e.position
				_knob = e.position
				_down_at = Time.get_ticks_msec()
				_moved = false
			else:   # second finger: camera gesture, the farmer stops
				_finger = -1
				value = Vector2.ZERO
				_pinch = _spread()
				_twist = _angle()
		else:
			_touches.erase(e.index)
			if e.index == _finger:
				if not _moved and Time.get_ticks_msec() - _down_at < TAP_SECONDS * 1000.0: tapped.emit(e.position)
				_finger = -1
				value = Vector2.ZERO
		queue_redraw()
		accept_event()
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2 and rig:
			var s := _spread()
			var a := _angle()
			if _pinch > 0.0: rig.zoom(_pinch / maxf(s, 1.0))
			rig.orbit(a - _twist, -e.relative.y * 0.002)
			_pinch = s
			_twist = a
		elif e.index == _finger:
			if (e.position - _origin).length() > TAP_PX: _moved = true
			var d: Vector2 = (e.position - _origin).limit_length(RADIUS)
			_knob = _origin + d
			value = d / RADIUS if _moved else Vector2.ZERO
			queue_redraw()
		accept_event()

func _spread() -> float:
	var p := _touches.values()
	return (p[0] - p[1]).length() if p.size() >= 2 else 0.0

func _angle() -> float:
	var p := _touches.values()
	return (p[1] - p[0]).angle() if p.size() >= 2 else 0.0

func _draw() -> void:
	if _finger == -1 or not _moved: return   # no stick on screen until you use it
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.18))
	draw_arc(_origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
	draw_circle(_knob, 52, Color(1, 1, 1, 0.75))
	draw_arc(_knob, 52, 0, TAU, 32, UI.INK, 3.0)
