"""Blender headless: convert Quaternius CC0 .usda models to .glb for Godot.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/usd_to_glb.py -- <in_dir> <out_dir>

Each file is imported into an empty scene and exported as a single GLB (materials kept).
"""
import bpy, pathlib, sys

args = sys.argv[sys.argv.index("--") + 1:]
src, dst = pathlib.Path(args[0]), pathlib.Path(args[1])
dst.mkdir(parents=True, exist_ok=True)
ok = 0
for f in sorted(src.glob("*.usda")):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=str(f))
    out = dst / (f.stem.split("_", 1)[1] + ".glb")      # crop_S_Wheat_1 -> S_Wheat_1.glb
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_apply=True, export_animations=False)
    ok += 1
print(f"converted {ok} files")
