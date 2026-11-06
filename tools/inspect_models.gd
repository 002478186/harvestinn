## godot --headless --path . --script res://tools/inspect_models.gd  -> prints size of every model in assets/3d
extends SceneTree

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var stack := [[n, xf]]
	while not stack.is_empty():
		var cur = stack.pop_back()
		var node: Node = cur[0]
		var t: Transform3D = cur[1]
		if node is Node3D: t = t * (node as Node3D).transform
		if node is MeshInstance3D and node.mesh:
			var b: AABB = t * node.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in node.get_children(): stack.append([c, t])
	return box

func _initialize() -> void:
	for dir in ["characters", "crops", "farm", "animals", "village", "restaurant", "furniture"]:
		for f in DirAccess.get_files_at("res://assets/3d/" + dir):
			if not (f.ends_with(".glb") or f.ends_with(".gltf")): continue
			var ps: PackedScene = load("res://assets/3d/%s/%s" % [dir, f])
			if ps == null: print("FAILED ", f); continue
			var inst := ps.instantiate()
			var b := _aabb(inst, Transform3D.IDENTITY)
			print("%-12s %-36s size=(%.2f, %.2f, %.2f) min_y=%.2f" % [dir, f, b.size.x, b.size.y, b.size.z, b.position.y])
			inst.free()
	quit()
