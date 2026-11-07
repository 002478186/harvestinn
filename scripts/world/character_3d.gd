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

## Faces and headwear can move between bodies: every KayKit adventurer shares one skeleton.
const HEADS := ["Rogue", "Knight", "Mage", "Barbarian"]
const HEADWEAR := ["", "Rogue_Head_Hooded", "Mage_Hat", "Barbarian_Hat", "Knight_Helmet"]
const HATS := ["Mage_Hat", "Barbarian_Hat", "Knight_Helmet"]
## Cozy clothes colours for villagers and guests.
const TINTS := ["#F2B84B", "#7CC35A", "#8FD3F4", "#E07A5F", "#C97BB5", "#D8B67E", "#F4E3C1", "#5FA8A0", "#B5654A"]
## Things villagers carry in their right hand.
const PROPS := ["restaurant/food_ingredient_carrot.gltf", "restaurant/bowl.gltf", "restaurant/food_ingredient_lettuce.gltf", "village/bucket_water.gltf", "restaurant/jar_C_small.gltf"]
static var _parts := {}       # "Model/Mesh" -> [mesh, skin], so grafts don't re-instantiate models

static func make(model_name: String, tint := Color.WHITE) -> Character3D:
	return make_look({"body": model_name, "tint": tint})

## look: {body, head ("" = body's own), headwear ("default" | "" | HEADWEAR id), cape (bool),
## tint (Color, clothes only), prop (model path held in the right hand, "" = none)}
static func make_look(look: Dictionary) -> Character3D:
	var c := Character3D.new()
	var body := str(look.get("body", MODELS[0]))
	if not body in MODELS: body = MODELS[0]
	c.name = body
	c.model = (load("res://assets/3d/characters/%s.glb" % body) as PackedScene).instantiate()
	c.add_child(c.model)
	c.model.rotation.y = PI        # KayKit faces +Z; our forward is -Z
	c.anim = c.model.find_child("AnimationPlayer", true, false)
	for a in LOOPING:
		if c.anim and c.anim.has_animation(a):
			c.anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	c._strip(c.model)
	var skel: Skeleton3D = c.model.find_children("*", "Skeleton3D", true, false)[0]
	var head := str(look.get("head", ""))
	var wear := str(look.get("headwear", "default"))
	if head != "" or wear != "default":
		for mi in skel.find_children("*", "MeshInstance3D", true, false):
			if mi.name.contains("_Head") or mi.name in HATS: mi.visible = false
		var face := head if head in HEADS else ("Rogue" if body == "Rogue_Hooded" else body)
		if wear == "Rogue_Head_Hooded": c._graft(skel, "Rogue_Hooded", wear)
		else: c._graft(skel, face, face + "_Head")
		if wear in HATS: c._graft(skel, wear.split("_")[0], wear)
	if not look.get("cape", true):
		for mi in skel.find_children("*", "MeshInstance3D", true, false):
			if mi.name.ends_with("_Cape"): mi.visible = false
	var tint: Color = look.get("tint", Color.WHITE)
	if tint != Color.WHITE: c._tint(skel, tint)
	if str(look.get("prop", "")) != "":
		var hand := BoneAttachment3D.new()
		hand.bone_name = "handslot.r"
		skel.add_child(hand)
		var prop: Node3D = (load("res://assets/3d/" + look["prop"]) as PackedScene).instantiate()
		prop.scale = Vector3.ONE * (2.0 if look["prop"].begins_with("village/") else 0.5)
		hand.add_child(prop)
	return c

## A varied but stable look per seed: the same guest always looks the same.
static func random_look(seed: int, with_prop := false) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed)   # neighbouring seeds would otherwise share their first draws
	var wear: String = ["", "", "", "", "Rogue_Head_Hooded", "Mage_Hat", "Barbarian_Hat", "Knight_Helmet"][r.randi() % 8]
	return {"body": MODELS[r.randi() % MODELS.size()], "head": HEADS[r.randi() % HEADS.size()], "headwear": wear,
		"cape": r.randf() < 0.4, "tint": Color(TINTS[r.randi() % TINTS.size()]), "prop": PROPS[r.randi() % PROPS.size()] if with_prop and r.randf() < 0.5 else ""}

## Copies mesh `part` of `model` onto `skel` (cached: one load per part, ever).
func _graft(skel: Skeleton3D, model_name: String, part: String) -> void:
	var key := model_name + "/" + part
	if not _parts.has(key):
		var donor: Node = (load("res://assets/3d/characters/%s.glb" % model_name) as PackedScene).instantiate()
		var src: MeshInstance3D = donor.find_child(part, true, false)
		var bone := ""   # hats ride a BoneAttachment3D instead of being skinned
		if src and src.get_parent() is BoneAttachment3D: bone = (src.get_parent() as BoneAttachment3D).bone_name
		_parts[key] = [src.mesh, src.skin, bone, src.transform] if src else []
		donor.free()
	if _parts[key].is_empty(): return
	var mi := MeshInstance3D.new()
	mi.name = part
	mi.mesh = _parts[key][0]
	if _parts[key][2] != "":
		var att := BoneAttachment3D.new()
		att.bone_name = _parts[key][2]
		skel.add_child(att)
		mi.transform = _parts[key][3]
		att.add_child(mi)
		return
	mi.skin = _parts[key][1]
	skel.add_child(mi)
	mi.skeleton = mi.get_path_to(skel)

func _ready() -> void:
	play("Idle")

func _strip(n: Node) -> void:
	for ch in n.get_children():
		if ch is Node3D and HIDE.any(func(h): return ch.name.contains(h)) and not ch.name.begins_with("hand."):
			(ch as Node3D).visible = false
		_strip(ch)

## Recolours clothes toward `tint`: colourful texels (cloth) take the tint by luminance,
## neutral ones (belts, buckles, metal) keep their look. Faces, hands and hair are untouched.
const CLOTH := """
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float colourful = smoothstep(0.03, 0.12, length(c - vec3(l)));
	ALBEDO = mix(c, tint.rgb * (l * 1.3 + 0.35), colourful * 0.85);
	ROUGHNESS = 0.9;
	RIM = 0.35;
	RIM_TINT = 0.6;
}"""
static var _cloth: Shader

func _tint(n: Node, tint: Color) -> void:
	if _cloth == null:
		_cloth = Shader.new()
		_cloth.code = CLOTH
	for ch in n.find_children("*", "MeshInstance3D", true, false):
		if not ["_Body", "_Leg", "_Cape", "_Hat", "_Helmet"].any(func(p): return ch.name.contains(p)): continue
		for i in ch.mesh.get_surface_count():
			var m: Material = ch.mesh.surface_get_material(i)
			if m is StandardMaterial3D and m.albedo_texture:
				var sm := ShaderMaterial.new()
				sm.shader = _cloth
				sm.set_shader_parameter("tex", m.albedo_texture)
				sm.set_shader_parameter("tint", tint)
				ch.set_surface_override_material(i, sm)

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
