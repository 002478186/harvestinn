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

## Functions (RPC)
| Function | Purpose |
|---|---|
| `set_display_name(p_name)` | Rename with moderation |
| `save_game(p_data, p_base_revision)` / `load_game()` | Cloud save with optimistic concurrency (conflict → returns server copy) |
| *(trading, friends, market news: see the trading migration)* | |
