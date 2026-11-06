# Headless test runner. Run with:
#   godot --headless --path . --script res://tests/test_runner.gd
# Each test_*.gd file under res://tests/ extends TestCase; every method that
# starts with "test_" is run and must return true (an aborted test returns null
# and is counted as a failure).
extends SceneTree

func _initialize() -> void:
	await process_frame  # let autoloads (Game, Sfx) enter the tree
	root.get_node("Game").save_path = "user://test_save.json"  # never touch the player's save
	var passed := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_runner.gd":
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var suite: TestCase = script.new()
		suite.tree = self
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures.clear()
			suite.setup()
			var ok = await suite.call(name)
			if ok == true and suite.failures.is_empty():
				passed += 1
			else:
				failed += 1
				push_error("FAIL %s::%s %s" % [f, name, ", ".join(suite.failures)])
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
