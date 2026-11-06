# Engine decision

**Choice: Godot 4 (GDScript), targeting Godot 4.x stable.**

## Candidates compared

Scores: 1 (poor) to 5 (excellent) for *this* game: a 2D top-down cozy farm on
mid-range phones, maintained by one developer who knows Python.

| Criterion | Godot 4 | Unity 6 | Flutter + Flame |
|---|---|---|---|
| One codebase for iOS + Android | 5. One project, export presets for both | 5 | 5 |
| 2D / isometric performance on mid-range phones | 4. Dedicated 2D renderer, `Compatibility` (GLES3) renderer for older GPUs, batching | 4. Very good, though the URP 2D setup is heavier | 3. Fine for light scenes; Flame has no batching or tilemap tooling at Godot's level |
| Networking / backend SDKs | 3. No first-party Firebase SDK, but `HTTPRequest` + REST works with any HTTP backend (Supabase is pure REST/PostgREST). Nakama has an official Godot SDK | 5. Official SDKs for almost everything | 4. Excellent Firebase/Supabase Dart SDKs |
| Ads / IAP plugins | 3. Community AdMob plugin (poing-studios) and official Google Play Billing and StoreKit plugins; less polished | 5. Unity LevelPlay/AdMob/IAP all first-class | 4. Official `google_mobile_ads`, `in_app_purchase` |
| Licensing cost | 5. MIT, no royalties, no seat fees | 3. Free under a revenue cap, then per-seat Pro; licensing terms have changed before | 5. BSD/MIT |
| Build / CI automation | 4. `godot --headless --export-debug` in a container; tests run headless | 3. Needs a licensed editor in CI (GameCI works, but needs license activation) | 5. `flutter build apk` |
| Ease for a solo Python developer | 5. GDScript is indentation-based, Python-like, small editor download (~100 MB) | 2. C#, large editor, many subsystems | 3. Dart is easy, but the game-engine parts (tiles, particles, scenes) are hand-built |
| **Total** | **29** | 27 | 29 |

## Why Godot wins the tie with Flutter + Flame

- **It is a game engine.** The farm needs tile grids, cameras with pinch zoom,
  particles, tweens, a scene system (farm ↔ inn), audio buses and an animation
  system. Godot has all of these built in. In Flame most of them would be
  assembled from packages.
- **GDScript fits a Python developer's habits** (indentation, `func`, dynamic
  or optional static typing), and the logic layer (`scripts/core/`) is plain
  `RefCounted` classes that are unit-tested headless.
- **No license risk** for a hobby or indie project that may later earn money.
- The weak point, ads and IAP, is stubbed behind `AdsManager` and `IAPManager`
  interfaces. They can be swapped for the AdMob and Play Billing/StoreKit
  plugins later without touching gameplay code.

## Consequences

- Use the **Compatibility renderer** (`gl_compatibility`) for the widest phone
  support, and the **mobile** stretch settings (`canvas_items`, `expand`) for
  safe-area-friendly layouts.
- All art is generated SVG/PNG, so there are no proprietary asset pipelines.
- Backend calls go over HTTPS (`HTTPRequest`); see `BACKEND_DECISION.md`.
