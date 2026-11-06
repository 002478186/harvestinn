## The 3D valley: sky, ground, village buildings, fields you buy, crops that grow, NPCs.
## Owns no rules: it draws Game.model and turns "player is near X" into context actions.
extends Node3D

signal action_changed(label: String, icon: String)

const PLOT := 2.2                       # metres per plot
const FIELD_ORIGIN := Vector3(-8.0, 0.0, 6.0)
const PARCEL_STEP := Vector3(8.4, 0.0, 6.0)

## id -> [model path, scale, position, yaw degrees]. Buildings appear once owned.
const BUILDINGS := {
	"inn": ["village/building_tavern_red.gltf", 6.0, Vector3(0, 0, -15), 0],
	"mill": ["farm/S_Windmill.glb", 0.9, Vector3(17, 0, -17), -20],
	"bakery": ["village/building_home_A_red.gltf", 6.0, Vector3(13, 0, -5), -90],
	"jam_kitchen": ["village/building_home_B_red.gltf", 5.0, Vector3(21, 0, -5), -90],
	"craft_table": ["village/building_blacksmith_red.gltf", 5.0, Vector3(-24, 0, -17), 30],
	"soap_maker": ["village/building_watermill_red.gltf", 4.5, Vector3(-27, 0, -2), 90],
	"loom": ["village/building_lumbermill_red.gltf", 4.5, Vector3(-27, 0, 10), 90],
	"dairy": ["farm/S_SmallBarn.glb", 0.8, Vector3(27, 0, 10), -90],
	"coop": ["farm/S_ChickenCoop.glb", 1.6, Vector3(18, 0, 22), 0],
	"barn_stall": ["farm/S_Barn.glb", 0.75, Vector3(29, 0, 23), -90],
	"goat_pen": ["farm/S_OpenBarn.glb", 0.75, Vector3(18, 0, 33), 0],
	"sheep_pen": ["farm/S_OpenBarn.glb", 0.75, Vector3(29, 0, 33), 0],
}
const MARKET := ["village/building_market_red.gltf", 5.0, Vector3(-15, 0, -8), 30]
## NPC id -> [model, tint, position, what interacting opens]
const NPCS := {
	"innkeeper": ["Mage", Color("#7CC35A"), Vector3(-2.5, 0, -9.5), "inn"],
	"chef": ["Barbarian", Color("#FFFFFF"), Vector3(3.5, 0, -10), "kitchen"],
	"merchant": ["Rogue", Color("#4A6FD8"), Vector3(-13, 0, -3.5), "market"],
	"craftsperson": ["Barbarian", Color("#C49A6C"), Vector3(13.5, 0, -12), "shop"],
	"vet": ["Knight", Color("#8FD3F4"), Vector3(23, 0, 17), "animals"],
}
const CROP_SCALE := 0.85

var main: Node
var player: CharacterBody3D
var day := preload("res://scripts/world/day_night.gd").new()
var _plots: Array[Node3D] = []
var _dynamic: Node3D                     # rebuilt when land/buildings change
var _interact: Array[Dictionary] = []     # {pos, radius, label(): String, act(), icon}
var _interact_in: Array[Dictionary] = []  # same, for the interior you're in
var interiors := preload("res://scripts/world/interiors.gd").new()
const STOREHOUSE := Vector3(-17, 0, 12)
var _current: Dictionary = {}
var _npcs := {}
var _clock := 0.0
var _inside_clock := 0.0

func _ready() -> void:
	_environment()
	_ground()
	_scenery()
	_dynamic = Node3D.new()
	add_child(_dynamic)
	interiors.w = self
	add_child(interiors)
	for id in NPCS:
		var n: Array = NPCS[id]
		var c := Character3D.make(n[0], n[1])
		c.position = n[2]
		add_child(c)
		var tag := Label3D.new()
		tag.text = short_name(id)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 3.0, 0)
		tag.font_size = 48
		tag.outline_size = 12
		tag.modulate = Color.WHITE
		tag.outline_modulate = UI.INK
		c.add_child(tag)
		_npcs[id] = c
	Game.event.connect(_on_event)
	rebuild()

func _on_event(name: String, d: Dictionary) -> void:
	if name in ["reset", "land", "building", "animal", "guest", "served", "rep_tier"]:
		rebuild.call_deferred()
	if interiors.kind != "" and name in ["job", "collect", "guest", "served", "room", "inventory", "reputation", "purchase", "building", "storage", "coins"]:
		interiors.build.call_deferred()
	elif name in ["plot", "harvest"]:
		_refresh_plot(int(d.get("index", -1)))

# ------------------------------------------------------------------ look and feel

func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color("#FFF1D6")
	sun.light_energy = 1.45
	sun.shadow_opacity = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("#5DB7F0")
	sky.sky_horizon_color = Color("#CDEBF7")
	sky.ground_horizon_color = Color("#CDEBF7")
	sky.ground_bottom_color = Color("#7CC35A")
	sky.sun_angle_max = 20.0
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color("#DDEFF8")
	env.fog_density = 0.0018
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	day.sun = sun
	day.env = env
	day.sky = sky
	add_child(day)
	_night_sky()

## Stars (a dome of tiny unshaded dots) and fireflies drifting over the meadows: night only.
func _night_sky() -> void:
	var stars := CPUParticles3D.new()
	stars.amount = 400
	stars.lifetime = 9999.0
	stars.preprocess = 1.0
	stars.explosiveness = 1.0
	stars.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	stars.emission_sphere_radius = 160.0
	stars.gravity = Vector3.ZERO
	stars.initial_velocity_max = 0.0
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	stars.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color("#FFF8E0")
	stars.material_override = smat
	stars.position.y = 20.0
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)
	day.night_fx.append(stars)
	var flies := CPUParticles3D.new()
	flies.amount = 70
	flies.lifetime = 6.0
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(38, 1.2, 38)
	flies.position = Vector3(0, 1.4, 5)
	flies.gravity = Vector3(0, 0.05, 0)
	flies.initial_velocity_min = 0.2
	flies.initial_velocity_max = 0.6
	flies.spread = 180.0
	var fm := SphereMesh.new()
	fm.radius = 0.05
	fm.height = 0.1
	flies.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color("#E8FF8A")
	fmat.emission_enabled = true
	fmat.emission = Color("#E8FF8A")
	fmat.emission_energy_multiplier = 3.0
	flies.material_override = fmat
	add_child(flies)
	day.night_fx.append(flies)

func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

func _ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.noise = noise
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#3F7A2C"))
	ramp.set_color(1, Color("#86BF55"))
	tex.color_ramp = ramp
	var m := _mat(Color.WHITE)
	m.albedo_texture = tex
	m.uv1_scale = Vector3(30, 30, 1)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(180, 180)
	plane.mesh = pm
	plane.material_override = m
	add_child(plane)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(180, 1, 180)
	shape.shape = box
	shape.position.y = -0.5
	floor.add_child(shape)
	add_child(floor)
	# dirt paths: village square and the lane down to the fields
	for p in [[Vector3(0, 0.01, -6), Vector2(34, 6)], [Vector3(0, 0.01, 18), Vector2(4.5, 30)], [Vector3(16, 0.01, 17), Vector2(28, 4)]]:
		var path := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = p[1]
		path.mesh = q
		path.position = p[0]
		path.material_override = _mat(Color("#D8B67E"))
		add_child(path)
	# invisible walls keep the player in the valley
	for w in [[Vector3(0, 2, -45), Vector3(100, 4, 1)], [Vector3(0, 2, 50), Vector3(100, 4, 1)], [Vector3(-42, 2, 0), Vector3(1, 4, 100)], [Vector3(42, 2, 0), Vector3(1, 4, 100)]]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = w[1]
		cs.shape = b
		body.position = w[0]
		body.add_child(cs)
		add_child(body)

## Trees, hills, rocks, clouds and a well: deterministic, so the valley always looks the same.
func _scenery() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var trees := ["village/tree_single_A.gltf", "village/tree_single_B.gltf", "village/trees_A_medium.gltf", "village/trees_B_large.gltf"]
	for i in 70:
		var a := r.randf() * TAU
		var d := r.randf_range(38.0, 58.0)
		_place(trees[i % trees.size()], r.randf_range(5.0, 8.0), Vector3(cos(a) * d, 0, sin(a) * d), r.randf() * 360.0, i % 3 == 0)
	var placed := 0
	while placed < 55:   # inner belt: gives every view depth without blocking anything
		var a := r.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * r.randf_range(20.0, 36.0)
		if not _free_spot(p, 2.0): continue
		_place(trees[placed % trees.size()], r.randf_range(4.5, 7.0), p, r.randf() * 360.0, true)
		placed += 1
	for i in 10:
		var a2 := TAU * i / 10.0
		_place(["village/hills_A_trees.gltf", "village/hills_B_trees.gltf", "village/mountain_A_grass_trees.gltf"][i % 3], 22.0, Vector3(cos(a2) * 80, -1, sin(a2) * 80), r.randf() * 360.0)
	for p in [Vector3(-9, 0, 2), Vector3(11, 0, 3), Vector3(-20, 0, 22), Vector3(34, 0, -8), Vector3(-33, 0, -25), Vector3(-30, 0, 8)]:
		_place(["village/rock_single_A.gltf", "village/rock_single_C.gltf", "village/rock_single_E.gltf"][r.randi() % 3], 5.0, p, r.randf() * 360.0, true)
	_scatter_mesh(_tuft_mesh(), 4500, 1.0, r)
	_scatter("crops/S_Grass_2.glb", 400, 0.7, r, 6.0)
	_square()
	_pond(Vector3(-24, 0, 3), 7.0)
	_place("farm/S_Well.glb", 1.3, Vector3(7, 0, -9), 0, true)
	for p in [Vector3(-5.5, 0, -10.5), Vector3(5.8, 0, -9.0)]:
		_place("village/barrel.gltf", 6.0, p, 0, true)
	_place("village/wheelbarrow.gltf", 6.0, Vector3(4, 0, 4), 40)
	for i in 8:
		var c := _place(["village/cloud_big.gltf", "village/cloud_small.gltf"][i % 2], 6.0, Vector3(r.randf_range(-60, 60), 28 + r.randf() * 8, r.randf_range(-60, 40)), r.randf() * 360.0)
		_no_shadow(c)
		var tw := c.create_tween().set_loops()
		tw.tween_property(c, "position:x", c.position.x + 40, 60 + r.randf() * 40).set_trans(Tween.TRANS_SINE)
		tw.tween_property(c, "position:x", c.position.x, 60 + r.randf() * 40).set_trans(Tween.TRANS_SINE)

## A pond with gently moving water (tiny shader: two scrolling sine ripples + fresnel tint).
func _pond(at: Vector3, radius: float) -> void:
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.05
	disc.radial_segments = 48
	water.mesh = disc
	water.position = at + Vector3(0, 0.03, 0)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep : source_color = vec4(0.20, 0.55, 0.78, 1.0);
uniform vec4 shallow : source_color = vec4(0.45, 0.80, 0.92, 1.0);
void fragment() {
	vec2 p = UV * 18.0;
	float w = sin(p.x + TIME * 1.3) * cos(p.y * 0.8 + TIME * 0.9) * 0.5 + 0.5;
	ALBEDO = mix(deep.rgb, shallow.rgb, w * 0.6 + 0.2);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	water.material_override = mat
	add_child(water)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.2
	torus.outer_radius = radius + 0.6
	rim.mesh = torus
	rim.scale = Vector3(1, 0.25, 1)
	rim.position = at
	rim.material_override = _mat(Color("#B8A27A"))
	add_child(rim)
	for k in 7:
		var a := TAU * k / 7.0
		_place("village/rock_single_%s.gltf" % ["A", "C", "E"][k % 3], 2.5, at + Vector3(cos(a), 0, sin(a)) * (radius + 0.5), k * 50.0)

## Hide small details beyond `dist` metres from the camera (phones draw fewer triangles).
func _cull(n: Node, dist: float) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D: ch.visibility_range_end = dist
		_cull(ch, dist)

func _no_shadow(n: Node) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D: ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadow(ch)

## True where scenery may go (not on paths, fields, the square, buildings or the pond).
func _free_spot(p: Vector3, pad := 0.0) -> bool:
	if absf(p.x) < 3.5 + pad and p.z > -2 and p.z < 34: return false              # lane to the fields
	if p.z > -10 - pad and p.z < -1.5 + pad and absf(p.x) < 18 + pad: return false  # village square
	if p.x > -10 - pad and p.x < 9.5 + pad and p.z > 4 - pad and p.z < 36 + pad: return false
	if Vector2(p.x, p.z + 14).length() < 10 + pad: return false                     # inn
	if Vector2(p.x + 24, p.z - 3).length() < 8 + pad: return false                  # pond
	if p.x > 12 - pad and p.x < 36 + pad and p.z > 14 - pad and p.z < 40 + pad: return false   # animal paddock
	if absf(p.z - 17) < 3 + pad and p.x > 0 and p.x < 32: return false              # lane to the animals
	for id in BUILDINGS:
		var b: Vector3 = BUILDINGS[id][2]
		if Vector2(p.x - b.x, p.z - b.z).length() < 7 + pad: return false
	if Vector2(p.x - MARKET[2].x, p.z - MARKET[2].z).length() < 7 + pad: return false
	return true

## A grass tuft: 5 tapered blades, vertex-coloured dark at the root and sunlit at the tip.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for k in 5:
		var a := TAU * k / 5.0 + r.randf() * 0.6
		var base := Vector3(cos(a), 0, sin(a)) * 0.06
		var side := Vector3(-sin(a), 0, cos(a)) * 0.05
		var tip := base * 3.0 + Vector3(0, r.randf_range(0.35, 0.6), 0)
		for v in [[base - side, Color("#3E7A2A")], [base + side, Color("#3E7A2A")], [tip, Color("#A8D86A")]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	st.set_material(mat)
	return st.commit()

func _scatter_mesh(mesh: Mesh, count: int, scale: float, r: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var xf: Array[Transform3D] = []
	while xf.size() < count:
		var p := Vector3(r.randf_range(-40, 40), 0, r.randf_range(-40, 46))
		if _free_spot(p): xf.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * scale * r.randf_range(0.6, 1.4)), p))
	mm.instance_count = xf.size()
	for i in xf.size(): mm.set_instance_transform(i, xf[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = 32.0        # grass far from the camera isn't drawn
	inst.visibility_range_end_margin = 4.0
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(inst)

## The village square: fountain, lamp posts, flower beds, market clutter.
func _square() -> void:
	var f := MeshInstance3D.new()
	var basin := CylinderMesh.new()
	basin.top_radius = 1.8
	basin.bottom_radius = 2.0
	basin.height = 0.6
	f.mesh = basin
	f.position = Vector3(0, 0.3, -5.5)
	f.material_override = _mat(Color("#C9C2B4"))
	add_child(f)
	_pond(Vector3(0, 0.55, -5.5), 1.55)
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.35
	cm.height = 1.8
	col.mesh = cm
	col.position = Vector3(0, 1.2, -5.5)
	col.material_override = _mat(Color("#B5AC9C"))
	add_child(col)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 1.2
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0, 0.6, -5.5)
	add_child(body)
	for p in [Vector3(-4, 0, -2), Vector3(4, 0, -2), Vector3(-12, 0, -2), Vector3(12, 0, -2), Vector3(-11, 0, 4.5), Vector3(11, 0, 4.5)]:
		_lamp(p)
	for p in [Vector3(-8, 0, -1.2), Vector3(8, 0, -1.2), Vector3(-4.5, 0, -12.5), Vector3(4.5, 0, -12.5)]:
		_flowerbed(p)
	for c in [["village/crate_A_big.gltf", Vector3(-11, 0, -4)], ["village/sack.gltf", Vector3(-10.2, 0, -3.3)], ["village/barrel.gltf", Vector3(-18, 0, -5)], ["village/crate_open.gltf", Vector3(-17.5, 0, -3.8)]]:
		_place(c[0], 6.0, c[1], randf() * 90.0, true)

func _lamp(at: Vector3) -> void:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.1
	pm.height = 2.6
	post.mesh = pm
	post.position = at + Vector3(0, 1.3, 0)
	post.material_override = _mat(Color("#4A2F1F"))
	add_child(post)
	var bulb := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.22
	bm.height = 0.44
	bulb.mesh = bm
	bulb.position = at + Vector3(0, 2.7, 0)
	var glow := _mat(Color("#FFE29A"))
	glow.emission_enabled = true
	glow.emission = Color("#FFD27A")
	glow.emission_energy_multiplier = 1.5
	bulb.material_override = glow
	add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = Color("#FFC870")
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.position = at + Vector3(0, 2.6, 0)
	add_child(light)
	day.lamps.append({"mat": glow, "light": light})

func _flowerbed(at: Vector3) -> void:
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.3, 1.0)
	bed.mesh = bm
	bed.position = at + Vector3(0, 0.15, 0)
	bed.material_override = _mat(Color("#7A4E2D"))
	add_child(bed)
	var colors := [Color("#E83A5F"), Color("#F2B84B"), Color("#C97BB5"), Color("#FFFFFF"), Color("#F07F1E")]
	for k in 10:
		var fl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.2
		fl.mesh = sm
		fl.position = at + Vector3(-1.0 + (k % 5) * 0.5, 0.42, -0.25 + (k / 5) * 0.5)
		fl.material_override = _mat(colors[k % colors.size()], 0.6)
		add_child(fl)

## Scatters one model's mesh many times as a MultiMesh, avoiding paths, fields and the square.
func _scatter(path: String, count: int, scale: float, r: RandomNumberGenerator, keep_out := 6.0) -> void:
	var src: Node = (load("res://assets/3d/" + path) as PackedScene).instantiate()
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mi.mesh
	var xf: Array[Transform3D] = []
	while xf.size() < count:
		var p := Vector3(r.randf_range(-40, 40), 0, r.randf_range(-40, 46))
		if not _free_spot(p): continue
		xf.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * scale * r.randf_range(0.7, 1.3)), p))
	mm.instance_count = xf.size()
	for i in xf.size(): mm.set_instance_transform(i, xf[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = 32.0        # grass far from the camera isn't drawn
	inst.visibility_range_end_margin = 4.0
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(inst)
	src.free()

## Instances a model; `solid` adds a box collider from its bounds so you can't walk through it.
func _place(path: String, scale: float, pos: Vector3, yaw: float, solid := false, parent: Node3D = null) -> Node3D:
	var ps: PackedScene = load("res://assets/3d/" + path) if ResourceLoader.exists("res://assets/3d/" + path) else null
	if ps == null: push_warning("missing model " + path)
	var n: Node3D = ps.instantiate() if ps else Node3D.new()
	n.scale = Vector3.ONE * scale
	n.position = pos
	n.rotation_degrees.y = yaw
	(parent if parent else self).add_child(n)
	if solid:   # box collider from the (scaled) bounds, same position/rotation as the model
		var box := _bounds(n)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(box.size.x * 0.85, 0.4), maxf(box.size.y, 1.0), maxf(box.size.z * 0.85, 0.4))
		cs.shape = shape
		cs.position = box.get_center()
		body.add_child(cs)
		body.position = pos
		body.rotation_degrees.y = yaw
		(parent if parent else self).add_child(body)
	return n

## Local-space AABB of every mesh under `n` (in n's parent scale).
func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack := [[n, Transform3D.IDENTITY.scaled(n.scale)]]
	while not stack.is_empty():
		var cur = stack.pop_back()
		var node: Node = cur[0]
		var t: Transform3D = cur[1]
		if node != n and node is Node3D: t = t * (node as Node3D).transform
		if node is MeshInstance3D and node.mesh:
			var b: AABB = t * node.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in node.get_children(): stack.append([c, t])
	return out

# ------------------------------------------------------------------ dynamic world

func rebuild() -> void:
	for c in _dynamic.get_children(): c.queue_free()
	day.lamps = day.lamps.filter(func(l): return l.has("mat"))   # building lights are rebuilt below
	_plots.clear()
	_interact.clear()
	var m: GameModel = Game.model
	# the inn + market are always there
	_building("inn", true)
	_place(MARKET[0], MARKET[1], MARKET[2], MARKET[3], true, _dynamic)
	_add("Open market", MARKET[2] + Vector3(2, 0, 4), 4.0, func(): Screens.market(main), "market")
	for id in BUILDINGS:
		if id != "inn": _building(id, m.owns_building(id))
	_terrace(m)
	_animals(m)
	_place("farm/S_Silo.glb", 0.55, STOREHOUSE, 0, true, _dynamic)
	_place("village/crate_A_big.gltf", 6.0, STOREHOUSE + Vector3(2.2, 0, 1.6), 20, false, _dynamic)
	_place("village/sack.gltf", 6.0, STOREHOUSE + Vector3(-2.0, 0, 1.8), 0, false, _dynamic)
	_add("Enter the storehouse", STOREHOUSE + Vector3(0, 0, 3.2), 2.8, func(): main.enter_interior("storehouse", STOREHOUSE + Vector3(0, 0, 3.5)), "barn")
	# fields
	for p in int(m.s["parcels"]):
		_parcel(p, true)
	for i in m.s["plots"].size():
		var n := Node3D.new()
		n.position = plot_pos(i)
		var soil := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(PLOT - 0.25, 0.18, PLOT - 0.25)
		soil.mesh = bm
		soil.position.y = 0.05
		soil.material_override = _mat(Color("#7A4E2D"))
		n.add_child(soil)
		for k in 3:   # furrows
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(PLOT - 0.5, 0.05, 0.12)
			f.mesh = fm
			f.position = Vector3(0, 0.16, -0.6 + k * 0.6)
			f.material_override = _mat(Color("#5E3A20"))
			n.add_child(f)
		var tl := Label3D.new()
		tl.name = "Timer"
		tl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tl.position.y = 2.2
		tl.font_size = 28
		tl.pixel_size = 0.004
		tl.no_depth_test = true
		tl.outline_size = 8
		tl.outline_modulate = UI.INK
		n.add_child(tl)
		_dynamic.add_child(n)
		_plots.append(n)
		var idx: int = i
		_add(func(): return _plot_label(idx), n.position, PLOT * 0.75, func(): main.plot_action(idx), "farm")
		_interact[-1]["plot"] = idx
		_refresh_plot(i)
	var next := m.next_parcel()
	if not next.is_empty():
		_parcel(int(m.s["parcels"]), false)
		var sign_pos := parcel_origin(int(m.s["parcels"])) + Vector3(PLOT * 1.5, 0, -0.8)
		_add(func(): return ("Buy this field · %d" % int(next["cost"])) if m.is_unlocked(next["unlock_level"]) else "Field unlocks at level %d" % int(next["unlock_level"]),
			sign_pos, 3.5, func(): main.buy_field(), "coin")
	# NPC chats
	for id in NPCS:
		var who := short_name(id)
		var opens: String = NPCS[id][3]
		_add("Talk to " + who, NPCS[id][2], 2.6, func(): main.talk_to(id, opens), "friends")

const TABLES := [Vector3(-6, 0, -6.5), Vector3(6, 0, -6.5), Vector3(-9.5, 0, -10.5), Vector3(9.5, 0, -10.5), Vector3(-3, 0, -3.5), Vector3(3, 0, -3.5)]

const ANIMAL_MODELS := {"cow": ["animals/SK_Cow.glb", 0.22], "sheep": ["animals/SK_Sheep.glb", 0.3], "goat": ["animals/SK_Llama.glb", 0.25]}

## Every adopted animal wanders in front of its home; a "!" floats over ones with goods ready.
func _animals(m: GameModel) -> void:
	var now := Game.now()
	for h in m.s["animals"]:
		var home: Vector3 = BUILDINGS[h][2] + Vector3(0, 0, 5.5).rotated(Vector3.UP, deg_to_rad(BUILDINGS[h][3]))
		for i in m.s["animals"][h].size():
			var kind: String = m.s["animals"][h][i]["type"]
			var a: Node3D = _chicken() if kind == "chicken" else _place(ANIMAL_MODELS[kind][0], ANIMAL_MODELS[kind][1], Vector3.ZERO, 0, false, _dynamic)
			if a.get_parent() == null: _dynamic.add_child(a)
			var start := home + Vector3(-2.0 + (i % 3) * 2.0, 0, (i / 3) * 1.8)
			a.position = start
			_wander(a, start)
			if m.animal_state(h, i, now) == "ready":
				var mark := Label3D.new()
				mark.text = "!"
				mark.font_size = 96
				mark.modulate = UI.WHEAT
				mark.outline_size = 14
				mark.outline_modulate = UI.INK
				mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				mark.position = Vector3(0, 2.0 / a.scale.y, 0)
				a.add_child(mark)

func _wander(a: Node3D, start: Vector3) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(start.x * 100 + start.z)
	var tw := a.create_tween().set_loops()
	for k in 4:
		var to := start + Vector3(r.randf_range(-1.6, 1.6), 0, r.randf_range(-1.2, 1.2))
		tw.tween_callback(func(): a.look_at(Vector3(to.x, a.position.y, to.z) + (to - a.position) * 0.01 + Vector3(0.001, 0, 0), Vector3.UP, true))
		tw.tween_property(a, "position", to, r.randf_range(2.5, 4.5)).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(r.randf_range(1.0, 3.0))

## A small low-poly hen built from primitives (there's no CC0 chicken in our packs).
func _chicken() -> Node3D:
	var n := Node3D.new()
	var parts := [[SphereMesh, Vector3(0, 0.32, 0), Vector3(0.5, 0.42, 0.62), Color("#FFFFFF")],
		[SphereMesh, Vector3(0, 0.62, 0.22), Vector3(0.3, 0.32, 0.3), Color("#FFFFFF")],
		[SphereMesh, Vector3(0, 0.82, 0.22), Vector3(0.1, 0.14, 0.16), Color("#E5483B")],
		[PrismMesh, Vector3(0, 0.62, 0.42), Vector3(0.1, 0.1, 0.14), Color("#F2B84B")],
		[SphereMesh, Vector3(0, 0.42, -0.32), Vector3(0.22, 0.3, 0.16), Color("#F3EEE2")]]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0].new()
		mi.position = p[1]
		mi.scale = p[2]
		mi.material_override = _mat(p[3], 0.7)
		n.add_child(mi)
	for x in [-0.1, 0.1]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.03
		em.height = 0.06
		eye.mesh = em
		eye.position = Vector3(x, 0.68, 0.36)
		eye.material_override = _mat(UI.INK, 0.3)
		n.add_child(eye)
	n.scale = Vector3.ONE * 1.4
	return n

## Café tables in front of the inn: one per unlocked table, with the waiting guests seated.
func _terrace(m: GameModel) -> void:
	for t in mini(int(m.rep_tier()["tables"]), 2):
		var at: Vector3 = TABLES[t]
		_place("restaurant/table_round_A.gltf", 0.55, at, 0, true, _dynamic)
		_place("restaurant/chair_A.gltf", 1.0, at + Vector3(0, 0, 1.2), 180, false, _dynamic)


func _building(id: String, owned: bool) -> void:
	var b: Array = BUILDINGS[id]
	var info: Dictionary = GameData.buildings().get(id, {})
	if owned:
		var n := _place(b[0], b[1], b[2], b[3], true, _dynamic)
		var door: Vector3 = b[2] + Vector3(0, 0, 5).rotated(Vector3.UP, deg_to_rad(b[3]))
		var label := "Enter the inn" if id == "inn" else ("Enter the %s" % info.get("name", id) if info.get("kind") == "workshop" else "Visit the %s" % info.get("name", id))
		_add(label, door, 3.5, func(): main.open_building(id, door), "inn" if id == "inn" else "shop")
		var warm := OmniLight3D.new()          # windows glow after dusk
		warm.light_color = Color("#FFB860")
		warm.light_energy = 2.2
		warm.omni_range = 8.0
		warm.position = b[2] + Vector3(0, 2.2, 3.2).rotated(Vector3.UP, deg_to_rad(b[3]))
		_dynamic.add_child(warm)
		day.lamps.append({"light": warm})
		_ready_marker(n, id)
	elif Game.model.is_unlocked(info.get("unlock_level", 99)):
		var site := Node3D.new()
		site.position = b[2]
		_dynamic.add_child(site)
		_place("village/crate_open.gltf", 6.0, Vector3(-1, 0, 0), 20, false, site)
		_place("village/sack.gltf", 6.0, Vector3(1, 0, 0.5), 0, false, site)
		var tag := Label3D.new()
		tag.text = "%s\n%d coins" % [info.get("name", id), int(info["levels"][0]["cost"])]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position.y = 2.5
		tag.font_size = 40
		tag.outline_size = 10
		tag.outline_modulate = UI.INK
		site.add_child(tag)
		_add("Build %s · %d" % [info.get("name", id), int(info["levels"][0]["cost"])], b[2], 3.5, func(): main.build_here(id), "shop")

## A bouncing star over buildings with finished goods.
func _ready_marker(n: Node3D, id: String) -> void:
	var star := Label3D.new()
	star.text = "★"
	star.font_size = 120
	star.modulate = UI.WHEAT
	star.outline_size = 16
	star.outline_modulate = UI.INK
	star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	star.position = Vector3(0, 9, 0) / n.scale.x
	star.name = "Ready"
	star.visible = false
	star.set_meta("building", id)
	n.add_child(star)
	var tw := star.create_tween().set_loops()
	tw.tween_property(star, "position:y", star.position.y + 0.3 / n.scale.x * 3, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(star, "position:y", star.position.y, 0.6).set_trans(Tween.TRANS_SINE)

func _parcel(p: int, owned: bool) -> void:
	var o := parcel_origin(p)
	var size := Vector3(PLOT * 3, 0, PLOT * 2)
	if not owned:
		var meadow := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size.x, size.z)
		meadow.mesh = pm
		meadow.position = o + size / 2 + Vector3(0, 0.02, 0)
		meadow.material_override = _mat(Color("#A8D673"))
		_dynamic.add_child(meadow)
		var sign := Label3D.new()
		sign.text = "FOR SALE"
		sign.font_size = 72
		sign.outline_size = 16
		sign.modulate = UI.WHEAT
		sign.outline_modulate = UI.INK
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.position = o + Vector3(size.x / 2, 2.2, -0.8)
		_dynamic.add_child(sign)
		_place("village/crate_A_big.gltf", 6.0, o + Vector3(size.x / 2, 0, -0.8), 0, false, _dynamic)
	# wooden fence around the field (gap at the front for the gate)
	var seg := 2.3
	for side in 2:
		for k in int(size.x / seg):
			_place("village/fence_wood_straight.gltf", 2.0, o + Vector3(seg * (k + 0.5), 0, -0.4 if side == 0 else size.z + 0.4), 90, false, _dynamic)
	for k in int(size.z / seg):
		_place("village/fence_wood_straight.gltf", 2.0, o + Vector3(-0.4, 0, seg * (k + 0.5)), 0, false, _dynamic)

func parcel_origin(p: int) -> Vector3:
	return FIELD_ORIGIN + Vector3((p % 2) * PARCEL_STEP.x, 0, (p / 2) * PARCEL_STEP.z)

func plot_pos(i: int) -> Vector3:
	var per := GameModel.plots_per_parcel()
	var k := i % per
	return parcel_origin(i / per) + Vector3(PLOT * (0.5 + k % 3), 0, PLOT * (0.5 + k / 3))

# ------------------------------------------------------------------ crops

func _plot_label(i: int) -> String:
	var m: GameModel = Game.model
	var p: Dictionary = m.s["plots"][i]
	if p["crop"] == "":
		return "Plant %s" % GameData.item_name(main.seed) if main.seed != "" else "Plant seeds"
	if m.plot_remaining(i, Game.now()) <= 0.0:
		return "Harvest %s" % GameData.item_name(p["crop"])
	return "%s · %s left" % [GameData.item_name(p["crop"]), UI.fmt_time(m.plot_remaining(i, Game.now()))]

func _refresh_plot(i: int) -> void:
	if i < 0 or i >= _plots.size(): return
	var n := _plots[i]
	var old := n.get_node_or_null("Crop")
	var m: GameModel = Game.model
	var p: Dictionary = m.s["plots"][i]
	var stage := ""
	if p["crop"] != "":
		var prog := m.plot_progress(i, Game.now())
		var st := 4 if prog >= 1.0 else clampi(int(prog * 3.0) + 1, 1, 3)
		stage = "%s_%d" % [GameData.crops()[p["crop"]]["model"], st]
	if old and old.get_meta("stage", "") == stage: return
	if old: old.queue_free()
	(n.get_node("Timer") as Label3D).text = ""
	if stage == "": return
	var crop := Node3D.new()
	crop.name = "Crop"
	crop.set_meta("stage", stage)
	n.add_child(crop)
	var sc := CROP_SCALE * (0.55 if stage.begins_with("BushBerries") or stage.begins_with("Pumpkin") or stage.begins_with("Watermelon") else 1.0)
	for k in 4:   # four plants per plot
		_place("crops/S_%s.glb" % stage, sc, Vector3(-0.5 + (k % 2), 0.12, -0.5 + (k / 2)), k * 90.0, false, crop)
	_cull(crop, 45.0)
	crop.scale = Vector3(0.3, 0.3, 0.3)
	crop.create_tween().tween_property(crop, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if stage.ends_with("_4"):
		var glow := OmniLight3D.new()
		glow.light_color = UI.WHEAT
		glow.light_energy = 0.6
		glow.omni_range = 2.0
		glow.position.y = 1.0
		crop.add_child(glow)

func harvest_fx(i: int, crop: String) -> void:
	var at := plot_pos(i) + Vector3(0, 1, 0)
	_pop_produce(plot_pos(i), crop)
	var p := CPUParticles3D.new()
	p.position = at
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	p.mesh = mesh
	var mat := _mat(Color(GameData.items()[crop]["color"]))
	mat.emission_enabled = true
	mat.emission = Color(GameData.items()[crop]["color"]) * 0.5
	p.material_override = mat
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var screen := cam.unproject_position(at)
		for k in 3: main.hud.fly(UI.item_tex(crop), screen, "barn")
		main.hud.fly(UI.icon("xp"), screen, "xp")

## The harvested produce jumps out of the soil, spins, and arcs into the farmer's arms.
func _pop_produce(at: Vector3, crop: String) -> void:
	var fam: String = GameData.crops()[crop]["model"]
	var path := "crops/S_%sCrop.glb" % fam
	if not ResourceLoader.exists("res://assets/3d/" + path): path = "crops/S_%s_4.glb" % fam
	for k in 3:
		var n := _place(path, 1.2, at + Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)), randf() * 360.0)
		var up := n.position + Vector3(0, 1.8 + k * 0.3, 0)
		var tw := n.create_tween()
		tw.tween_property(n, "position", up, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(k * 0.06)
		tw.parallel().tween_property(n, "rotation:y", n.rotation.y + TAU, 0.5)
		tw.tween_method(func(t: float): n.position = up.lerp(player.global_position + Vector3(0, 1.2, 0), t); n.scale = Vector3.ONE * 1.2 * (1.0 - t * 0.8), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(n.queue_free)

# ------------------------------------------------------------------ interaction

func _add(label, pos: Vector3, radius: float, act: Callable, icon: String) -> void:
	_interact.append({"label": label, "pos": pos, "radius": radius, "act": act, "icon": icon})

func _process(dt: float) -> void:
	if player == null: return
	_clock += dt
	if _clock > 0.5:
		_clock = 0.0
		for i in _plots.size(): _refresh_plot(i)
		_timers()
		_ready_markers()
	# nearest interactable in range
	var best := {}
	var best_d := INF
	var pp := player.global_position
	_inside_clock += dt
	if interiors.kind != "" and _inside_clock > 5.0:   # refresh timers on interior signs
		_inside_clock = 0.0
		interiors.build()
	for it in (_interact_in if interiors.kind != "" else _interact):
		var d := Vector2(pp.x - it["pos"].x, pp.z - it["pos"].z).length()
		if d < it["radius"] and d < best_d:
			best = it
			best_d = d
	var label := ""
	if not best.is_empty():
		label = best["label"].call() if best["label"] is Callable else best["label"]
	if best.get("pos") != _current.get("pos") or label != _current.get("_last", ""):
		_current = best
		_current["_last"] = label
		action_changed.emit(label, best.get("icon", ""))
	_sweep()
	# NPCs turn to face you when you're close
	for id in _npcs:
		var c: Node3D = _npcs[id]
		if c.global_position.distance_to(pp) < 6.0:
			var to := pp - c.global_position
			c.rotation.y = lerp_angle(c.rotation.y, atan2(-to.x, -to.z), dt * 5.0)

func act() -> void:
	if not _current.is_empty():
		_current["act"].call()

## While the action button is held, act on each new plot you walk onto (sweep planting/harvesting).
var sweeping := false
var _last_swept := -1

func _sweep() -> void:
	if not sweeping or _current.is_empty() or not _current.has("plot"): return
	var i: int = _current["plot"]
	if i == _last_swept: return
	var p: Dictionary = Game.model.s["plots"][i]
	var ready: bool = p["crop"] != "" and Game.model.plot_remaining(i, Game.now()) <= 0.0
	if p["crop"] == "" and main.seed != "" or ready:
		_last_swept = i
		main.plot_action(i)

func current_target() -> Vector3:
	return _current.get("pos", player.global_position)

func _timers() -> void:
	var m: GameModel = Game.model
	var now := Game.now()
	for i in _plots.size():
		var lbl: Label3D = _plots[i].get_node("Timer")
		var rem := m.plot_remaining(i, now)
		lbl.text = UI.fmt_time(rem) if m.s["plots"][i]["crop"] != "" and rem > 0.0 and player.global_position.distance_to(_plots[i].position) < 14.0 else ""

func _ready_markers() -> void:
	var now := Game.now()
	for n in _dynamic.get_children():
		var star := n.get_node_or_null("Ready")
		if star: star.visible = Game.model.building_has_ready(star.get_meta("building"), now)

## "Dr. Juniper Hale" -> "Juniper", "Basil Okafor" -> "Basil".
static func short_name(id: String) -> String:
	var parts: PackedStringArray = GameData.characters()[id]["name"].split(" ")
	return parts[1] if parts[0].ends_with(".") and parts.size() > 1 else parts[0]

func npc(id: String) -> Character3D:
	return _npcs.get(id)
