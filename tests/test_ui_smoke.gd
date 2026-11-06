## Drives the real main scene headless: tap a plot, plant, harvest, open the barn.
extends TestCase

func test_plant_and_harvest_through_ui() -> bool:
	var game: Node = tree.root.get_node("Game")
	game.set_model(GameModel.new_game(game.now()))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main._on_plot(0)
	truthy(main.hud.sheet_open(), "seed picker opens on empty plot")
	main.hud.close_sheet()
	main.start_planting("wheat")
	main._on_plot(0)
	eq(game.model.s["plots"][0]["crop"], "wheat", "planted via planting mode")
	game.model.s["plots"][0]["ready_at"] = 0.0
	main._on_plot(0)
	eq(game.model.s["plots"][0]["crop"], "", "harvested")
	eq(game.model.count("wheat"), 6, "wheat in barn")
	for screen in ["barn", "shop", "settings", "market", "orders", "friends", "trophy", "event"]:
		main._on_nav(screen)
		truthy(main.hud.sheet_open(), screen + " opens")
	main._on_nav("inn")
	truthy(main.inn.visible, "inn view opens")
	game.model.tick(game.now())
	game.model.add_items({"carrot_stew": 1})
	main.inn.refresh()
	eq(game.model.serve_guest(0), "", "serve tutorial guest")
	main._on_nav("inn")
	truthy(not main.inn.visible, "back to farm")
	game.model.s["coins"] = 1000
	game.model.s["level"] = 4
	game.model.tick(game.now())
	eq(game.model.build("mill"), "", "build mill")
	main._on_building("mill")
	truthy(main.hud.sheet_open(), "mill sheet opens")
	game.model.s["level"] = 10
	game.model.s["coins"] = 5000
	eq(game.model.build("coop"), "", "build coop")
	eq(game.model.buy_animal("coop", game.now()), "", "adopt hen")
	await tree.process_frame
	main._on_building("coop")
	truthy(main.hud.sheet_open(), "coop sheet opens")
	Screens.shop(main, "farm")
	Screens.shop(main, "style")
	Screens.market(main, "online")
	Screens.avatar_editor(main)
	Screens.cast(main)
	truthy(main.hud.sheet_open(), "cast opens")
	main.hud.close_sheet()
	main.queue_free()
	await tree.process_frame
	return true
