# Credits

HarvestInn is an original game. Its names, characters, art, music and UI are not
taken from any other game.

## Code
- HarvestInn contributors, MIT License.
- [Godot Engine](https://godotengine.org), MIT License.

## 3D art (all CC0 1.0, thank you!)
- **Characters, village buildings, nature, food, restaurant and furniture props:** KayKit by
  Kay Lousberg (www.kaylousberg.com): Adventurers Character Pack, Medieval Hexagon Pack,
  Restaurant Bits, Furniture Bits (`assets/3d/characters`, `village`, `restaurant`, `furniture`).
- **Crops (with growth stages), farm buildings, farm animals:** Quaternius (quaternius.com):
  Ultimate Crops, Farm Buildings, Farm Animals, via the CC0 mirror
  github.com/chibifire-stages/quaternius-stage, converted from USD to glTF with Blender
  (`tools/usd_to_glb.py`) into `assets/3d/crops`, `farm`, `animals`.
- **Hen:** Quaternius Ultimate Monsters (chicken), same CC0 mirror (`assets/3d/animals/SK_Chicken.glb`).
- **Goat:** baked from the Quaternius Ultimate Animated Animals deer (CC0): recoloured coat plus horns,
  by `tools/make_goat.py` (`assets/3d/animals/SK_Goat.glb`).
- Ground, grass tufts, water, fountain, lamps and flower beds are generated in code (`scripts/world/world.gd`).
- Every model is restyled at runtime by `scripts/world/toon.gd` (toon shading, rim light, one palette).

## 2D art
UI icons, item icons, portraits and the logo are procedurally generated SVG
(`tools/gen_art.py`, `branding/`), CC0 1.0 with the project.

## Audio
- SFX, music and the ambience loop are synthesized from scratch by `tools/gen_audio.py` (CC0 1.0).
- Footstep/coin/jump sounds: Kenney (kenney.nl), Starter Kit 3D Platformer, CC0 1.0 (`assets/audio/kenney`).

## Fonts
Listed in assets/fonts/ with their licenses (SIL Open Font License 1.1).
