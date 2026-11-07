# HarvestInn v0.2 work report (not shipped)

All eight items on the list are done and committed locally (8 commits after `3aebf5a`).
The three gates pass: 70 Godot tests, the economy check, and the backend SQL tests.
**I did not push, tag or install**, because the 10/10 bar is not honestly met yet (see below).

Screenshots of the current state: `docs/shots/` (`sheet.png` shows all nine views side by side).
Re-render them with `tools/shots.sh <dir>` and `tools/contact_sheet.sh <dir>`.

## Honest rating per area

| Area | Before | Now | Why not 10 |
|---|---|---|---|
| Living world | 5 | 8 | Guests walk in, sit, eat, pay and walk out; villagers stroll (7 by day, 2 at night); animals waddle and call out. Villagers walk through the player and each other. |
| Art cohesion | 5 | 7.5 | One toon, rim-lit look with a shared palette across all packs; real goat and hen models; warm rooms. The ground is still a flat noise texture; rooms are sparse next to Hay Day's clutter. |
| Character variety | 4 | 8 | 5 bodies × 4 faces × 5 hats, capes, carried props, recoloured clothes; seeded per guest. The silhouettes all come from one character pack. |
| World instead of panels | 6 | 8 | Stall crates and a price board, walk-up pens, radial seed and recipe pickers. The shop, barn list and orders are still sheets (allowed by the brief). |
| Game feel | 5 | 7.5 | Squash and stretch, camera punch, dust, wind, springy buttons, haptic tiers. Haptics not felt on a device. |
| Audio | 4 | 6 | Day and night music crossfade, positional ambience, a sound per action, ducking. Everything is synthesized and **I could not listen to it**: checked numerically only. |
| First 10 minutes | 6 | 8 | Beacon and edge arrow, daily goals, and a simulated first session with no reward gap over 60 s. Not play-tested by a person. |
| iPhone performance | ? | ? | Desktop: about 330 FPS uncapped, 110–170k primitives, 400–500 draw calls. **Not measured on the iPhone 17 Pro Max.** |

## Still missing before 10/10
1. A device run: steady 60 FPS with `--perf`, the safe area, haptics, and kill-the-app save survival.
2. A listening pass on the phone; probably replace the synth music with real CC0 recordings.
3. Art: textured ground and paths, denser interior dressing, a store-quality hero shot.
4. Villagers that avoid the player and each other (they pass through today).
5. A real person play-testing the first 10 minutes.
6. Draw calls: crops should be MultiMesh (each plot is 4 meshes today).

## Decisions I made (also in the commit messages)
- **Top view everywhere**, as you asked mid-run: −55° at 17 m, leading the farmer by 3.5 m; orbit limited to −42…−72°.
- No goat exists in the CC0 packs, so `tools/make_goat.py` bakes one from the Quaternius deer.
- Rim light instead of outlines (half the draw calls).
- Faster early crops (wheat 45 s, carrot 150 s, first stew 20 s), with the XP curve exponent raised from 1.55 to 1.6 so the 7-day pacing stays in its target.
