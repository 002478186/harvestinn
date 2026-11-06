## Root: wires the farm world, HUD and screens together. Holds no game rules.
extends Node

var farm: Node2D
var hud: CanvasLayer
var planting := ""            # crop id while in planting mode

func _ready() -> void:
	farm = preload("res://scripts/farm/farm_view.gd").new()
	add_child(farm)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	farm.plot_tapped.connect(_on_plot)
	farm.building_tapped.connect(_on_building)
	farm.fly.connect(hud.fly)
	hud.nav.connect(_on_nav)
	Game.event.connect(_on_event)

func _on_event(name: String, d: Dictionary) -> void:
	if name == "harvest":
		farm.harvest_feedback(d["index"], d["crop"], d["qty"])

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
