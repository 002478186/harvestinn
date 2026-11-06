## The player's farmer: white SVG layers tinted from the player's choices.
class_name Avatar
extends Control

const SKINS := ["#F7D9C4", "#F2C9A0", "#E0AC7E", "#C68A5E", "#8D5A3B", "#5C3A24"]
const HAIR_COLORS := ["#2B1B14", "#5B4636", "#B04A2E", "#D9A441", "#E8E8E8", "#3E6FB0"]
const HAIR_STYLES := ["short", "curly", "long", "bun"]

static func make(a: Dictionary, size := 200) -> Avatar:
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(size, size)
	var cos := GameData.cosmetics()
	var layers := [
		["outfit", Color(cos.get(a["outfit"], {}).get("color", "#4E7BB5"))],
		["skin", Color(SKINS[int(a["skin"]) % SKINS.size()])],
		["face", Color.WHITE],
		["hair_%s" % a["hair"], Color(HAIR_COLORS[int(a["hair_color"]) % HAIR_COLORS.size()])],
	]
	if a["hat"] != "hat_none":
		layers.append(["hat_%s" % a["hat"], Color(cos.get(a["hat"], {}).get("color", "#ffffff"))])
	for l in layers:
		var r := UI.icon_rect(UI.tex("res://assets/art/avatar/%s.svg" % l[0]), size)
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.self_modulate = l[1]
		av.add_child(r)
	return av
