"""Blender headless: bake the goat from Quaternius' CC0 deer (no goat exists in the packs).

  blender -b --python tools/make_goat.py -- <UltimateAnimatedAnimals_SK_Deer.usda> <out SK_Goat.glb>

Recolours the coat cream/tan and adds two swept-back horns.
"""
import bpy, sys, math

src, out = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=src)
coat = {"Main": (0.80, 0.66, 0.50), "Main_Light": (0.97, 0.94, 0.88), "Main_Dark": (0.40, 0.29, 0.21), "Eye_Lighter": (0.80, 0.66, 0.50)}
for m in bpy.data.materials:
    if m.name in coat and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Base Color"].default_value = (*coat[m.name], 1.0)
horn = bpy.data.materials.new("Horn")
horn.use_nodes = True
horn.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.36, 0.30, 1.0)
for x in (-0.2, 0.2):   # Blender space: nose at -Y, ear tips at (±0.7, -1.64, 4.26)
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.15, radius2=0.03, depth=1.0, location=(x, -1.75, 4.25))
    c = bpy.context.object
    c.rotation_euler = (math.radians(-35), 0, math.radians(8 if x > 0 else -8))
    c.data.materials.append(horn)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_animations=False)
