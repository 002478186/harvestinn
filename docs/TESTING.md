# Testing HarvestInn

## Automated (run before every commit; CI runs them too)
```bash
godot --headless --path . --script res://tests/test_runner.gd   # 70 unit, UI smoke and first-session tests
backend/tests/run.sh                                             # SQL: accounts, trading, RLS, 2 race tests
python3 tools/simulate_economy.py --check                        # data sanity + 7-day pacing
python3 tools/dev_backend.py --e2e                               # real client ↔ local PostgREST (20 checks)
```

## Visual review
`tools/shots.sh <dir>` renders the nine store-listing views (farm day and night, fields, market, pens,
inn, workshop, storehouse, creator) and `tools/contact_sheet.sh <dir>` combines them into one image.
`-- --perf` prints uncapped FPS, draw calls and triangles every 2 s.
Dev flags (after `--`): `--demo`, `--fresh`, `--clean` (no popups or beacon), `--at=x,z,yaw[,dist]`,
`--inside=inn|<workshop>|storehouse`, `--hour=H`, `--creator`, `--screen=<name>|seeds|r:<workshop>`,
`--tut=N` (jump to a tutorial step), `--serve` (inn guest eats, pays, leaves), `--harvest`, `--wait=s`.

## On your phone: a 15-minute play-test
1. **First launch:** create your farmer (5 looks, 8 outfit colours, a name). Marigold's card then
   guides you: walk (left thumb) to the FOR SALE field and buy it → stand on soil, Plant wheat →
   talk to Basil and cook a Carrot Stew → harvest the glowing wheat → serve the guest at the inn's
   terrace table → sell at Wren's market stall. The tutorial ends with a gift.
2. **Feel:** walk vs run (push the stick further), drag on the right to orbit, pinch to zoom.
   Walking into trees or buildings: the camera slides in instead of clipping.
3. **Sweep:** hold the green button and walk across a field: every plot you cross gets planted
   (or harvested when ripe). Watch the produce pop out and fly to you.
4. **Timers and offline:** plant carrots (2.5 min), close the app completely, wait 3 minutes, reopen:
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
