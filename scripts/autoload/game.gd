## Owns the live GameModel and relays its events, so UI never holds a stale model.
extends Node

signal event(name: String, data: Dictionary)

var model: GameModel

func now() -> float:
	return Time.get_unix_time_from_system()

func _ready() -> void:
	set_model(GameModel.new_game(now()))

func set_model(m: GameModel) -> void:
	model = m
	model.event.connect(func(n, d): event.emit(n, d))
	event.emit("reset", {})

## Dev aid: `godot --path . -- --shot=out.png` saves a screenshot after ~2 s and quits.
func _process(_dt: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") and Engine.get_process_frames() == 120:
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()
