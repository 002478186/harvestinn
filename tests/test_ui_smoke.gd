## Drives the real 3D main scene headless: create a farmer, buy a field, plant, harvest, open screens.
extends TestCase

func test_3d_core_loop_through_the_game_scene() -> bool:
	var game: Node = tree.root.get_node("Game")
	game.set_model(GameModel.new_game(game.now()))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	truthy(main.hud.sheet_open(), "character creator opens for a new player")
	eq(str(game.model.s["avatar"]["model"]), "Rogue_Hooded", "default look picked")
	main.hud.close_sheet()
	eq(game.model.s["plots"].size(), 0, "no land yet")
	main.buy_field()
	eq(game.model.s["plots"].size(), 6, "bought the first field")
	await tree.process_frame
	main.plot_action(0)
	truthy(main.hud.sheet_open(), "first plant asks for a seed")
	main.choose_seed("wheat", 0)
	eq(game.model.s["plots"][0]["crop"], "wheat", "planted wheat")
	main.plot_action(1)
	eq(game.model.s["plots"][1]["crop"], "wheat", "re-plants the chosen seed")
	game.model.s["plots"][0]["ready_at"] = 0.0
	main.plot_action(0)
	eq(game.model.s["plots"][0]["crop"], "", "harvested")
	eq(game.model.count("wheat"), 6, "wheat in barn")
	main.player.global_position = main.world.plot_pos(1)
	await tree.process_frame
	await tree.process_frame
	truthy(main.hud.action_btn.text.contains("Wheat"), "standing on a plot offers its action: " + main.hud.action_btn.text)
	for screen in ["barn", "shop", "settings", "market", "orders", "friends", "trophy", "event", "journal"]:
		main._on_nav(screen)
		truthy(main.hud.sheet_open(), screen + " opens")
	game.model.tick(game.now())
	game.model.add_items({"carrot_stew": 1}, true)
	var coins: int = game.model.s["coins"]
	main.serve_at_table(0)
	truthy(game.model.s["coins"] > coins, "served the terrace guest in the world")
	main.world.interiors.enter("inn", Vector3.ZERO)
	await tree.process_frame
	truthy(main.world.interiors.get_child_count() > 20, "3D inn interior built")
	main.world.interiors.enter("mill", Vector3.ZERO) if game.model.owns_building("mill") else null
	main.world.interiors.enter("storehouse", Vector3.ZERO)
	truthy(main.world._interact_in.size() >= 2, "storehouse interactions")
	main.world.interiors.leave()
	game.model.s["level"] = 10
	game.model.s["coins"] = 5000
	main.build_here("coop")
	truthy(game.model.owns_building("coop"), "built the coop in the world")
	eq(game.model.buy_animal("coop", game.now()), "", "adopt hen")
	main.open_building("coop")
	truthy(main.hud.sheet_open(), "coop sheet opens")
	main.talk_to("merchant", "market")
	Screens.character_creator(main)
	Screens.cast(main)
	main.hud.close_sheet()
	main.queue_free()
	await tree.process_frame
	return true

func test_walk_up_care_and_stall_selling() -> bool:
	var game: Node = tree.root.get_node("Game")
	game.set_model(load("res://scripts/main.gd").demo_farm(game.now()))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var m: GameModel = game.model
	var h := "coop"
	var hungry := 0
	m.s["animals"][h][hungry]["cycle_end"] = 0.0
	main.tend_animal(h, hungry, main.world)
	eq(m.animal_state(h, hungry, game.now()), "producing", "walk-up feeds the hen")
	m.s["animals"][h][hungry]["cycle_end"] = 1.0
	var eggs := m.count("egg")
	main.tend_animal(h, hungry, main.world)
	truthy(m.count("egg") > eggs, "walk-up collects eggs")
	var wheat := m.count("wheat")
	var coins: int = m.s["coins"]
	main.sell_crate("wheat", Vector3.ZERO)
	eq(m.count("wheat"), wheat - 10, "a crate sells a batch of ten")
	truthy(m.s["coins"] > coins, "coins paid")
	main.queue_free()
	await tree.process_frame
	return true

func test_select_plots_and_plant_a_mix() -> bool:
	var game: Node = tree.root.get_node("Game")
	game.set_model(GameModel.new_game(game.now()))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.hud.close_sheet()
	var m: GameModel = game.model
	m.s["coins"] = 500
	main.buy_field()
	await tree.process_frame
	for i in [0, 1, 2]: main.world.toggle_select(i)
	eq(main.world.selected.size(), 3, "three plots selected")
	truthy(main.hud.sel_bar != null, "selection bar shows")
	main.choose_seed("wheat", 0)
	eq([0, 1, 2].map(func(i): return m.s["plots"][i]["crop"]), ["wheat", "wheat", "wheat"], "all three planted with wheat")
	eq(main.world.selected.size(), 0, "selection cleared")
	main.world.select_all_empty()
	eq(main.world.selected, [3, 4, 5], "all empty picks the rest")
	main.choose_seed("carrot", 3)
	eq(m.s["plots"][5]["crop"], "carrot", "the rest get carrots: a mixed field")
	main.world.toggle_select(0)
	main.world.toggle_select(0)
	eq(main.world.selected.size(), 0, "tapping again deselects")
	main.rig.zoom(2.0)
	eq(main.rig.dist, 26.0, "pinch zoom is clamped")
	main.queue_free()
	await tree.process_frame
	return true
