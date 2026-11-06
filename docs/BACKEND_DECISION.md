# Backend decision

**Choice: Supabase** (Postgres + Auth + PostgREST RPC + Edge Functions). The free tier is enough.

## Comparison

| | Supabase | Firebase | Nakama | PlayFab |
|---|---|---|---|---|
| Free tier | 500 MB DB, 50k MAU auth, 500k edge fn calls | Generous Spark plan, but Cloud Functions need the paid Blaze plan | Open source, but you host it (VM ~$5–10/mo) or pay for Heroic Cloud | Free dev tier, limits per title |
| Server-authoritative trades | **Postgres functions in one transaction, `SELECT … FOR UPDATE` row locks, unique constraints**. This is the strongest guarantee against double-spend and races | Firestore transactions + Cloud Functions (Blaze plan needed) | Server runtime (TS/Lua/Go) + storage engine; very good | CloudScript + economy v2; good but complex |
| Godot integration | Plain REST (PostgREST + GoTrue); a small GDScript client | REST only (no official Godot SDK) | Official Godot SDK | REST only |
| Guest login → Apple/Google | Anonymous sign-ins + `linkIdentity` | Anonymous auth + link | Device ID + link | Custom ID + link |
| Lock-in | Low (it's Postgres) | High | Low | High |

Supabase wins because trading correctness is the main risk. All money and
inventory moves for trades happen inside a single SQL transaction, written
in plain SQL that you can read and test.

## Server-authoritative model

- The **local farm** (crops, workshops, inn) is simulated on the device and
  works offline. It is a single-player game; cheating it only affects yourself.
- Anything that crosses players goes through a **server-side escrow
  inventory and coin wallet** (`wallets`, `escrow_items` tables):
  1. *Deposit*: to list or offer items, the client calls `rpc/deposit_items`.
     The server records the items as owned by the player in escrow, and the
     client removes them locally in the same step (stored in an outbox if
     offline). Deposits are capped per day and per item, so a modified client
     can't flood the market with fake goods.
  2. *List / buy / offer / accept*: Postgres functions that check ownership,
     lock rows, move coins and items atomically, write `trade_log`, and
     enforce rate limits (`rate_limits` table) and min/max price per item.
  3. *Collect*: sold coins and bought items are withdrawn to the device with
     `rpc/collect`, which is idempotent (it marks rows as collected in the
     same transaction).
- Clients **cannot** write to these tables directly. Row Level Security denies
  all direct writes, and only the `SECURITY DEFINER` functions can change them.

## Accounts and keys you must create

1. **Supabase account** (free) → *New project* (any region near your players).
   - Copy **Project URL** and the **anon (publishable) key** into `.env`
     (see `.env.example`). The anon key is safe to ship in the app because RLS
     protects the data.
   - **Never** put the `service_role` key in the game or in git.
   - Auth → Providers: enable **Anonymous sign-ins**.
   - Install the Supabase CLI and run the migrations in
     `backend/supabase/migrations` (`supabase db push`). See `backend/README.md`.
2. **Sign in with Apple** (optional upgrade path): an **Apple Developer Program**
   membership ($99/yr, which you need anyway to ship on iOS). Create a Services
   ID + key, then paste them into Supabase Auth → Apple.
3. **Google sign-in**: a **Google Cloud** project → OAuth client IDs
   (Android + Web) → paste into Supabase Auth → Google.
4. **Google Play Console** ($25 one-time) to publish on Android.
5. Later, when monetization is turned on: **AdMob** account, and in-app
   products set up in App Store Connect / Play Console.

GitHub Secrets for CI (only for release builds; debug CI needs none):
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.
