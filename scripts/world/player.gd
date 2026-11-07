## The farmer: CharacterBody3D moved by the joystick (or WASD/arrows), camera-relative.
## Walks or runs with the stick's tilt, turns smoothly, plays footsteps and action anims.
extends CharacterBody3D

const WALK := 3.2
const RUN := 6.5
const TURN := 12.0

var body: Character3D
var stick := Vector2.ZERO          # set by the HUD joystick each frame (-1..1)
var cam_yaw := 0.0                 # set by the camera rig
var frozen := false                # true while a menu is open
var _step := 0.0
var _foot: AudioStreamPlayer3D

func setup(look: Dictionary) -> void:
	if body: body.queue_free()
	body = Character3D.make_look(look)
	body.scale = Vector3.ONE * 0.8
	add_child(body)

func _ready() -> void:
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_foot = AudioStreamPlayer3D.new()
	_foot.stream = load("res://assets/audio/kenney/walking.ogg")
	_foot.volume_db = -8.0
	add_child(_foot)

func _input_vector() -> Vector2:
	var v := stick
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if k != Vector2.ZERO:
		v = k.normalized() * (1.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 0.6)
	return v.limit_length(1.0)

func _physics_process(dt: float) -> void:
	var v := Vector2.ZERO if frozen or (body and body.busy()) else _input_vector()
	var dir := Vector3(v.x, 0, v.y).rotated(Vector3.UP, cam_yaw)
	var speed := lerpf(0.0, RUN, v.length()) if v.length() > 0.75 else WALK * v.length() / 0.75
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * dt
	move_and_slide()
	if dir.length() > 0.05 and body:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), dt * TURN)
	if body and not body.busy():
		body.play("Idle" if speed < 0.2 else ("Running_A" if speed > WALK + 0.5 else "Walking_A"), 0.15)
	_step -= dt * speed
	if speed > 0.2 and _step <= 0.0 and Sfx.sfx_on:
		_step = 1.7
		_foot.pitch_scale = randf_range(0.9, 1.1)
		_foot.play()

## Face a world point and play a one-shot action (Interact, PickUp, Use_Item, Cheer...).
func do_action(anim: String, at: Vector3) -> void:
	if body == null: return
	var to := at - global_position
	if Vector2(to.x, to.z).length() > 0.1:
		body.rotation.y = atan2(-to.x, -to.z)
	body.play(anim, 0.1)
