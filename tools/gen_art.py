#!/usr/bin/env python3
"""Generate all original in-game art as SVG into assets/art/ (Godot imports SVG directly).

  python3 tools/gen_art.py

Outputs: tiles, crop growth stages, item icons (category shape badge + colour, for
colour-blind players), buildings, animals, character portraits (+ blink frame for
idle animation), avatar layers (white, tinted in-game) and UI icons. All CC0.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"
INK = "#4A2F1F"
load = lambda n: {k: v for k, v in json.loads((ROOT / "data" / n).read_text()).items() if k != "_doc"}


def o(w=6):
    return f'stroke="{INK}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"'


def svg(body, w=128, h=128):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>\n'


def save(rel, text):
    p = ART / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


# ------------------------------------------------------------------ motifs (128 box)
def crop_motif(shape, color, s=1.0):
    """Ripe-crop drawing by shape family."""
    g = f'transform="translate(64 70) scale({s}) translate(-64 -70)"'
    if shape == "grain":
        k = "".join(f'<ellipse cx="{64+d*10}" cy="{40+i*14}" rx="8" ry="12" fill="{color}" {o(4)}/>' for i in range(4) for d in (-1, 1))
        return f'<g {g}><path d="M64 110 V30" {o(6)}/>{k}<ellipse cx="64" cy="30" rx="7" ry="12" fill="{color}" {o(4)}/></g>'
    if shape == "root":
        return f'<g {g}><path d="M48 40 Q64 22 80 40 L64 112 Z" fill="{color}" {o()}/><path d="M64 38 Q50 14 40 18 M64 38 Q66 10 72 8 M64 38 Q80 16 90 20" fill="none" stroke="#3FA34D" stroke-width="8" stroke-linecap="round"/><path d="M56 60 H66 M60 78 H70" {o(4)}/></g>'
    if shape == "leafy":
        return f'<g {g}><circle cx="64" cy="72" r="38" fill="{color}" {o()}/><path d="M64 110 Q40 70 64 36 Q88 70 64 110 M34 70 Q64 80 94 70" fill="none" {o(4)}/></g>'
    if shape == "berry":
        return f'<g {g}><path d="M64 112 Q24 80 34 52 Q64 40 94 52 Q104 80 64 112 Z" fill="{color}" {o()}/><path d="M44 46 Q64 30 84 46 L64 54 Z" fill="#3FA34D" {o(4)}/>' + "".join(f'<circle cx="{x}" cy="{y}" r="3" fill="#FFF3B0"/>' for x, y in [(52, 66), (70, 64), (60, 82), (78, 80), (64, 98)]) + "</g>"
    if shape == "flower":
        pet = "".join(f'<ellipse cx="64" cy="34" rx="12" ry="22" fill="{color}" {o(4)} transform="rotate({a} 64 60)"/>' for a in range(0, 360, 45))
        return f'<g {g}><path d="M64 80 V120" stroke="#3FA34D" stroke-width="10"/>{pet}<circle cx="64" cy="60" r="18" fill="#8A5A3B" {o(4)}/></g>'
    # round
    return f'<g {g}><circle cx="64" cy="72" r="38" fill="{color}" {o()}/><path d="M56 34 Q64 20 72 34" fill="#3FA34D" {o(4)}/><ellipse cx="50" cy="60" rx="8" ry="12" fill="#fff" opacity="0.35"/></g>'


def category_motif(cat, color, item):
    if cat == "animal":
        if item == "feather":
            return f'<path d="M40 108 Q44 40 96 20 Q92 80 40 108 Z" fill="{color}" {o()}/><path d="M40 108 L84 40" {o(4)}/>'
        if item == "wool":
            return "".join(f'<circle cx="{x}" cy="{y}" r="22" fill="{color}" {o()}/>' for x, y in [(44, 76), (84, 76), (64, 56), (64, 88)])
        if item == "egg":
            return f'<ellipse cx="64" cy="70" rx="32" ry="42" fill="{color}" {o()}/><ellipse cx="52" cy="54" rx="7" ry="12" fill="#fff" opacity="0.6"/>'
        return f'<path d="M44 34 H84 L90 52 V108 Q90 114 84 114 H44 Q38 114 38 108 V52 Z" fill="{color}" {o()}/><path d="M38 70 H90" stroke="#8FD3F4" stroke-width="10"/><rect x="48" y="22" width="32" height="14" rx="4" fill="#8FD3F4" {o(4)}/>'
    if cat == "feed":
        return f'<path d="M32 50 Q64 30 96 50 L90 112 H38 Z" fill="#D8B878" {o()}/><path d="M40 52 Q64 70 88 52" fill="{color}" {o(4)}/>'
    if cat == "meal":
        return f'<ellipse cx="64" cy="84" rx="48" ry="22" fill="#FFFFFF" {o()}/><path d="M24 78 Q64 120 104 78" fill="#FFFFFF" {o()}/><ellipse cx="64" cy="76" rx="36" ry="12" fill="{color}" {o(4)}/><path d="M50 52 Q44 40 52 30 M64 52 Q58 40 66 28 M78 52 Q72 40 80 30" fill="none" stroke="#B0B0B0" stroke-width="5" stroke-linecap="round"/>'
    if cat == "craft":
        return f'<rect x="26" y="34" width="76" height="66" rx="16" fill="{color}" {o()}/><path d="M26 56 H102 M26 78 H102" stroke="#fff" stroke-width="6" opacity="0.6"/>'
    # goods: jar / loaf / wheel by name
    if "jam" in item or "sauce" in item or "oil" in item:
        return f'<rect x="36" y="44" width="56" height="64" rx="12" fill="{color}" {o()}/><rect x="32" y="30" width="64" height="18" rx="6" fill="#E9B872" {o()}/><rect x="46" y="62" width="36" height="24" rx="4" fill="#FBF0D6"/>'
    if "cheese" in item or item == "butter":
        return f'<path d="M24 92 L64 36 L104 92 Z" fill="{color}" {o()}/><circle cx="60" cy="74" r="6" fill="#000" opacity="0.13"/><circle cx="76" cy="84" r="4" fill="#000" opacity="0.13"/>'
    if "pie" in item or item == "cake":
        return f'<ellipse cx="64" cy="82" rx="46" ry="22" fill="#D69A4E" {o()}/><ellipse cx="64" cy="74" rx="42" ry="16" fill="{color}" {o(4)}/><path d="M34 74 H94 M64 60 V88" stroke="#E9B872" stroke-width="5"/>'
    if item == "flour" or item == "cream":
        return f'<path d="M36 40 Q64 28 92 40 L98 110 H30 Z" fill="{color}" {o()}/><path d="M48 70 Q64 60 80 70" fill="none" stroke="#E8C15A" stroke-width="6"/>'
    return f'<path d="M22 84 Q22 44 64 44 Q106 44 106 84 Q106 98 92 98 H36 Q22 98 22 84 Z" fill="{color}" {o()}/><path d="M44 58 L52 70 M62 54 L70 66 M80 58 L88 70" {o(4)}/>'


BADGE = {  # category -> badge shape path centred at (108,108)
    "crop": '<circle cx="108" cy="108" r="14"/>',
    "animal": '<path d="M108 92 Q122 110 108 122 Q94 110 108 92 Z"/>',
    "goods": '<rect x="95" y="95" width="26" height="26" rx="4"/>',
    "meal": '<path d="M108 92 L112 103 L123 104 L114 111 L117 122 L108 116 L99 122 L102 111 L93 104 L104 103 Z"/>',
    "craft": '<path d="M108 92 L124 108 L108 124 L92 108 Z"/>',
    "feed": '<path d="M108 92 L124 122 H92 Z"/>',
}
BADGE_FILL = {"crop": "#6BAA4B", "animal": "#8FD3F4", "goods": "#F2B84B", "meal": "#C8553D", "craft": "#C97BB5", "feed": "#B9984F"}


def item_icon(item, info, crops):
    cat = info["category"]
    body = crop_motif(crops[item]["shape"], info["color"], 0.9) if cat == "crop" else category_motif(cat, info["color"], item)
    b = BADGE[cat].replace("/>", f' fill="{BADGE_FILL[cat]}" {o(4)}/>')
    return svg(body + b)


# ------------------------------------------------------------------ tiles + crop stages
def tiles():
    save("tiles/grass.svg", svg('<rect width="128" height="128" fill="#8CCB5E"/>' + "".join(
        f'<path d="M{x} {y} q3 -8 6 0" fill="none" stroke="#6FB24B" stroke-width="3"/>' for x, y in [(20, 30), (80, 20), (50, 70), (100, 90), (14, 100), (70, 110)])))
    save("tiles/soil.svg", svg(f'<rect x="4" y="8" width="120" height="116" rx="18" fill="#8A5A3B" {o(5)}/><rect x="10" y="12" width="108" height="100" rx="14" fill="#A8724A"/>' + "".join(
        f'<path d="M20 {y} H108" stroke="#8A5A3B" stroke-width="6" stroke-linecap="round"/>' for y in (36, 62, 88))))
    save("crops/sprout.svg", svg(f'<path d="M64 100 V80" {o(5)}/><path d="M64 84 Q44 84 40 66 Q60 64 64 84 Z M64 80 Q84 78 88 60 Q68 60 64 80 Z" fill="#7CC35A" {o(4)}/>'))
    for cid, c in load("crops.json").items():
        color = load("items.json")[cid]["color"]
        save(f"crops/{cid}_growing.svg", svg(f'<path d="M64 108 V56" {o(6)}/>' + "".join(
            f'<path d="M64 {y} Q{64+d*30} {y-4} {64+d*34} {y-22} Q{64+d*10} {y-20} 64 {y} Z" fill="#6BAA4B" {o(4)}/>' for y in (96, 76) for d in (-1, 1))
            + f'<circle cx="64" cy="52" r="10" fill="{color}" {o(4)}/>'))
        save(f"crops/{cid}_ready.svg", svg(crop_motif(c["shape"], color)))


# ------------------------------------------------------------------ buildings (192 box)
def building(roof, wall, emblem, kind="house"):
    if kind == "mill":
        blades = "".join(f'<rect x="90" y="18" width="12" height="70" rx="4" fill="#FBF0D6" {o(4)} transform="rotate({a} 96 84)"/>' for a in (0, 90, 180, 270))
        return svg(f'<ellipse cx="96" cy="182" rx="70" ry="8" fill="#000" opacity="0.13"/><path d="M60 180 L72 84 H120 L132 180 Z" fill="{wall}" {o()}/><path d="M66 90 L96 56 L126 90 Z" fill="{roof}" {o()}/>{blades}<circle cx="96" cy="84" r="9" fill="{INK}"/><path d="M84 180 V150 Q96 136 108 150 V180" fill="#8A5A3B" {o(4)}/>', 192, 192)
    if kind == "pen":
        posts = "".join(f'<rect x="{x}" y="100" width="10" height="70" rx="3" fill="#E9B872" {o(4)}/>' for x in range(16, 180, 32))
        return svg(f'<ellipse cx="96" cy="176" rx="88" ry="12" fill="#000" opacity="0.13"/><rect x="10" y="120" width="172" height="60" rx="10" fill="#B8E08A"/>{posts}<path d="M14 118 H178 M14 146 H178" stroke="#E9B872" stroke-width="10" stroke-linecap="round"/><path d="M14 118 H178 M14 146 H178" fill="none" {o(3)}/><path d="M40 100 L96 50 L152 100 Z" fill="{roof}" {o()}/><rect x="56" y="98" width="80" height="30" fill="{wall}" {o()}/>{emblem}', 192, 192)
    return svg(f'''<ellipse cx="96" cy="182" rx="80" ry="9" fill="#000" opacity="0.13"/>
<rect x="28" y="84" width="136" height="96" rx="8" fill="{wall}" {o()}/>
<path d="M14 92 L40 46 L96 22 L152 46 L178 92 Z" fill="{roof}" {o()}/>
<path d="M80 180 V136 Q96 120 112 136 V180" fill="#8A5A3B" {o(5)}/>
<rect x="40" y="110" width="28" height="28" rx="4" fill="#FFE79A" {o(4)}/><rect x="124" y="110" width="28" height="28" rx="4" fill="#FFE79A" {o(4)}/>
<circle cx="96" cy="62" r="20" fill="#FBF0D6" {o(4)}/>{emblem}''', 192, 192)


def emblem_item(color, cat, item):
    return f'<g transform="translate(78 44) scale(0.28)">{category_motif(cat, color, item)}</g>'


BUILDINGS = {
    "inn": ("#C8553D", "#E9B872", "meal", "carrot_stew", "house"),
    "mill": ("#C8553D", "#F3EEE2", "goods", "flour", "mill"),
    "bakery": ("#D69A4E", "#FBE3C0", "goods", "bread", "house"),
    "jam_kitchen": ("#C8193C", "#FDE2E6", "goods", "strawberry_jam", "house"),
    "craft_table": ("#8A5A3B", "#EAD9C0", "craft", "pillow", "house"),
    "dairy": ("#4A6FD8", "#F4F8FF", "goods", "cheese", "house"),
    "soap_maker": ("#3FA34D", "#E6F6EE", "craft", "soap", "house"),
    "loom": ("#9C6ADE", "#F3EAFB", "craft", "yarn", "house"),
    "coop": ("#C8553D", "#F6E7C8", "animal", "egg", "pen"),
    "barn_stall": ("#C8553D", "#E9B872", "animal", "milk", "pen"),
    "goat_pen": ("#8A5A3B", "#FFF6E0", "animal", "goat_milk", "pen"),
    "sheep_pen": ("#6BAA4B", "#F2EDE4", "animal", "wool", "pen"),
}


# ------------------------------------------------------------------ animals (128 box)
def animal(kind, happy=True):
    eye = f'<circle cx="0" cy="0" r="4" fill="{INK}"/>'
    if kind == "chicken":
        return svg(f'<ellipse cx="64" cy="118" rx="34" ry="6" fill="#000" opacity="0.13"/><ellipse cx="62" cy="80" rx="36" ry="30" fill="#FFFFFF" {o()}/><circle cx="88" cy="52" r="18" fill="#FFFFFF" {o()}/><path d="M84 34 Q88 24 94 34 Q98 26 100 38" fill="#E5483B" {o(4)}/><path d="M104 54 L116 58 L104 62 Z" fill="#F2B84B" {o(4)}/><g transform="translate(92 50)">{eye}</g><path d="M36 76 Q52 90 70 78" fill="none" {o(4)}/><path d="M54 108 V116 M70 108 V116" {o(5)}/>')
    if kind == "cow":
        spots = '<ellipse cx="44" cy="74" rx="12" ry="9" fill="#4A2F1F"/><ellipse cx="74" cy="90" rx="10" ry="7" fill="#4A2F1F"/>'
        return svg(f'<ellipse cx="64" cy="120" rx="44" ry="6" fill="#000" opacity="0.13"/><rect x="18" y="56" width="80" height="50" rx="24" fill="#FFFFFF" {o()}/>{spots}<path d="M30 104 V118 M86 104 V118" {o(6)}/><ellipse cx="98" cy="58" rx="22" ry="24" fill="#FFFFFF" {o()}/><ellipse cx="102" cy="72" rx="16" ry="10" fill="#F5B7B1" {o(4)}/><path d="M82 38 L76 28 M114 38 L120 28" {o(5)}/><g transform="translate(92 54)">{eye}</g><g transform="translate(108 54)">{eye}</g>')
    if kind == "goat":
        return svg(f'<ellipse cx="64" cy="120" rx="40" ry="6" fill="#000" opacity="0.13"/><rect x="22" y="60" width="72" height="42" rx="20" fill="#E4D3B8" {o()}/><path d="M32 100 V118 M84 100 V118" {o(6)}/><path d="M86 62 Q90 30 106 34 Q118 40 112 66 Q104 80 94 74 Z" fill="#E4D3B8" {o()}/><path d="M96 34 Q92 18 82 16 M108 36 Q112 20 122 20" fill="none" {o(5)}/><path d="M102 74 L100 88 L108 80" fill="#FBF0D6" {o(4)}/><g transform="translate(104 50)">{eye}</g>')
    return svg(f'<ellipse cx="64" cy="120" rx="44" ry="6" fill="#000" opacity="0.13"/>' + "".join(f'<circle cx="{x}" cy="{y}" r="18" fill="#F7F3EC" {o(5)}/>' for x, y in [(34, 70), (58, 60), (82, 66), (40, 92), (66, 94), (88, 88)])
               + f'<path d="M38 104 V118 M80 104 V118" {o(6)}/><ellipse cx="100" cy="64" rx="16" ry="20" fill="#4A2F1F" {o(4)}/><g transform="translate(104 60)"><circle r="4" fill="#fff"/></g>')


# ------------------------------------------------------------------ characters (256 box)
def face(skin, hair, hair_style, shirt, extra="", blink=False, beard=False, glasses=False):
    eyes = ('<path d="M98 132 q8 6 16 0 M142 132 q8 6 16 0" fill="none" ' + o(5) + "/>") if blink else \
        f'<ellipse cx="106" cy="130" rx="7" ry="9" fill="{INK}"/><ellipse cx="150" cy="130" rx="7" ry="9" fill="{INK}"/><circle cx="108" cy="127" r="2.5" fill="#fff"/><circle cx="152" cy="127" r="2.5" fill="#fff"/>'
    hair_back = {"long": f'<path d="M64 120 Q60 230 100 236 H156 Q196 230 192 120 Z" fill="{hair}" {o()}/>',
                 "bun": f'<circle cx="128" cy="46" r="26" fill="{hair}" {o()}/>'}.get(hair_style, "")
    hair_front = {
        "short": f'<path d="M72 118 Q70 60 128 56 Q186 60 184 118 Q160 92 128 94 Q100 92 72 118 Z" fill="{hair}" {o()}/>',
        "curly": "".join(f'<circle cx="{x}" cy="{y}" r="20" fill="{hair}" {o(5)}/>' for x, y in [(80, 100), (100, 74), (128, 66), (156, 74), (176, 100)]),
        "long": f'<path d="M70 124 Q70 58 128 56 Q186 58 186 124 Q168 86 128 90 Q90 86 70 124 Z" fill="{hair}" {o()}/>',
        "bun": f'<path d="M74 114 Q74 64 128 62 Q182 64 182 114 Q156 90 128 92 Q100 90 74 114 Z" fill="{hair}" {o()}/>',
        "bald": "",
    }[hair_style]
    beard_p = f'<path d="M86 150 Q90 206 128 208 Q166 206 170 150 Q150 172 128 172 Q106 172 86 150 Z" fill="{hair}" {o(5)}/>' if beard else ""
    glasses_p = f'<circle cx="106" cy="130" r="16" fill="none" {o(5)}/><circle cx="150" cy="130" r="16" fill="none" {o(5)}/><path d="M122 130 H134" {o(5)}/>' if glasses else ""
    return svg(f'''<circle cx="128" cy="128" r="124" fill="#FBF0D6"/>{hair_back}
<path d="M40 256 Q40 196 128 192 Q216 196 216 256 Z" fill="{shirt}" {o()}/>
<rect x="112" y="166" width="32" height="34" fill="{skin}" {o(5)}/>
<ellipse cx="128" cy="126" rx="58" ry="62" fill="{skin}" {o()}/>
<ellipse cx="92" cy="150" rx="10" ry="6" fill="#F28B82" opacity="0.5"/><ellipse cx="164" cy="150" rx="10" ry="6" fill="#F28B82" opacity="0.5"/>
{eyes}<path d="M112 158 Q128 172 144 158" fill="none" {o(5)}/>{beard_p}{hair_front}{glasses_p}{extra}''', 256, 256)


CHEF_HAT = f'<path d="M84 80 Q70 40 100 40 Q110 16 128 24 Q146 16 156 40 Q186 40 172 80 Z" fill="#FFFFFF" {o()}/><rect x="84" y="72" width="88" height="20" rx="4" fill="#FFFFFF" {o()}/>'
STRAW_HAT = f'<ellipse cx="128" cy="78" rx="84" ry="18" fill="#E8C15A" {o()}/><path d="M88 78 Q90 36 128 36 Q166 36 168 78 Z" fill="#E8C15A" {o()}/><path d="M88 70 H168" stroke="#C8553D" stroke-width="8"/>'
SCARF = f'<path d="M84 196 Q128 216 172 196 L176 214 Q128 236 80 214 Z" fill="#C8553D" {o(5)}/>'
APRON = f'<path d="M96 210 H160 V256 H96 Z" fill="#FFFFFF" {o(5)}/>'
BANDANA = f'<path d="M74 96 Q128 50 182 96 Q128 80 74 96 Z" fill="#4E7BB5" {o(5)}/>'
FLOWER = f'<circle cx="170" cy="78" r="12" fill="#E83A5F" {o(4)}/><circle cx="170" cy="78" r="4" fill="#FFD86B"/>'

CHARACTERS = {  # id: (skin, hair, style, shirt, extra, beard, glasses)
    "innkeeper": ("#F2C9A0", "#8A5A3B", "bun", "#6BAA4B", APRON + FLOWER, False, False),
    "chef": ("#8D5A3B", "#2B1B14", "short", "#FFFFFF", CHEF_HAT, True, False),
    "merchant": ("#E0AC7E", "#D9A441", "curly", "#4A6FD8", SCARF, False, True),
    "vet": ("#C68A5E", "#3B2A20", "long", "#7EA6E0", "", False, False),
    "craftsperson": ("#F5D5B8", "#B04A2E", "short", "#9C6ADE", BANDANA, True, False),
    "guest_wanderer": ("#D9A57A", "#5B4636", "short", "#8A5A3B", STRAW_HAT, True, False),
    "guest_painter": ("#F2C9A0", "#E07A5F", "bun", "#F2B84B", "", False, False),
    "guest_scholar": ("#7A4A2E", "#E8E8E8", "bald", "#3E7C3A", "", True, True),
    "guest_cyclist": ("#F5D5B8", "#2B1B14", "curly", "#E5483B", "", False, False),
    "guest_musician": ("#B57A50", "#4A2F1F", "long", "#C97BB5", FLOWER, False, False),
    "guest_baker_kid": ("#F7D9C4", "#F2B84B", "short", "#8FD3F4", "", False, False),
    "guest_fisher": ("#C68A5E", "#9AA0A6", "short", "#4E7BB5", BANDANA, True, False),
    "guest_gardener": ("#8D5A3B", "#2B1B14", "bun", "#7CC35A", STRAW_HAT, False, True),
    "guest_poet": ("#E0AC7E", "#3B2A20", "long", "#4A2F1F", SCARF, False, False),
    "guest_knitter": ("#F2C9A0", "#C0C0C0", "bun", "#E9A3C0", "", False, True),
}


def avatar_layers():
    """White/grey layers tinted by the player's choices with CanvasItem.modulate."""
    W = "#FFFFFF"
    save("avatar/skin.svg", svg(f'<path d="M112 166 H144 V200 H112 Z" fill="{W}" {o(5)}/><ellipse cx="128" cy="126" rx="58" ry="62" fill="{W}" {o()}/>', 256, 256))
    save("avatar/face.svg", svg(f'<ellipse cx="106" cy="130" rx="7" ry="9" fill="{INK}"/><ellipse cx="150" cy="130" rx="7" ry="9" fill="{INK}"/><circle cx="108" cy="127" r="2.5" fill="#fff"/><circle cx="152" cy="127" r="2.5" fill="#fff"/><path d="M112 158 Q128 172 144 158" fill="none" {o(5)}/><ellipse cx="92" cy="150" rx="10" ry="6" fill="#F28B82" opacity="0.5"/><ellipse cx="164" cy="150" rx="10" ry="6" fill="#F28B82" opacity="0.5"/>', 256, 256))
    save("avatar/outfit.svg", svg(f'<path d="M40 256 Q40 196 128 192 Q216 196 216 256 Z" fill="{W}" {o()}/>', 256, 256))
    for style in ("short", "curly", "long", "bun"):
        # reuse face() hair shapes on a transparent canvas
        full = face(W, W, style, "none")
        hair = [seg for seg in full.split("<") if f'fill="{W}"' in seg and ("path" in seg or "circle" in seg)]
        body = "".join("<" + h for h in hair if "M112 166" not in h and "128\" cy=\"126" not in h)
        save(f"avatar/hair_{style}.svg", svg(body, 256, 256))
    save("avatar/hat_hat_straw.svg", svg(STRAW_HAT.replace("#E8C15A", W).replace("#C8553D", "#DDDDDD"), 256, 256))
    save("avatar/hat_hat_bandana.svg", svg(BANDANA.replace("#4E7BB5", W), 256, 256))
    save("avatar/hat_hat_beanie.svg", svg(f'<path d="M72 104 Q72 46 128 44 Q184 46 184 104 Z" fill="{W}" {o()}/><rect x="68" y="96" width="120" height="18" rx="8" fill="{W}" {o()}/><circle cx="128" cy="40" r="12" fill="{W}" {o(5)}/>', 256, 256))
    save("avatar/hat_hat_sunflower.svg", svg("".join(f'<ellipse cx="{x}" cy="78" rx="12" ry="16" fill="{W}" {o(4)}/>' for x in range(80, 180, 24)), 256, 256))


# ------------------------------------------------------------------ UI icons (64 box)
UI = {
    "coin": f'<circle cx="32" cy="32" r="26" fill="#F2B84B" {o(4)}/><circle cx="32" cy="32" r="16" fill="none" stroke="#C98F2E" stroke-width="4"/>',
    "gem": f'<path d="M14 24 L24 10 H40 L50 24 L32 56 Z" fill="#8FD3F4" {o(4)}/><path d="M14 24 H50 M24 10 L32 24 L40 10" fill="none" {o(3)}/>',
    "xp": f'<path d="M32 6 L39 24 L58 25 L43 37 L48 56 L32 45 L16 56 L21 37 L6 25 L25 24 Z" fill="#F5D33F" {o(4)}/>',
    "rep": f'<path d="M32 54 Q6 36 8 20 Q12 6 26 10 Q32 13 32 18 Q32 13 38 10 Q52 6 56 20 Q58 36 32 54 Z" fill="#E83A5F" {o(4)}/>',
    "shop": f'<path d="M8 26 L14 10 H50 L56 26 Z" fill="#C8553D" {o(4)}/><rect x="12" y="26" width="40" height="28" fill="#FBF0D6" {o(4)}/><rect x="26" y="36" width="12" height="18" fill="#8A5A3B" {o(3)}/>',
    "barn": f'<path d="M8 28 L16 12 L32 6 L48 12 L56 28 V56 H8 Z" fill="#C8553D" {o(4)}/><path d="M22 56 V36 H42 V56 M22 36 L42 56 M42 36 L22 56" fill="none" stroke="#FBF0D6" stroke-width="4"/>',
    "inn": f'<path d="M8 30 L32 8 L56 30 Z" fill="#C8553D" {o(4)}/><rect x="14" y="30" width="36" height="26" fill="#E9B872" {o(4)}/><path d="M28 56 V44 H36 V56" fill="#8A5A3B" {o(3)}/>',
    "market": f'<rect x="10" y="22" width="44" height="32" rx="4" fill="#FBF0D6" {o(4)}/><path d="M6 22 Q12 10 20 22 Q26 10 32 22 Q38 10 44 22 Q52 10 58 22" fill="#6BAA4B" {o(4)}/><circle cx="32" cy="40" r="8" fill="#F2B84B" {o(3)}/>',
    "friends": f'<circle cx="22" cy="22" r="10" fill="#F2C9A0" {o(4)}/><circle cx="42" cy="22" r="10" fill="#C68A5E" {o(4)}/><path d="M6 54 Q8 36 22 36 Q36 36 38 54 Z M26 54 Q28 36 42 36 Q56 36 58 54 Z" fill="#8FD3F4" {o(4)}/>',
    "settings": f'<circle cx="32" cy="32" r="18" fill="#9AA0A6" {o(4)}/><circle cx="32" cy="32" r="7" fill="#FBF0D6" {o(3)}/>' + "".join(f'<rect x="28" y="4" width="8" height="12" rx="2" fill="#9AA0A6" {o(3)} transform="rotate({a} 32 32)"/>' for a in range(0, 360, 60)),
    "orders": f'<rect x="12" y="8" width="40" height="50" rx="4" fill="#FBF0D6" {o(4)}/><path d="M20 22 H44 M20 32 H44 M20 42 H36" {o(3)}/>',
    "gift": f'<rect x="10" y="26" width="44" height="30" fill="#C8553D" {o(4)}/><rect x="6" y="18" width="52" height="10" fill="#E07A5F" {o(4)}/><path d="M32 18 V56" stroke="#F2B84B" stroke-width="6"/>',
    "trophy": f'<path d="M18 8 H46 V26 Q46 40 32 40 Q18 40 18 26 Z" fill="#F2B84B" {o(4)}/><rect x="26" y="40" width="12" height="8" fill="#F2B84B" {o(3)}/><rect x="18" y="48" width="28" height="8" rx="2" fill="#8A5A3B" {o(3)}/>',
    "farm": f'<rect x="8" y="30" width="48" height="26" rx="6" fill="#A8724A" {o(4)}/><path d="M20 30 V18 M32 30 V12 M44 30 V18" stroke="#6BAA4B" stroke-width="6" stroke-linecap="round"/>',
    "lock": f'<rect x="14" y="28" width="36" height="28" rx="6" fill="#9AA0A6" {o(4)}/><path d="M22 28 V20 Q22 10 32 10 Q42 10 42 20 V28" fill="none" {o(5)}/>',
    "clock": f'<circle cx="32" cy="32" r="24" fill="#FBF0D6" {o(4)}/><path d="M32 18 V32 L42 38" fill="none" {o(4)}/>',
    "heart_hand": f'<path d="M32 40 Q18 30 20 20 Q24 12 32 18 Q40 12 44 20 Q46 30 32 40 Z" fill="#E83A5F" {o(3)}/><path d="M8 50 Q20 40 32 50 Q44 40 56 50 V58 H8 Z" fill="#F2C9A0" {o(3)}/>',
}


DECOR = {
    "decor_fence": f'<path d="M10 70 H118 M10 100 H118" stroke="#FFFFFF" stroke-width="12"/><path d="M10 70 H118 M10 100 H118" fill="none" {o(3)}/>' + "".join(f'<path d="M{x} 118 V44 L{x+10} 32 L{x+20} 44 V118 Z" fill="#FFFFFF" {o(4)}/>' for x in (10, 40, 70, 100)),
    "decor_flowerbed": f'<ellipse cx="64" cy="96" rx="56" ry="22" fill="#8A5A3B" {o(5)}/>' + "".join(f'<circle cx="{x}" cy="{y}" r="12" fill="{c}" {o(3)}/><circle cx="{x}" cy="{y}" r="4" fill="#FFD86B"/>' for x, y, c in [(30, 82, "#E83A5F"), (52, 72, "#C97BB5"), (76, 80, "#F2B84B"), (98, 74, "#E83A5F"), (64, 92, "#8FD3F4")]),
    "decor_scarecrow": f'<path d="M64 124 V40" {o(8)}/><path d="M24 62 H104" {o(8)}/><path d="M40 60 H88 L82 100 H46 Z" fill="#6BAA4B" {o(4)}/><circle cx="64" cy="34" r="20" fill="#F2D7A6" {o(4)}/><circle cx="57" cy="32" r="3" fill="{INK}"/><circle cx="71" cy="32" r="3" fill="{INK}"/><path d="M56 42 Q64 48 72 42" fill="none" {o(3)}/><path d="M36 20 H92 L80 4 H48 Z" fill="#E8C15A" {o(4)}/>',
    "decor_well": f'<rect x="24" y="64" width="80" height="56" rx="10" fill="#9AA0A6" {o(5)}/><path d="M24 84 H104 M24 102 H104" stroke="#7C8288" stroke-width="5"/><path d="M30 64 V24 M98 64 V24" {o(6)}/><path d="M18 30 L64 8 L110 30 Z" fill="#C8553D" {o(5)}/><ellipse cx="64" cy="66" rx="34" ry="8" fill="#4AA8D8" {o(3)}/>',
    "decor_lamp": f'<path d="M64 124 V44" {o(8)}/><rect x="46" y="16" width="36" height="36" rx="8" fill="#FFD86B" {o(5)}/><path d="M40 16 H88 L64 4 Z" fill="{INK}"/><ellipse cx="64" cy="122" rx="22" ry="5" fill="#000" opacity="0.13"/>',
    "decor_pond": f'<ellipse cx="64" cy="76" rx="58" ry="36" fill="#4AA8D8" {o(5)}/><ellipse cx="52" cy="70" rx="14" ry="10" fill="#FFFFFF" {o(3)}/><circle cx="62" cy="62" r="7" fill="#FFFFFF" {o(3)}/><path d="M68 62 L76 64 L68 66 Z" fill="#F2B84B"/><ellipse cx="90" cy="88" rx="10" ry="5" fill="#7CC35A" {o(3)}/>',
}


def main():
    for k, body in DECOR.items():
        save(f"decor/{k}.svg", svg(body))
    items, crops = load("items.json"), load("crops.json")
    tiles()
    for iid, info in items.items():
        save(f"items/{iid}.svg", item_icon(iid, info, crops))
    for bid, (roof, wall, cat, emb_item, kind) in BUILDINGS.items():
        emb = emblem_item(items[emb_item]["color"], cat, emb_item)
        if kind == "pen":
            emb = f'<g transform="translate(78 100) scale(0.28)">{category_motif(cat, items[emb_item]["color"], emb_item)}</g>'
        save(f"buildings/{bid}.svg", building(roof, wall, emb, kind))
    for a in ("chicken", "cow", "goat", "sheep"):
        save(f"animals/{a}.svg", animal(a))
    for cid, (skin, hair, style, shirt, extra, beard, glasses) in CHARACTERS.items():
        save(f"characters/{cid}.svg", face(skin, hair, style, shirt, extra, False, beard, glasses))
        save(f"characters/{cid}_blink.svg", face(skin, hair, style, shirt, extra, True, beard, glasses))
    avatar_layers()
    for k, body in UI.items():
        save(f"ui/{k}.svg", svg(body, 64, 64))
    print("art written:", sum(1 for _ in ART.rglob("*.svg")), "SVGs")


if __name__ == "__main__":
    main()
