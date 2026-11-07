## Top-view camera: smooth (frame-rate independent) follow; zoom and orbit come from the joystick's
## two-finger gestures (touch) or the mouse wheel and right-drag (desktop).
extends Node3D

@export var follow_rate := 7.0
var target: Node3D
var yaw := 0.0
## Top view, Hay Day style: a high angle that shows fields, pens and paths at a glance.
const TOP_PITCH := -55.0
const TOP_DIST := 17.0
const AHEAD := 3.5          # metres the view leads the farmer: they sit in the lower third, the world ahead shows
var ahead := AHEAD
const PITCH_RANGE := Vector2(-72.0, -42.0)   # orbiting never drops to a low third-person angle
var pitch := deg_to_rad(TOP_PITCH)
var dist := TOP_DIST
var cam := Camera3D.new()
var look_offset := Vector3.ZERO
var anchor := Vector3.ZERO          # inside a room: framing leans toward the room centre
var anchor_weight := 0.0     # shift the framing (e.g. the character creator puts you in the top half)
var trauma := 0.0             # camera punch: 0..1, decays; moves only the camera, never the player
var _shake_t := 0.0

func _ready() -> void:
	cam.fov = 46.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

func _physics_process(dt: float) -> void:
	if target == null: return
	var lead := Vector3(0, 0, -ahead).rotated(Vector3.UP, yaw)
	var focus := (target.global_position + Vector3(0, 1.6, 0) + lead).lerp(anchor + Vector3(0, 1.0, 0), anchor_weight)
	global_position = global_position.lerp(focus, 1.0 - exp(-follow_rate * dt))
	var offset := Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	var want := global_position + offset
	var q := PhysicsRayQueryParameters3D.create(global_position, want)
	q.exclude = [target.get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["position"].y > 0.3:     # ignore the ground itself
		want = global_position + (hit["position"] - global_position) * 0.9
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-14.0 * dt)) if cam.global_position.distance_to(want) < 6.0 else want
	cam.look_at(global_position + look_offset, Vector3.UP)
	if trauma > 0.0:
		trauma = maxf(trauma - 1.6 * dt, 0.0)
		_shake_t += dt * 32.0
		var k := trauma * trauma
		cam.global_position += cam.global_basis * Vector3(sin(_shake_t * 1.7), sin(_shake_t * 2.3), 0) * 0.25 * k
		cam.rotate_object_local(Vector3.FORWARD, sin(_shake_t * 1.1) * 0.04 * k)
	if target.has_method("do_action"):
		target.cam_yaw = yaw

func top_view() -> void:
	pitch = deg_to_rad(TOP_PITCH)
	dist = TOP_DIST
	ahead = AHEAD
	look_offset = Vector3.ZERO

func punch(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

## Two-finger gestures come from the joystick (it owns the whole screen).
func zoom(factor: float) -> void:
	dist = clampf(dist * factor, 10.0, 26.0)

func orbit(d_yaw: float, d_pitch: float) -> void:
	yaw -= d_yaw
	pitch = clampf(pitch + d_pitch, deg_to_rad(PITCH_RANGE.x), deg_to_rad(PITCH_RANGE.y))

## Desktop: wheel zooms, right-drag orbits.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom(1.1)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		orbit(e.relative.x * 0.008, -e.relative.y * 0.004)
