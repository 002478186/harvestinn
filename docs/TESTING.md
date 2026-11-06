# Testing HarvestInn

## Automated (run before every commit; CI runs them too)
```bash
godot --headless --path . --script res://tests/test_runner.gd   # 55 unit + UI smoke tests
backend/tests/run.sh                                             # SQL: accounts, trading, RLS, 2 race tests
python3 tools/simulate_economy.py --check                        # data sanity + 7-day pacing
python3 tools/dev_backend.py --e2e                               # real client ↔ local PostgREST (20 checks)
```

## Visual review
`tools/shots.sh <dir>` renders the demo farm from five viewpoints and `tools/contact_sheet.sh <dir>`
combines them into one image. `-- --perf` prints FPS, draw calls and triangles every 2 s.

## On your phone: a 15-minute play-test
1. **First launch:** the Innkeeper card appears. Follow it: plant wheat → open the Inn → kitchen → cook
   Carrot Stew → harvest wheat → serve the guest (coins and hearts fly to the top bar) → Market → sell.
   The tutorial ends with a gift and then the daily reward.
2. **Touch:** drag to pan, pinch to zoom, tap plots. Long-press the Inn for half a second, drag it, and release:
   it moves (and won't drop onto the fields).
3. **Planting mode:** pick a seed, then keep tapping empty plots; tap *Done* to stop.
4. **Timers and offline:** plant carrots (5 min), close the app completely, wait 6 minutes, reopen:
   "Welcome back" lists what finished, and the carrots are ready.
5. **Level-ups:** at level 2 a popup lists the new unlocks and Marigold says something new.
6. **Workshops:** at level 4 buy the Windmill (Shop → Buildings), make flour, collect it.
7. **Storage:** fill the silo and see the "Silo is full" message; upgrade it in Shop → Farm.
8. **Settings → My Farmer:** change skin, hair and hat, set a name (try a rude one: it's refused).
9. **Sound:** every tap clicks, harvests pop, coins jingle. Mute music and SFX separately in Settings.
10. **Safe area:** nothing sits under the Dynamic Island or the home bar, and every button is easy to hit.
11. **Offline trading:** with no backend configured, Market → *Online market* and Friends show the
    "Connect to the internet to trade" card. Everything else works.

Want to see the late game straight away? On desktop run `godot --path . -- --demo`
(level 22 with workshops and all four animal homes).

## Notes
- The phone build has **no backend configured** (no Supabase keys yet), so online trading
  is tested on the Mac with `tools/dev_backend.py`. After you create the Supabase project
  (docs/BACKEND_DECISION.md), put the keys in `.env` and rebuild.
- With a free Apple ID, builds installed from Xcode expire after **7 days**. Re-run the install to refresh.
