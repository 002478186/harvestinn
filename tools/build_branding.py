#!/usr/bin/env python3
"""Build every HarvestInn branding asset from vector sources.

Writes SVGs to branding/ and rasterizes them with `rsvg-convert` (librsvg):
  branding/concepts/concept_{a,b,c}.svg      three logo concepts
  branding/logo.svg                          master logo (chosen concept A, refined)
  branding/wordmark.svg                      logo + "HarvestInn" lettering
  branding/ios/AppIcon.appiconset/*          all iOS sizes + Contents.json (opaque)
  branding/android/adaptive/*                adaptive foreground/background 432px
  branding/android/legacy/mipmap-*/          legacy launcher icons
  branding/splash/*, branding/store/*        splash screens, 1024x500 feature graphic
  branding/icon_256.png                      Godot project icon

Run: python3 tools/build_branding.py   (needs: brew install librsvg)
"""
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
B = ROOT / "branding"

PALETTE = {
    "barn_red": "#C8553D", "barn_red_dark": "#8E3426", "barn_red_light": "#E07A5F",
    "wheat": "#F2B84B", "meadow": "#6BAA4B", "leaf": "#3E7C3A", "hill": "#7CC35A",
    "cream": "#FBF0D6", "wood": "#E9B872", "wood_dark": "#8A5A3B", "sky": "#8FD3F4",
    "sky_light": "#DDF3FB", "sun": "#FFD86B", "window": "#FFE79A", "ink": "#4A2F1F",
}
P = PALETTE
def out(w=12):
    return f'stroke="{P["ink"]}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"'
OUT = out()

# ---------------------------------------------------------------- shared parts
def sky_bg(w=1024, h=1024):
    return f'''<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="{P["sky"]}"/><stop offset="1" stop-color="{P["sky_light"]}"/></linearGradient></defs>
<rect width="{w}" height="{h}" fill="url(#sky)"/>'''

def hills():
    return f'''<circle cx="800" cy="230" r="92" fill="{P["sun"]}"/>
<path d="M0 760 Q512 610 1024 760 L1024 1024 L0 1024 Z" fill="{P["hill"]}"/>
<path d="M0 880 Q300 800 600 868 T1024 850 V1024 H0 Z" fill="{P["meadow"]}"/>'''

def inn(scale=1.0, tx=0, ty=0):
    """The chosen mark: a small wooden inn under a gambrel barn roof, a sprout on top."""
    return f'''<g transform="translate({tx} {ty}) scale({scale})">
  <ellipse cx="512" cy="790" rx="270" ry="34" fill="#000" opacity="0.12"/>
  <!-- body -->
  <rect x="318" y="468" width="388" height="310" rx="14" fill="{P["wood"]}" {OUT}/>
  <path d="M330 540 H694 M330 610 H694 M330 680 H694 M330 748 H694" stroke="#C98F4E" stroke-width="8"/>
  <!-- gambrel roof -->
  <path d="M262 500 L330 366 L512 288 L694 366 L762 500 Z" fill="{P["barn_red"]}" {OUT}/>
  <path d="M312 478 L360 382 L512 318 L664 382 L712 478" fill="none" stroke="{P["barn_red_light"]}" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>
  <!-- attic window -->
  <circle cx="512" cy="410" r="44" fill="{P["window"]}" {OUT}/>
  <path d="M512 370 V450 M472 410 H552" stroke="{P["ink"]}" stroke-width="8"/>
  <!-- windows -->
  <rect x="354" y="560" width="82" height="82" rx="10" fill="{P["window"]}" {OUT}/>
  <rect x="588" y="560" width="82" height="82" rx="10" fill="{P["window"]}" {OUT}/>
  <path d="M395 564 V638 M358 601 H432 M629 564 V638 M592 601 H666" stroke="{P["ink"]}" stroke-width="7"/>
  <!-- door -->
  <path d="M458 778 V666 Q458 618 512 618 Q566 618 566 666 V778 Z" fill="{P["wood_dark"]}" {OUT}/>
  <circle cx="548" cy="712" r="8" fill="{P["wheat"]}"/>
  <!-- sprout -->
  <path d="M512 292 C512 262 512 240 512 214" fill="none" {out(14)}/>
  <path d="M512 236 C470 236 438 212 430 172 C474 168 506 192 512 236 Z" fill="{P["meadow"]}" {OUT}/>
  <path d="M512 222 C548 216 580 186 588 146 C546 146 514 176 512 222 Z" fill="{P["meadow"]}" {OUT}/>
</g>'''

def svg(body, w=1024, h=1024, extra_defs=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{extra_defs}{body}</svg>\n'

def wheat(x, y, h, lean=0):
    """One wheat stalk with grain kernels; lean tilts the head (degrees)."""
    kern = "".join(
        f'<ellipse cx="{side*15}" cy="{-h + 30 + i*26}" rx="13" ry="22" transform="rotate({side*28} {side*15} {-h + 30 + i*26})" fill="{P["wheat"]}" {out(7)}/>'
        for i in range(4) for side in (-1, 1))
    return f'''<g transform="translate({x} {y}) rotate({lean})">
  <path d="M0 0 V{-h+10}" {out(10)}/>
  <ellipse cx="0" cy="{-h + 6}" rx="12" ry="24" fill="{P["wheat"]}" {out(7)}/>{kern}</g>'''


def refined_mark():
    """Concept A refined: flanking wheat, warmer glow; same silhouette for small sizes."""
    glow = f'<circle cx="512" cy="560" r="300" fill="{P["sun"]}" opacity="0.18"/>'
    return wheat(250, 800, 250, -10) + wheat(200, 820, 200, -18) + inn() + wheat(774, 800, 250, 10) + wheat(824, 820, 200, 18)


# ---------------------------------------------------------------- concepts
CONCEPT_A = svg(sky_bg() + hills() + inn())

CONCEPT_B = svg(f'''<rect width="1024" height="1024" fill="{P["cream"]}"/>
<rect x="250" y="150" width="40" height="760" rx="12" fill="{P["wood_dark"]}" {OUT}/>
<path d="M270 230 H760" {out(20)}/>
<path d="M380 230 V330 M680 230 V330" {out(10)}/>
<rect x="320" y="320" width="420" height="380" rx="40" fill="{P["wood"]}" {OUT}/>
<path d="M530 600 L470 420 Q530 380 590 420 Z" fill="#F08A2C" {OUT}/>
<path d="M530 410 C500 370 500 340 520 320 M530 410 C560 370 580 350 600 340" fill="none" stroke="{P["leaf"]}" stroke-width="18" stroke-linecap="round"/>''')

CONCEPT_C = svg(f'''<rect width="1024" height="1024" fill="{P["barn_red"]}"/>
<path d="M440 330 C410 290 470 260 440 210 M520 330 C490 290 550 260 520 210 M600 330 C570 290 630 260 600 210" fill="none" stroke="#fff" stroke-width="16" stroke-linecap="round" opacity="0.8"/>
<path d="M232 430 H792 Q792 760 512 760 Q232 760 232 430 Z" fill="{P["cream"]}" {OUT}/>
<path d="M232 430 H792" {out(20)}/>
<path d="M300 470 Q512 520 724 470" fill="none" stroke="{P["wheat"]}" stroke-width="40" stroke-linecap="round"/>
<path d="M700 400 L820 220 M720 410 L850 260 M740 420 L870 300" stroke="{P["wheat"]}" stroke-width="20" stroke-linecap="round"/>''')

# ---------------------------------------------------------------- final assets
LOGO = svg(sky_bg() + hills() + refined_mark())                         # opaque app icon master
FG = svg(inn(scale=0.62, tx=195, ty=210), 1024, 1024)            # adaptive foreground (66% safe zone)
BG = svg(sky_bg() + hills())                                     # adaptive background

# ---------------------------------------------------------------- lettering as paths
_FONTS = {}

def _font(name, wght):
    """Instance the bundled variable font at a weight (fontTools), cached."""
    key = (name, wght)
    if key not in _FONTS:
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
        f = TTFont(str(ROOT / "assets" / "fonts" / f"{name}.ttf"))
        axes = {"wght": wght}
        if "wdth" in [a.axisTag for a in f["fvar"].axes]:
            axes["wdth"] = 100
        _FONTS[key] = instancer.instantiateVariableFont(f, axes)
    return _FONTS[key]


def text_paths(segments, size, x, y, font="Fredoka", wght=600, anchor="start", stroke=0, spacing=0):
    """Render [(text, fill), ...] as SVG <path>s so assets never depend on installed fonts."""
    from fontTools.pens.svgPathPen import SVGPathPen
    f = _font(font, wght)
    upm = f["head"].unitsPerEm
    gs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f["hmtx"]
    sc = size / upm
    glyphs, adv = [], 0.0
    for text, fill in segments:
        for ch in text:
            g = cmap.get(ord(ch))
            if g is None:
                continue
            glyphs.append((g, adv, fill))
            adv += hmtx[g][0] + spacing / sc
    width = adv * sc
    x0 = x - width / 2 if anchor == "middle" else x
    parts = []
    for g, off, fill in glyphs:
        pen = SVGPathPen(gs)
        gs[g].draw(pen)
        d = pen.getCommands()
        if not d:
            continue
        st = f' stroke="{P["ink"]}" stroke-width="{stroke / sc:.1f}" stroke-linejoin="round" paint-order="stroke"' if stroke else ""
        parts.append(f'<path transform="translate({x0 + off * sc:.2f} {y}) scale({sc:.5f} {-sc:.5f})" d="{d}" fill="{fill}"{st}/>')
    return "\n".join(parts)


NAME = [("Harvest", P["barn_red"]), ("Inn", P["meadow"])]


def wordmark(w=1600, h=520, bg=None):
    bgr = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return svg(f'''{bgr}<g transform="translate(0 {(h-520)//2})">{inn(scale=0.5, tx=-10, ty=60)}</g>
{text_paths(NAME, 200, 500, h//2 + 70, stroke=11, spacing=2)}''', w, h)


def splash(w, h):
    s = min(w, h) / 1024 * 0.7
    tx, ty = (w - 1024 * s) / 2, h * 0.30 - 512 * s
    fs = 0.15 * min(w, h)
    return svg(f'''<rect width="{w}" height="{h}" fill="{P["cream"]}"/>
<path d="M0 {h*0.82} Q{w/2} {h*0.74} {w} {h*0.82} V{h} H0 Z" fill="{P["hill"]}"/>
<path d="M0 {h*0.9} Q{w*0.3} {h*0.86} {w*0.6} {h*0.89} T{w} {h*0.88} V{h} H0 Z" fill="{P["meadow"]}"/>
{inn(scale=s, tx=tx, ty=ty)}
{text_paths(NAME, fs, w/2, h*0.30 + 512*s + fs*1.1, anchor="middle", stroke=fs*0.06)}''', w, h)


FEATURE_BODY = lambda: f'''{sky_bg(1024, 500)}
<circle cx="900" cy="90" r="60" fill="{P["sun"]}"/>
<path d="M0 400 Q512 330 1024 400 V500 H0 Z" fill="{P["hill"]}"/>
<path d="M0 450 Q300 420 600 446 T1024 440 V500 H0 Z" fill="{P["meadow"]}"/>
{inn(scale=0.40, tx=10, ty=50)}
{text_paths(NAME, 94, 430, 240, stroke=6)}
{text_paths([("Grow · Cook · Host · Trade", P["ink"])], 34, 436, 304, font="Nunito", wght=800)}'''

IOS_SIZES = [  # (idiom, size pt, scale)
    ("iphone", 20, 2), ("iphone", 20, 3), ("iphone", 29, 2), ("iphone", 29, 3),
    ("iphone", 40, 2), ("iphone", 40, 3), ("iphone", 60, 2), ("iphone", 60, 3),
    ("ipad", 20, 1), ("ipad", 20, 2), ("ipad", 29, 1), ("ipad", 29, 2), ("ipad", 40, 1),
    ("ipad", 40, 2), ("ipad", 76, 1), ("ipad", 76, 2), ("ipad", 83.5, 2), ("ios-marketing", 1024, 1),
]
ANDROID_LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def fontconfig_env():
    """Point librsvg/fontconfig at the bundled OFL fonts without installing them."""
    conf = pathlib.Path(tempfile.gettempdir()) / "harvestinn-fonts.conf"
    conf.write_text(f'''<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><dir>{ROOT / "assets" / "fonts"}</dir><include ignore_missing="yes">/opt/homebrew/etc/fonts/fonts.conf</include></fontconfig>''')
    return {**os.environ, "FONTCONFIG_FILE": str(conf)}


ENV = None

def raster(src: pathlib.Path, dst: pathlib.Path, w: int, h=None, opaque=False):
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["rsvg-convert", "-w", str(w), "-h", str(h or w), str(src), "-o", str(dst)]
    if opaque:
        cmd[1:1] = ["-b", P["sky_light"]]
    subprocess.run(cmd, check=True, env=ENV)


def write(path: pathlib.Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def main():
    global ENV
    ENV = fontconfig_env()
    for name, body in {"a": CONCEPT_A, "b": CONCEPT_B, "c": CONCEPT_C}.items():
        p = write(B / "concepts" / f"concept_{name}.svg", body)
        raster(p, B / "concepts" / f"concept_{name}.png", 512)
    logo = write(B / "logo.svg", LOGO)
    wm = write(B / "wordmark.svg", wordmark())
    raster(wm, B / "wordmark.png", 1600, 520)
    write(B / "palette.json", json.dumps(PALETTE, indent=2))

    # iOS (no transparency: rendered with an opaque background colour)
    ios = B / "ios" / "AppIcon.appiconset"
    images = []
    for idiom, pt, sc in IOS_SIZES:
        px = int(round(pt * sc))
        fn = f"icon_{px}.png"
        raster(logo, ios / fn, px, opaque=True)
        images.append({"idiom": idiom, "size": f"{pt:g}x{pt:g}", "scale": f"{sc}x", "filename": fn})
    write(ios / "Contents.json", json.dumps({"images": images, "info": {"version": 1, "author": "harvestinn"}}, indent=2))

    # Android
    fg = write(B / "android" / "adaptive" / "foreground.svg", FG)
    bg = write(B / "android" / "adaptive" / "background.svg", BG)
    raster(fg, B / "android" / "adaptive" / "ic_launcher_foreground.png", 432)
    raster(bg, B / "android" / "adaptive" / "ic_launcher_background.png", 432)
    for dpi, px in ANDROID_LEGACY.items():
        raster(logo, B / "android" / "legacy" / f"mipmap-{dpi}" / "ic_launcher.png", px)
    raster(logo, B / "android" / "playstore_512.png", 512, opaque=True)

    # Splash + store
    for name, (w, h) in {"splash_portrait": (1242, 2688), "splash_landscape": (2688, 1242)}.items():
        p = write(B / "splash" / f"{name}.svg", splash(w, h))
        raster(p, B / "splash" / f"{name}.png", w, h)
    p = write(B / "store" / "feature_graphic.svg", svg(FEATURE_BODY(), 1024, 500))
    raster(p, B / "store" / "feature_graphic_1024x500.png", 1024, 500)

    raster(logo, B / "icon_256.png", 256)
    print("branding built:", sum(1 for _ in B.rglob("*.png")), "PNGs")


if __name__ == "__main__":
    main()
