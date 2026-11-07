extends TestCase

func test_palette_grade_lifts_darks_and_calms_saturation() -> bool:
	var deep := Toon.grade(Color.from_hsv(0.3, 0.95, 0.3))
	truthy(deep.v > 0.4, "darks lifted")
	truthy(deep.s < 0.9, "loud saturation calmed")
	var grey := Toon.grade(Color(0.5, 0.5, 0.5))
	truthy(grey.s < 0.06, "greys stay grey")
	truthy(Toon.grade(Color.WHITE).v >= 0.99, "white stays white")
	return true

func test_styling_is_in_place_and_once() -> bool:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#336633")
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = m
	Toon.style_node(mi)
	var once := m.albedo_color
	Toon.style_node(mi)
	eq(m.albedo_color, once, "graded only once")
	eq(m.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON, "toon diffuse")
	truthy(m.rim_enabled, "rim light")
	mi.free()
	return true

func test_looks_vary_and_are_stable_per_seed() -> bool:
	var seen := {}
	for i in 30: seen[str(Character3D.random_look(i))] = true
	truthy(seen.size() >= 25, "30 guests, at least 25 different looks (got %d)" % seen.size())
	eq(Character3D.random_look(42), Character3D.random_look(42), "same seed, same look")
	return true
