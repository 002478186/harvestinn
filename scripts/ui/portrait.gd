## Character portrait with an idle animation: a gentle breathing bob plus random blinks.
class_name Portrait
extends TextureRect

var _open: Texture2D
var _blink: Texture2D

static func make(character_id: String, size := 160) -> Portrait:
	var p := Portrait.new()
	var file: String = GameData.characters().get(character_id, {}).get("portrait", character_id)
	p._open = UI.tex("res://assets/art/characters/%s.svg" % file)
	p._blink = UI.tex("res://assets/art/characters/%s_blink.svg" % file)
	p.texture = p._open
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.custom_minimum_size = Vector2(size, size)
	return p

func _ready() -> void:
	pivot_offset = custom_minimum_size * Vector2(0.5, 1.0)
	var tw := create_tween().set_loops()
	tw.tween_property(self, "scale", Vector2(1.0, 1.03), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE)
	_blink_loop()

func _blink_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(2.0, 5.0)).timeout
		if not is_inside_tree(): return
		texture = _blink
		await get_tree().create_timer(0.12).timeout
		texture = _open
