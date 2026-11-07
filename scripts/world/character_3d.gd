## A KayKit (CC0) animated character: weapons stripped, optional outfit tint, simple anim API.
## Models: Rogue_Hooded, Rogue, Knight, Mage, Barbarian (assets/3d/characters).
class_name Character3D
extends Node3D

const MODELS := ["Rogue_Hooded", "Rogue", "Knight", "Mage", "Barbarian"]
const LOOPING := ["Idle", "Walking_A", "Walking_B", "Running_A", "Sit_Chair_Idle", "Unarmed_Idle", "Sit_Floor_Idle"]
## Adventurer props we never want on a farmer.
const HIDE := ["handslot", "Knife", "Crossbow", "Throwable", "Sword", "Axe", "Shield", "Staff", "Wand", "Spellbook", "Mug", "Arrow", "Quiver", "Bow", "Dagger"]

var model: Node3D
var anim: AnimationPlayer
var current := ""
var speed := 1.5                      # walk speed (m/s) for walk()
var _path: Array = []                 # world-space waypoints still to walk
var _arrived := Callable()

static func make(model_name: String, tint := Color.WHITE) -> Character3D:
	var c := Character3D.new()
	c.name = model_name
	var ps: PackedScene = load("res://assets/3d/characters/%s.glb" % (model_name if model_name in MODELS else MODELS[0]))
	c.model = ps.instantiate()
	c.add_child(c.model)
	c.model.rotation.y = PI        # KayKit faces +Z; our forward is -Z
	c.anim = c.model.find_child("AnimationPlayer", true, false)
	for a in LOOPING:
		if c.anim and c.anim.has_animation(a):
			c.anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	c._strip(c.model)
	if tint != Color.WHITE:
		c._tint(c.model, tint)
	return c

func _ready() -> void:
	play("Idle")

func _strip(n: Node) -> void:
	for ch in n.get_children():
		if ch is Node3D and HIDE.any(func(h): return ch.name.contains(h)) and not ch.name.begins_with("hand."):
			(ch as Node3D).visible = false
		_strip(ch)

## Multiplies the texture colours toward `tint` (subtle, so faces stay natural).
func _tint(n: Node, tint: Color) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			for i in ch.mesh.get_surface_count():
				var m: Material = ch.mesh.surface_get_material(i)
				if m is StandardMaterial3D:
					var mm: StandardMaterial3D = m.duplicate()
					mm.albedo_color = Color.WHITE.lerp(tint, 0.55)
					ch.set_surface_override_material(i, mm)
		_tint(ch, tint)

## Plays `name` (cross-fading). One-shots then play `then` (Idle by default).
func play(name: String, blend := 0.2, then := "Idle") -> void:
	if anim == null or not anim.has_animation(name) or current == name: return
	current = name
	anim.play(name, blend)
	if not name in LOOPING:
		var len := anim.get_animation(name).length
		get_tree().create_timer(len * 0.95).timeout.connect(func():
			if current == name: current = ""; play(then))

## Walks through world-space `points` (straight lines), then calls `arrived`.
func walk(points: Array, arrived := Callable()) -> void:
	_path = points.duplicate()
	_arrived = arrived
	current = ""
	play("Walking_A")

func walking() -> bool:
	return not _path.is_empty()

func _process(dt: float) -> void:
	if _path.is_empty(): return
	var d: Vector3 = _path[0] - global_position
	d.y = 0.0
	if d.length() < 0.05:
		_path.pop_front()
		if _path.is_empty():
			current = ""
			play("Idle")
			if _arrived.is_valid(): _arrived.call()
		return
	global_position += d.normalized() * minf(speed * dt, d.length())
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(1.0, dt * 8.0))

## Seated eating: the right arm and head play Use_Item (looped) over Sit_Chair_Idle.
func eat(seconds: float, done: Callable) -> void:
	if anim == null: return done.call()
	current = "Sit_Chair_Idle"
	anim.play("Sit_Chair_Idle", 0.2)
	var bt := AnimationNodeBlendTree.new()
	var sit := AnimationNodeAnimation.new()
	sit.animation = "Sit_Chair_Idle"
	var arm := AnimationNodeAnimation.new()
	arm.animation = "Use_Item"
	arm.use_custom_timeline = true
	arm.loop_mode = Animation.LOOP_PINGPONG
	var mix := AnimationNodeBlend2.new()
	mix.filter_enabled = true
	var a := anim.get_animation("Use_Item")
	for t in a.get_track_count():
		var tp := str(a.track_get_path(t))
		if [":upperarm.r", ":lowerarm.r", ":wrist.r", ":hand.r", ":head"].any(func(b): return tp.ends_with(b)):
			mix.set_filter_path(a.track_get_path(t), true)
	bt.add_node("sit", sit)
	bt.add_node("arm", arm)
	bt.add_node("mix", mix)
	bt.connect_node("mix", 0, "sit")
	bt.connect_node("mix", 1, "arm")
	bt.connect_node("output", 0, "mix")
	var tree := AnimationTree.new()
	tree.tree_root = bt
	anim.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.set("parameters/mix/blend_amount", 1.0)
	get_tree().create_timer(seconds).timeout.connect(func():
		tree.queue_free()
		done.call())

func busy() -> bool:
	return current != "" and not current in LOOPING
