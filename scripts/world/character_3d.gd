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

## Plays `name` (cross-fading). One-shots return to Idle when done.
func play(name: String, blend := 0.2) -> void:
	if anim == null or not anim.has_animation(name) or current == name: return
	current = name
	anim.play(name, blend)
	if not name in LOOPING:
		var len := anim.get_animation(name).length
		get_tree().create_timer(len * 0.95).timeout.connect(func():
			if current == name: current = ""; play("Idle"))

func busy() -> bool:
	return current != "" and not current in LOOPING
