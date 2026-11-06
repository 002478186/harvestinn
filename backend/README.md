# HarvestInn backend (Supabase)

Everything the server does lives in SQL migrations (`supabase/migrations/`):
accounts and profiles, cloud saves, and **server-authoritative trading**. There
is no separate server to run. Clients reach these functions through Supabase's
PostgREST `/rest/v1/rpc/<function>` endpoint using the public anon key plus the
player's JWT.

## Security model
- Row Level Security is on for every table. Clients can only `SELECT` what
  the policies allow. **All writes** go through `SECURITY DEFINER` functions
  that read `(select auth.uid())`, check ownership, lock rows (`FOR UPDATE`),
  rate-limit, and log trades in a single transaction.
- The **service_role** key is never used by the game and must never be shipped.
- Player names are filtered server-side (`private.name_is_clean`), with the
  same rules as the client (`scripts/core/name_filter.gd`).

## Deploy
1. Create a free project at https://supabase.com, then go to **Authentication → Providers**:
   - enable **Anonymous sign-ins** (guest login)
   - optional: enable **Apple** and **Google** (for account upgrade), and add
     their client IDs and secrets (see `docs/BACKEND_DECISION.md`)
   - set **Site URL** to a page you control (shown after linking in the browser)
2. Install the CLI: `brew install supabase/tap/supabase`
3. From this folder:
   ```bash
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase db push          # applies supabase/migrations/*.sql
   ```
4. Copy the **Project URL** and **anon public key** (Settings → API) into
   `.env` at the repo root, then run `python3 tools/write_config.py`. For CI,
   add them as GitHub Secrets `SUPABASE_URL` / `SUPABASE_ANON_KEY`.

## Test locally (no Supabase account needed)
```bash
brew install postgresql@16
backend/tests/run.sh
```
This starts a throwaway Postgres, adds a minimal stub of Supabase's `auth`
schema and roles (`tests/supabase_stub.sql`), applies the migrations, and runs
`tests/test_*.sql` (assertion blocks that raise on failure). CI runs the same script.

## End-to-end test (real game client ↔ local stack)
```bash
brew install postgresql@16 postgrest
python3 tools/dev_backend.py --e2e     # Postgres + PostgREST + auth stand-in, then tests/e2e_runner.gd
python3 tools/dev_backend.py           # or keep it running and point config/backend.json at http://127.0.0.1:54321
```
Two guest players list, buy, double-buy (refused), collect, retry a lost
deposit (counted once), hit a cloud-save conflict, add friends and visit farms.

## Functions (RPC)
| Function | Purpose |
|---|---|
| `set_display_name(p_name)` | Rename with moderation |
| `save_game(p_data, p_base_revision)` / `load_game()` | Cloud save with optimistic concurrency (conflict → returns server copy) |
| `deposit(p_request_id, p_items, p_coins)` | Device → escrow/wallet, idempotent, daily caps |
| `collect(p_request_id)` | Escrow/wallet → device, idempotent (a retry returns the same payload) |
| `create_listing`, `cancel_listing`, `buy_listing`, `browse_listings` | Marketplace (price bounds, 4 slots, 48 h expiry, 5% fee, row-locked buy) |
| `price_history(item)`, `market_news()` | Charts and trending items |
| `add_friend(code)`, `list_friends`, `remove_friend`, `visit_farm`, `help_friend`, `claim_helps` | Friends, read-only visits, daily help |
| `send_offer`, `respond_offer`, `cancel_offer` | Direct trades between friends (offered goods are held until answered) |
| `report_player(id, reason)` | Moderation queue (`public.reports`, read via the dashboard) |
| `my_trading()` | Wallet, escrow, my listings and pending offers in one call |

Every trade-related call is written to `public.trade_log`.

### Known trust limit
The farm is simulated on the device so it works offline. The server therefore
can't prove that deposited goods were really farmed. Daily deposit caps (100
of each item; 2,000 + 1,000×level coins) limit what a modified client could
inject. Everything *after* a deposit is fully server-authoritative.
