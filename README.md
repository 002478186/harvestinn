# HarvestInn 🌾🏡

A cozy **3D** farm-to-table game for iOS and Android. Create your farmer, walk the
valley, buy a field, plant and harvest by hand, raise happy animals, craft goods in
village workshops, cook for travellers at your own inn, and trade with other players online.

**Everything is a place:** walk *into* the inn (seated guests, Basil's stove, guest-room beds),
every workshop (stations + shelves of finished goods) and the storehouse (your stock as crates).
A 24-minute day/night cycle (`data/economy.json → day_night`) lights lamps, windows, stars and fireflies.

**Controls:** joystick (left thumb) or WASD to walk · drag on the right to turn the camera ·
pinch / wheel to zoom · the green button does whatever is in front of you (buy, plant,
harvest, talk, serve, build). **Hold** it and walk across a field to plant or harvest every plot.

**Engine:** Godot 4.7 (GDScript), see [docs/ENGINE_DECISION.md](docs/ENGINE_DECISION.md)
**Backend:** Supabase (server-authoritative trading), see [docs/BACKEND_DECISION.md](docs/BACKEND_DECISION.md)

## Core loop
Grow → harvest → process → cook → serve guests / sell / trade → coins + XP →
level up → unlock crops, animals, workshops, recipes and land.

## Quick start
```bash
# 1. Install Godot 4.7.2 (macOS: brew install --cask godot)
# 2. Import, then run the tests
godot --headless --path . --import
godot --headless --path . --script res://tests/test_runner.gd
# 3. Play on desktop (portrait window; mouse emulates touch)
godot --path .
# 4. Economy pacing report
python3 tools/simulate_economy.py
```
Online features need a Supabase project: copy `.env.example` to `.env`, fill in
the URL and **anon** key, then run `python3 tools/write_config.py`. Without it
the game runs fully offline and trading screens say "connect to trade".

## Repository layout
| Path | What |
|---|---|
| `scenes/` | Godot scenes (main, farm, inn, UI) |
| `scripts/core/` | Pure game logic (no UI), unit-tested |
| `scripts/autoload/` | Singletons: game state, events, save, network, ads, IAP |
| `scripts/ui/`, `scripts/farm/`, `scripts/inn/` | Presentation layer |
| `data/` | **All** balancing and content: items, crops, recipes, animals, levels, dialogue |
| `assets/` | Generated art, audio, open-licensed fonts |
| `branding/` | Logo SVGs, app icons, splash, store graphics |
| `backend/` | Supabase SQL migrations and edge functions ([README](backend/README.md)) |
| `tests/` | Headless GDScript tests |
| `tools/` | Python helpers: economy simulator, icon/art/audio generators |
| `docs/` | Design and decision documents |

## Builds
CI builds a debug Android APK on every push to `main` (Actions → artifacts).
iOS and release builds: see [docs/BUILD.md](docs/BUILD.md).

## Docs
[Engine](docs/ENGINE_DECISION.md) · [Backend](docs/BACKEND_DECISION.md) · [Economy](docs/ECONOMY.md) ·
[Branding](docs/BRANDING.md) · [Build](docs/BUILD.md) · [Privacy policy draft](docs/PRIVACY.md) · [Backend README](backend/README.md)

## Monetization
`AdsManager` (`scripts/autoload/ads.gd`) and `IAPManager` (`scripts/autoload/iap.gd`) are
**mocks and off by default** (`data/monetization.json`). TODOs in each file explain
how to wire AdMob, Google Play Billing and StoreKit. The game is fully playable without them.

## Dev helpers
`godot --path . -- --demo` loads a mid-game farm · `-- --screen=market` opens a screen ·
`-- --shot=out.png` saves a screenshot and quits · `python3 tools/dev_backend.py` runs a local backend.
Regenerate assets: `tools/gen_art.py`, `tools/gen_audio.py`, `tools/build_branding.py`.

## Localization
UI strings are English source text passed through Godot's `tr()`. Add a translation CSV/PO
in Project Settings → Localization. Dialogue lives in `data/dialogue/<lang>.json`.

## Decisions made where the brief was open
- **View:** full 3D third-person (rebuilt from the first 2D version after play-testing):
  KayKit + Quaternius CC0 models, Godot's Mobile renderer, shadows, glow and fog.
- **Trading inventory:** items are *deposited* into a server-side escrow
  before they can be listed or offered. The server owns those items from then
  on, which is what makes trades server-authoritative while the farm itself
  stays playable offline. See BACKEND_DECISION.md.
- **Time:** real time. All timers are absolute timestamps, so offline progress
  is exact.

## License
Code: MIT ([LICENSE](LICENSE)). Assets: see [CREDITS.md](CREDITS.md).
