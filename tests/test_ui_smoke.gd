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
	for screen in ["barn", "shop", "settings", "market", "orders", "friends", "trophy", "event"]:
		main._on_nav(screen)
		truthy(main.hud.sheet_open(), screen + " opens")
	game.model.tick(game.now())
	game.model.add_items({"carrot_stew": 1}, true)
	var coins: int = game.model.s["coins"]
	main.serve_at_table(0)
	truthy(game.model.s["coins"] > coins, "served the terrace guest in the world")
	main.show_inn()
	truthy(main.inn.visible, "inn view opens")
	main.show_farm()
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
