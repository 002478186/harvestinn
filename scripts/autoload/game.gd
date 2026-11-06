## Owns the live GameModel, relays its events, and saves it:
## every 30 s, right after important actions, and when the app is backgrounded/closed.
extends Node

signal event(name: String, data: Dictionary)

var save_path := "user://save.json"   # tests point this elsewhere
const AUTOSAVE_SECONDS := 30.0
const SAVE_NOW_EVENTS := ["harvest", "level_up", "building", "served", "sold", "trade", "purchase", "collect", "daily", "achievement_claimed", "event", "outbox", "animal"]

var model: GameModel
var welcome := {}             # offline summary shown once by main.gd
var _save_queued := false

func now() -> float:
	return Time.get_unix_time_from_system()

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	var d := SaveCodec.read(save_path)
	if d.is_empty():
		set_model(GameModel.new_game(now()))
	else:
		set_model(GameModel.new(d))
		welcome = model.offline_summary(float(d["last_seen"]), now())
	var t := Timer.new()
	t.wait_time = AUTOSAVE_SECONDS
	t.autostart = true
	t.timeout.connect(save)
	add_child(t)
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(func(): model.tick(now()))
	add_child(tick)

func set_model(m: GameModel) -> void:
	model = m
	if not model.event.is_connected(_relay):
		model.event.connect(_relay)
	event.emit("reset", {})

func _relay(n: String, d: Dictionary) -> void:
	event.emit(n, d)
	if n in SAVE_NOW_EVENTS and not _save_queued:
		_save_queued = true
		save.call_deferred()

func save() -> void:
	_save_queued = false
	if model == null: return
	model.s["last_seen"] = now()
	var err := SaveCodec.write_atomic(save_path, model.s)
	if err != OK:
		push_error("save failed: %s" % error_string(err))
		event.emit("save_failed", {"error": err})

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_GO_BACK_REQUEST:
			save()
		NOTIFICATION_WM_CLOSE_REQUEST:
			save()
			get_tree().quit()

## Dev aid: `godot --path . -- --shot=out.png` saves a screenshot after ~2 s and quits.
func _process(_dt: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--perf" and Engine.get_process_frames() % 120 == 0 and Engine.get_process_frames() > 0:
			print("PERF fps=%d draw_calls=%d objects=%d prims=%d" % [Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			if Engine.get_process_frames() >= 600: get_tree().quit()
		if a.begins_with("--shot=") and Engine.get_process_frames() == 120:
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()
