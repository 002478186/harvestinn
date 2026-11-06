# Building HarvestInn

Engine: **Godot 4.7.2** (standard build, GDScript). Export templates must match exactly.

## Common steps
```bash
brew install --cask godot                  # or download 4.7.2 from godotengine.org
godot --headless --path . --import         # first run / fresh checkout
godot --headless --path . --script res://tests/test_runner.gd   # unit + UI smoke tests
python3 tools/simulate_economy.py --check  # economy pacing
backend/tests/run.sh                       # SQL tests (needs postgresql@16)
python3 tools/write_config.py              # writes config/backend.json from .env (optional; offline without it)
```
Install export templates once: Editor → *Manage Export Templates* → Download 4.7.2,
or unzip `Godot_v4.7.2-stable_export_templates.tpz` into
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.

## Android
### Debug APK (what CI builds on every push to `main`)
1. Install **JDK 17** (`brew install --cask temurin@17`) and the **Android SDK**
   (Android Studio, or the command-line tools with `platform-tools`, `build-tools;34.0.0`, `platforms;android-34`).
2. Godot → Editor Settings → Export → Android: set *Java SDK Path* and *Android SDK Path*.
   Godot generates a debug keystore automatically.
3. Export:
   ```bash
   godot --headless --path . --export-debug "Android" build/android/HarvestInn-debug.apk
   adb install -r build/android/HarvestInn-debug.apk
   ```
   Or download the `HarvestInn-android-debug` artifact from the latest GitHub Actions run.

### Release (Play Store)
1. Create an upload keystore. **Never commit it** (`*.jks` and `*.keystore` are git-ignored):
   ```bash
   keytool -genkeypair -v -keystore ~/harvestinn-upload.jks -alias harvestinn -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Godot → Project → Export → Android → *Keystore → Release*: point to it and enter
   the alias and password, which Godot stores in the git-ignored `export_credentials.cfg`.
   For CI, use the env vars `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`
   and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`, with the keystore base64-encoded in a GitHub Secret.
3. Bump `version/code` (integer, +1 each upload) and `version/name` in `export_presets.cfg`.
4. Play Console requires an **AAB**: enable *Gradle Build* in the Android preset
   (Project → Install Android Build Template first), set *Export Format: AAB*, then
   `godot --headless --export-release "Android" build/android/HarvestInn.aab`.
5. Target SDK: Google Play currently requires a recent target API. Godot 4.7's template targets it by default.

## iOS (requires macOS + Xcode)
1. Install **Xcode** from the App Store, open it once, then install command line tools (`xcode-select --install`).
2. An **Apple ID** is enough for testing on your own iPhone (free provisioning, the app expires after 7 days).
   Publishing needs the **Apple Developer Program** ($99/yr).
3. Godot → Project → Export → iOS: set *App Store Team ID* (Xcode → Settings → Accounts → your team),
   bundle id `com.harvestinn.game` (change it if it's taken), export method *Development*.
4. Export the Xcode project:
   ```bash
   godot --headless --path . --export-debug "iOS" build/ios/HarvestInn.xcodeproj
   open build/ios/HarvestInn.xcodeproj
   ```
5. In Xcode: select the HarvestInn target → *Signing & Capabilities* → tick *Automatically manage signing*, choose your team.
   Plug in the iPhone, enable **Developer Mode** on it (Settings → Privacy & Security), pick it as the run destination, then ⌘R.
   The first time, trust the developer on the phone: Settings → General → VPN & Device Management.
6. App Store: in Xcode, Product → Archive → Distribute App → App Store Connect.
   The app icon is `branding/ios/AppIcon.appiconset` (opaque, all sizes); the launch screen uses `branding/splash/`.
7. *Sign in with Apple*: add the capability in Xcode when you turn on account linking (see `docs/BACKEND_DECISION.md`).

## CI
`.github/workflows/android.yml`, on every push to `main` and on `v*` tags:
1. SQL migrations and tests on Postgres (`backend/tests/run.sh`)
2. Godot import, unit tests, economy simulation
3. Debug APK export, uploaded as an artifact

Release signing secrets are only needed if you add a release job:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`SUPABASE_URL`, `SUPABASE_ANON_KEY`.

## Performance notes (60 FPS on mid-range phones)
- *GL Compatibility* renderer (widest GPU support), 2D only, SVGs imported once as textures.
- The farm redraws only on model events. Timers update labels at 2 Hz, not every frame.
- If FPS drops: Godot Debugger → Monitors (draw calls, objects). The usual cause is too many Labels;
  pool them, or replace the per-plot timer labels with a single shader-driven bar.
