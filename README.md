# HarvestInn 🌾🏡

A cozy farm-to-table game for iOS and Android. Grow crops, raise happy animals,
craft goods in village workshops, cook meals for travellers at your own inn,
and trade with other players online.

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

## Decisions made where the brief was open
- **View:** top-down 2.5D (slight 3/4 perspective sprites) instead of true
  isometric. It keeps tap targets large and the grid math simple on phones.
- **Trading inventory:** items are *deposited* into a server-side escrow
  before they can be listed or offered. The server owns those items from then
  on, which is what makes trades server-authoritative while the farm itself
  stays playable offline. See BACKEND_DECISION.md.
- **Time:** real time. All timers are absolute timestamps, so offline progress
  is exact.

## License
Code: MIT ([LICENSE](LICENSE)). Assets: see [CREDITS.md](CREDITS.md).
