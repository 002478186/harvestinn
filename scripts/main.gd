## Root: wires the farm world, HUD and screens together. Holds no game rules.
extends Node

var farm: Node2D
var hud: CanvasLayer
var inn: Control
var planting := ""            # crop id while in planting mode

func _ready() -> void:
	if "--demo" in OS.get_cmdline_user_args():
		Game.set_model(demo_farm(Game.now()))
	farm = preload("res://scripts/farm/farm_view.gd").new()
	add_child(farm)
	var inn_layer := CanvasLayer.new()
	inn_layer.layer = 1
	add_child(inn_layer)
	inn = preload("res://scripts/inn/inn_view.gd").new()
	inn.main = self
	inn.visible = false
	inn_layer.add_child(inn)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.layer = 2
	add_child(hud)
	var tut := preload("res://scripts/ui/tutorial_card.gd").new()
	tut.hud = hud
	hud.root.add_child(tut)
	farm.plot_tapped.connect(_on_plot)
	farm.building_tapped.connect(_on_building)
	farm.fly.connect(hud.fly)
	hud.nav.connect(_on_nav)
	Game.event.connect(_on_event)
	Net.cloud_conflict.connect(func(server): Screens.cloud_conflict(self, server))
	for a in OS.get_cmdline_user_args():   # dev aid for screenshots: -- --screen=shop / --screen=b:mill
		if a.begins_with("--screen="):
			var v := a.substr(9)
			if v.begins_with("b:"): Screens.open_building(self, v.substr(2))
			else: Screens.open(self, v)
	var w := Game.welcome
	if float(w.get("away", 0.0)) > 3600.0 or ["crops", "jobs", "animals", "guests", "room_coins"].any(func(k): return int(w.get(k, 0)) > 0) and float(w.get("away", 0.0)) > 60.0:
		Screens.welcome_back(self, Game.welcome)
		Game.welcome = {}

func _on_event(name: String, d: Dictionary) -> void:
	if name == "harvest":
		farm.harvest_feedback(d["index"], d["crop"], d["qty"])
	elif name == "helped":
		hud.toast(tr("%s watered one of your crops!") % d["name"])
	elif name == "level_up":
		Screens.talk(self, Dialogue.for_level_up(d["level"], d["unlocks"]))

func say_error(code: String) -> void:
	Sfx.play("error")
	hud.toast(tr(Screens.ERRORS.get(code, code)))

func _on_plot(i: int) -> void:
	var m := Game.model
	var now := Game.now()
	var p: Dictionary = m.s["plots"][i]
	if p["crop"] == "":
		if planting != "":
			var err := m.plant(i, planting, now)
			if err == "": Sfx.play("plant")
			else: say_error(err)
		else:
			Screens.seed_picker(self, i)
	elif m.plot_remaining(i, now) <= 0.0:
		var err := m.harvest(i, now)
		if err == "": Sfx.play("harvest")
		else: say_error(err)
	else:
		Screens.growing_plot(self, i)

func start_planting(crop: String) -> void:
	planting = crop
	hud.banner(tr("Planting %s: tap empty plots") % tr(GameData.item_name(crop)), func(): planting = "")

func _on_building(id: String) -> void:
	Screens.open_building(self, id)

func _on_nav(screen: String) -> void:
	Screens.open(self, screen)

func show_inn() -> void:
	hud.close_sheet()
	hud.clear_banner()
	planting = ""
	inn.visible = true
	farm.set_process_unhandled_input(false)
	Sfx.play("door")

func show_farm() -> void:
	inn.visible = false
	farm.set_process_unhandled_input(true)
	Sfx.play("door")

## Dev aid (-- --demo): a mid-game farm for screenshots and manual testing.
static func demo_farm(now: float) -> GameModel:
	var m := GameModel.new_game(now)
	m.s["level"] = 22
	m.s["coins"] = 200_000
	m.s["gems"] = 50
	m.skip_tutorial()
	for i in 5: m.buy_land()
	for b in ["mill", "bakery", "jam_kitchen", "coop", "barn_stall", "goat_pen", "sheep_pen", "dairy"]:
		m.build(b)
	m.add_items({"animal_feed": 40, "wheat": 30, "carrot": 20, "potato": 20, "tomato": 12, "strawberry": 12}, true)
	for h in ["coop", "barn_stall", "goat_pen", "sheep_pen"]:
		for k in 2:
			m.buy_animal(h, now)
			m.feed_animal(h, k, now - (3000.0 if k == 0 else 0.0))
	var crops := ["wheat", "carrot", "potato", "tomato", "corn", "strawberry", "sunflower", "pumpkin"]
	for i in m.s["plots"].size():
		m.plant(i, crops[i % crops.size()], now - 400.0 * (i % 4))
	m.queue_recipe("mill", "flour", now)
	m.s["coins"] = 200_000
	m.s["name"] = "Hazel"
	return m
