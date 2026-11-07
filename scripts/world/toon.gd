## One art style for every pack: KayKit, Quaternius and procedural meshes all get toon
## diffuse, a soft rim light and (untextured colours only) one shared palette grade.
## Materials are changed in place, once, so shared materials stay batched.
class_name Toon
extends RefCounted

const RIM := 0.35
const RIM_TINT := 0.6

## Connect once: every mesh that enters the tree from then on is styled.
static func watch(tree: SceneTree) -> void:
	tree.node_added.connect(style_node)

static func style_node(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_style(mi.material_override)
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				_style(mi.get_surface_override_material(i))
				_style(mi.mesh.surface_get_material(i))
	elif n is MultiMeshInstance3D:
		var mm := n as MultiMeshInstance3D
		_style(mm.material_override)
		if mm.multimesh and mm.multimesh.mesh:
			for i in mm.multimesh.mesh.get_surface_count(): _style(mm.multimesh.mesh.surface_get_material(i))

static func _style(m: Material) -> void:
	if not m is StandardMaterial3D or m.has_meta("toon"): return
	var s := m as StandardMaterial3D
	s.set_meta("toon", true)
	if s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: return
	s.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	s.specular_mode = BaseMaterial3D.SPECULAR_TOON
	s.roughness = maxf(s.roughness, 0.8)
	s.metallic = 0.0
	s.rim_enabled = s.cull_mode != BaseMaterial3D.CULL_DISABLED   # foliage: up-normals make rim glow white
	s.rim = RIM
	s.rim_tint = RIM_TINT
	if s.albedo_texture == null and not s.vertex_color_use_as_albedo:
		s.albedo_color = grade(s.albedo_color)

## The shared palette: lift darks, calm loud saturation, nudge hues a touch warmer,
## so Quaternius' deep flat colours sit next to KayKit's bright pastel atlas.
static func grade(c: Color) -> Color:
	var h := c.h
	if c.s > 0.05:   # warm shift: blues/greens drift 3% toward yellow, never past it
		h = fposmod(h - 0.03 * sin(h * TAU * 0.5), 1.0) if h > 0.17 and h < 0.7 else h
	var s := lerpf(c.s, 0.55, 0.3) if c.s > 0.05 else c.s
	var v := lerpf(c.v, 1.0, 0.18)
	return Color.from_hsv(h, s, v, c.a)
