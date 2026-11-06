## Non-blocking tutorial card under the HUD; follows Game.model.tutorial_step().
extends PanelContainer

var hud: CanvasLayer
var _pulse: Tween

func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 130
	offset_left = 16
	offset_right = -120

func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.95), 28, 5, UI.WHEAT))
	Game.event.connect(func(n, _d): if n in ["tutorial", "reset", "name"]: _show())
	_show()

func _process(_dt: float) -> void:
	visible = not Game.model.tutorial_step().is_empty() and not hud.sheet_open() and not hud._popup_open

func _show() -> void:
	for c in get_children(): c.queue_free()
	if _pulse: _pulse.kill()
	var st := Game.model.tutorial_step()
	visible = not st.is_empty()
	if not visible: return
	var h := HBoxContainer.new()
	add_child(h)
	h.add_child(Portrait.make(st["speaker"], 84))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_theme_constant_override("separation", 4)
	v.add_child(UI.label(GameData.characters()[st["speaker"]]["name"].split(" ")[0], 20, UI.RED, 600))
	v.add_child(UI.label(Dialogue.text(st["line"], Game.model.s["name"]), 21))
	var row := HBoxContainer.new()
	v.add_child(row)
	if st["goal"] is String:
		var go := UI.button(tr("Continue"), func(): Sfx.play("click"); Game.model.tutorial_tap(), UI.MEADOW)
		go.custom_minimum_size = Vector2(180, 72)
		go.add_theme_font_size_override("font_size", 24)
		row.add_child(go)
	var skip := UI.button(tr("Skip"), func(): Game.model.skip_tutorial(), UI.WOOD_DARK)
	skip.custom_minimum_size = Vector2(110, 72)
	skip.add_theme_font_size_override("font_size", 20)
	row.add_child(skip)
	var target: Control = hud._targets.get(st.get("hint", ""), null)
	if target:
		target.pivot_offset = target.size / 2
		_pulse = target.create_tween().set_loops()
		_pulse.tween_property(target, "scale", Vector2(1.15, 1.15), 0.4)
		_pulse.tween_property(target, "scale", Vector2.ONE, 0.4)
