## Brand theme + tiny widget helpers so every screen looks the same.
## Sizes are in viewport units (720 wide ≈ 360 dp, so 96 units ≈ 48 dp).
class_name UI
extends RefCounted

const RED := Color("#C8553D")
const MEADOW := Color("#6BAA4B")
const WHEAT := Color("#F2B84B")
const CREAM := Color("#FBF0D6")
const WOOD := Color("#E9B872")
const WOOD_DARK := Color("#8A5A3B")
const SKY := Color("#8FD3F4")
const INK := Color("#4A2F1F")
const MIN_TAP := 96

static var _theme: Theme
static var _tex: Dictionary = {}

static func font(weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load("res://assets/fonts/%s.ttf" % ("Fredoka" if weight >= 600 else "Nunito"))
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f

static func box(bg: Color, radius := 24, border := 4, border_color := INK) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.set_content_margin_all(16)
	return sb

static func theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new()
	t.default_font = font(700)
	t.default_font_size = 30
	t.set_color("font_color", "Label", INK)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c: Color = {"normal": RED, "hover": RED.lightened(0.1), "pressed": RED.darkened(0.15), "disabled": Color("#B8A89A"), "focus": RED}[st]
		var sb := box(c, 22)
		if st == "focus":
			sb.draw_center = false
			sb.border_color = WHEAT
			sb.set_border_width_all(6)
		t.set_stylebox(st, "Button", sb)
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 32)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#F4EEE8"))
	t.set_stylebox("panel", "PanelContainer", box(CREAM, 32, 6))
	t.set_stylebox("panel", "Panel", box(CREAM, 32, 6))
	t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 16, 4))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("background", "ProgressBar", box(Color("#E7D6B4"), 14, 3))
	t.set_stylebox("fill", "ProgressBar", box(MEADOW, 14, 0))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_stylebox("panel", "TooltipPanel", box(CREAM, 12, 3))
	_theme = t
	return t

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

static func item_tex(id: String) -> Texture2D: return tex("res://assets/art/items/%s.svg" % id)
static func icon(name: String) -> Texture2D: return tex("res://assets/art/ui/%s.svg" % name)

static func label(text: String, size := 30, color := INK, weight := 700) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 700:
		l.add_theme_font_override("font", font(weight))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, on_press: Callable, color := RED, ic: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = ic
	b.expand_icon = true
	b.custom_minimum_size = Vector2(MIN_TAP, MIN_TAP)
	if color != RED:
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := box(color if st != "pressed" else color.darkened(0.15), 22)
			if st == "focus":
				sb.draw_center = false
				sb.border_color = WHEAT
				sb.set_border_width_all(6)
			b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func(): Sfx.play("click"); on_press.call())
	return b

static func icon_rect(t: Texture2D, size := 64) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	return r

static func fmt_time(sec: float) -> String:
	var t := int(ceil(sec))
	if t >= 3600: return "%dh %02dm" % [t / 3600, (t % 3600) / 60]
	if t >= 60: return "%dm %02ds" % [t / 60, t % 60]
	return "%ds" % t

## Item row: icon + "Name ×n".
static func item_row(id: String, qty: int, size := 56) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_child(icon_rect(item_tex(id), size))
	h.add_child(label("%s ×%d" % [GameData.item_name(id), qty], 26))
	return h
