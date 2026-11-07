## Root of the 3D game: world + player + camera + HUD. Turns world interactions into
## model calls (GameModel holds every rule) and plays the matching character animation.
extends Node

var world: Node3D
var player: CharacterBody3D
var rig: Node3D
var hud: CanvasLayer
var fade := ColorRect.new()
var seed := ""                 # last seed chosen: tapping empty plots re-plants it

func _ready() -> void:
	if "--demo" in OS.get_cmdline_user_args():
		Game.set_model(demo_farm(Game.now()))
	world = preload("res://scripts/world/world.gd").new()
	world.main = self
	add_child(world)
	player = preload("res://scripts/world/player.gd").new()
	player.position = Vector3(0, 0, 1.5)
	world.add_child(player)
	world.player = player
	_dress_player()
	rig = preload("res://scripts/world/camera_rig.gd").new()
	rig.target = player
	world.add_child(rig)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.layer = 2
	add_child(hud)
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(fade)
	var tut := preload("res://scripts/ui/tutorial_card.gd").new()
	tut.hud = hud
	hud.root.add_child(tut)
	world.action_changed.connect(hud.set_action)
	hud.nav.connect(_on_nav)
	Game.event.connect(_on_event)
	Net.cloud_conflict.connect(func(server): Screens.cloud_conflict(self, server))
	for a in OS.get_cmdline_user_args():   # dev: -- --at=x,z,yaw_degrees,dist puts player + camera there
		if a.begins_with("--at="):
			var v := a.substr(5).split(",")
			player.global_position = Vector3(float(v[0]), 0, float(v[1]))
			rig.yaw = deg_to_rad(float(v[2])) if v.size() > 2 else 0.0
			if v.size() > 3: rig.dist = float(v[3])
			rig.global_position = player.global_position
	for a in OS.get_cmdline_user_args():   # dev: -- --inside=inn / mill / storehouse
		if a.begins_with("--inside="):
			world.interiors.enter(a.substr(9), Vector3(0, 0, -9))
	if "--serve" in OS.get_cmdline_user_args():   # dev: serve the first inn guest after 1 s (eat/pay/leave)
		get_tree().create_timer(1.0).timeout.connect(func():
			Game.model.add_items(Game.model.inn()["guests"][0]["order"], true)
			serve_at_table(0))
	for a in OS.get_cmdline_user_args():   # dev aid for screenshots: -- --screen=shop / --screen=b:mill
		if a.begins_with("--screen="):
			var v := a.substr(9)
			if v.begins_with("b:"): Screens.open_building(self, v.substr(2))
			else: Screens.open(self, v)
	if "--fresh" in OS.get_cmdline_user_args():   # dev: a brand-new player who already made a farmer
		Game.set_model(GameModel.new_game(Game.now()))
		Game.model.s["avatar"]["model"] = "Rogue_Hooded"
		Game.welcome = {}
	var clean := "--clean" in OS.get_cmdline_user_args()   # dev: screenshots without popups
	if clean:
		Game.model.s["daily"] = {"last": GameModel.local_day(Game.now()), "streak": 1}
		Game.model.skip_tutorial()
		if str(Game.model.s["avatar"].get("model", "")) == "": Game.model.s["avatar"]["model"] = "Rogue_Hooded"
	if str(Game.model.s["avatar"].get("model", "")) == "" and not "--demo" in OS.get_cmdline_user_args():
		Screens.character_creator(self)
	elif Game.model.tutorial_step().is_empty() and Game.model.daily_index(Game.now()) >= 0:
		Screens.daily(self)
	var w := Game.welcome if not clean else {}
	if float(w.get("away", 0.0)) > 3600.0 or ["crops", "jobs", "animals", "guests", "room_coins"].any(func(k): return int(w.get(k, 0)) > 0) and float(w.get("away", 0.0)) > 60.0:
		Screens.welcome_back(self, w)
	Game.welcome = {}

func _process(_dt: float) -> void:
	hud.clock.text = world.day.clock_text()
	player.stick = hud.joystick.value
	player.frozen = hud.sheet_open() or hud._popup_open
	hud.joystick.visible = not player.frozen
	hud.action_btn.visible = hud.action_btn.visible and not player.frozen and hud.action_btn.text != ""

func _dress_player() -> void:
	var a: Dictionary = Game.model.s["avatar"]
	var model := str(a.get("model", ""))
	player.setup(model if model != "" else "Rogue_Hooded", Color(str(a.get("tint", "#ffffff"))))

func _on_event(name: String, d: Dictionary) -> void:
	match name:
		"harvest": world.harvest_fx(d["index"], d["crop"])
		"avatar", "reset": _dress_player()
		"achievement":
			Sfx.play("level_up")
			hud.toast(tr("Achievement: %s!") % tr(GameData.achievements()[d["id"]]["name"]))
		"tutorial":
			if Game.model.tutorial_step().is_empty(): Screens.daily(self)
		"helped": hud.toast(tr("%s watered one of your crops!") % d["name"])
		"level_up":
			player.do_action("Cheer", player.global_position + Vector3(0, 0, -1))
			Screens.talk(self, Dialogue.for_level_up(d["level"], d["unlocks"]))

func say_error(code: String) -> void:
	Sfx.play("error")
	hud.toast(tr(Screens.ERRORS.get(code, code)))

func _on_nav(screen: String) -> void:
	if screen == "action":
		world.act()
		world._last_swept = world._current.get("plot", -1)
	elif screen == "sweep_on": world.sweeping = true
	elif screen == "sweep_off":
		world.sweeping = false
		world._last_swept = -1
	else: Screens.open(self, screen)

# ------------------------------------------------------------------ farming verbs

func buy_field() -> void:
	var err := Game.model.buy_parcel()
	if err != "":
		say_error(err)
		return
	Sfx.play("build")
	player.do_action("Cheer", world.current_target())
	hud.toast(tr("A new field is yours! Walk onto the soil to plant."))

## Empty plot: plant (asks for a seed the first time). Growing: details. Ready: harvest.
func plot_action(i: int) -> void:
	var m: GameModel = Game.model
	var now := Game.now()
	var p: Dictionary = m.s["plots"][i]
	if p["crop"] == "":
		if seed == "" or not m.is_unlocked(GameData.crops()[seed]["unlock_level"]):
			Screens.seed_picker(self, i)
			return
		var err := m.plant(i, seed, now)
		if err == "no_coins":
			Screens.seed_picker(self, i)
			return
		if err != "":
			say_error(err)
			return
		Sfx.play("plant")
		player.do_action("Use_Item", world.plot_pos(i))
	elif m.plot_remaining(i, now) <= 0.0:
		var err := m.harvest(i, now)
		if err != "":
			say_error(err)
			return
		Sfx.play("harvest")
		player.do_action("PickUp", world.plot_pos(i))
	else:
		Screens.growing_plot(self, i)

func choose_seed(crop: String, plot: int) -> void:
	seed = crop
	hud.close_sheet()
	plot_action(plot)

func build_here(id: String) -> void:
	var err := Game.model.build(id)
	if err != "":
		say_error(err)
		return
	Sfx.play("build")
	player.do_action("Cheer", world.current_target())
	hud.toast(tr("%s built!") % tr(GameData.buildings()[id]["name"]))

func open_building(id: String, door := Vector3.ZERO) -> void:
	player.do_action("Interact", world.current_target())
	var kind: String = GameData.buildings().get(id, {}).get("kind", "")
	if id == "inn" or kind == "workshop": enter_interior(id, door if door != Vector3.ZERO else player.global_position)
	else: Screens.open_building(self, id)

## Fade to black, swap the scene to (or from) an interior, fade back in.
func enter_interior(id: String, door: Vector3) -> void:
	await _fade(1.0)
	world.interiors.enter(id, door)
	Sfx.play("door")
	_fade(0.0)

func leave_interior() -> void:
	await _fade(1.0)
	world.interiors.leave()
	Sfx.play("door")
	_fade(0.0)

func _fade(to: float) -> void:
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", to, 0.22)
	await tw.finished

func act_result(err: String, sfx: String) -> void:
	if err != "": say_error(err)
	else: Sfx.play(sfx)

func talk_to(id: String, opens: String) -> void:
	player.do_action("Interact", world.npc(id).global_position)
	world.npc(id).play("Interact")
	var c: Dictionary = GameData.characters()[id]
	var line: String = c["lines"]["greet"].pick_random()
	hud.queue_popup(func():
		var v: VBoxContainer = hud.popup(c["name"])
		var por := Portrait.make(id, 180)
		v.add_child(por)
		v.move_child(por, 0)
		v.add_child(UI.label(tr(c["role"]), 24, UI.WOOD_DARK, 600))
		v.add_child(UI.label(Dialogue.text(line, Game.model.s["name"]), 28))
		var labels := {"inn": "Show me the inn", "kitchen": "Let's cook", "market": "Let's trade", "shop": "What can I build?", "animals": "Tell me about animals"}
		var go := {"inn": show_inn, "kitchen": func(): Screens.workshop(self, "kitchen"), "market": func(): Screens.market(self),
			"shop": func(): Screens.shop(self), "animals": func(): Screens.animal_guide(self)}
		v.add_child(UI.button(tr(labels[opens]), func(): hud.close_popup(v); go[opens].call(), UI.MEADOW))
		v.add_child(UI.button(tr("Bye!"), func(): hud.close_popup(v), UI.WOOD_DARK)))

## Terrace service: serve straight from your basket, or go cook the missing meal.
func serve_at_table(t: int) -> void:
	var m: GameModel = Game.model
	var g: Dictionary = m.inn()["guests"][t]
	if not m.has_items(g["order"]):
		Screens.workshop(self, "kitchen")
		hud.toast(tr("%s would love: %s") % [GameData.characters()[g["char"]]["name"].split(" ")[0],
			", ".join(g["order"].keys().map(func(k): return "%s ×%d" % [GameData.item_name(k), int(g["order"][k])]))])
		return
	var at: Vector3 = world.interiors.table_pos(g["char"])
	var coins := m.order_value(g["order"])
	var err := m.serve_guest(t)
	if err != "":
		say_error(err)
		return
	world.interiors.serve_guest(g["char"], coins)   # eats, then pays with a coin pop and leaves
	player.do_action("Interact", at)
	Sfx.play("collect")
	var lines: Array = GameData.characters()[g["char"]]["lines"].get("served", [])
	if not lines.is_empty(): hud.toast("“%s”" % Dialogue.text(lines[0]))

func serve_inside(t: int) -> void:
	serve_at_table(t)

func show_inn() -> void:
	hud.close_sheet()
	if world.interiors.kind != "inn":
		var door: Vector3 = world.BUILDINGS["inn"][2] + Vector3(0, 0, 5)
		if world.interiors.kind == "": enter_interior("inn", door)
		else: world.interiors.enter("inn", door)

func show_farm() -> void:
	if world.interiors.kind != "": leave_interior()

## Dev aid (-- --demo): a mid-game farm for screenshots and manual testing.
static func demo_farm(now: float) -> GameModel:
	var m := GameModel.new_game(now)
	m.s["level"] = 22
	m.s["coins"] = 200_000
	m.s["gems"] = 50
	m.skip_tutorial()
	m.s["avatar"]["model"] = "Rogue_Hooded"
	for i in 6: m.buy_parcel()
	for b in ["mill", "bakery", "jam_kitchen", "coop", "barn_stall", "goat_pen", "sheep_pen", "dairy"]:
		m.build(b)
	m.add_items({"animal_feed": 40, "wheat": 30, "carrot": 20, "potato": 20, "tomato": 12, "strawberry": 12}, true)
	for h in ["coop", "barn_stall", "goat_pen", "sheep_pen"]:
		for k in 2:
			m.buy_animal(h, now)
			m.feed_animal(h, k, now - (3000.0 if k == 0 else 0.0))
	var crops := ["wheat", "carrot", "potato", "tomato", "corn", "strawberry", "sunflower", "pumpkin"]
	for i in m.s["plots"].size():
		m.plant(i, crops[i % crops.size()], now - 900.0 * (i % 5))
	m.queue_recipe("mill", "flour", now - 200.0)
	m.queue_recipe("mill", "flour", now)
	m.s["reputation"] = 60
	m.s["owned"].append_array(["furn_rug", "furn_bookshelf", "furn_plant"])
	m.build_room(now)
	m.add_items({"blanket": 1, "pillow": 2}, true)
	m.furnish_room(0, now - 7200.0)
	m.tick(now - 600.0)
	m.tick(now)
	m.s["coins"] = 200_000
	m.s["name"] = "Hazel"
	return m
