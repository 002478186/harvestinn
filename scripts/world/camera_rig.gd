## Third-person camera: smooth (frame-rate independent) follow, drag to orbit, pinch/wheel to zoom.
## Touches on the left 45% of the screen belong to the joystick and are ignored here.
extends Node3D

@export var follow_rate := 7.0
var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-26.0)
var dist := 9.5
var cam := Camera3D.new()
var look_offset := Vector3.ZERO     # shift the framing (e.g. the character creator puts you in the top half)
var _touches := {}
var _pinch := 0.0

func _ready() -> void:
	cam.fov = 46.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

func _physics_process(dt: float) -> void:
	if target == null: return
	global_position = global_position.lerp(target.global_position + Vector3(0, 1.6, 0), 1.0 - exp(-follow_rate * dt))
	var offset := Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	var want := global_position + offset
	var q := PhysicsRayQueryParameters3D.create(global_position, want)
	q.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["position"].y > 0.3:     # ignore the ground itself
		want = global_position + (hit["position"] - global_position) * 0.9
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-14.0 * dt)) if cam.global_position.distance_to(want) < 6.0 else want
	cam.look_at(global_position + look_offset, Vector3.UP)
	if target.has_method("do_action"):
		target.cam_yaw = yaw

func _unhandled_input(e: InputEvent) -> void:
	var w := get_viewport().get_visible_rect().size.x
	if e is InputEventScreenTouch:
		if e.pressed and e.position.x > w * 0.45: _touches[e.index] = e.position
		else: _touches.erase(e.index)
		_pinch = _spread()
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var s := _spread()
			if _pinch > 0.0: dist = clampf(dist * _pinch / maxf(s, 1.0), 7.0, 22.0)
			_pinch = s
		else:
			yaw -= e.relative.x * 0.008
			pitch = clampf(pitch - e.relative.y * 0.004, deg_to_rad(-65.0), deg_to_rad(-15.0))
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: dist = maxf(7.0, dist * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = minf(22.0, dist * 1.1)

func _spread() -> float:
	var p := _touches.values()
	return (p[0] - p[1]).length() if p.size() >= 2 else 0.0
