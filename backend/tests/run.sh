#!/usr/bin/env bash
# Runs the Supabase migrations + SQL tests against a throwaway local Postgres.
#   backend/tests/run.sh        (needs postgres 15+ binaries: brew install postgresql@16)
set -euo pipefail
cd "$(dirname "$0")/.."
PGBIN="${PGBIN:-$(ls -d /opt/homebrew/opt/postgresql@*/bin 2>/dev/null | tail -1 || true)}"
[ -n "$PGBIN" ] && export PATH="$PGBIN:$PATH"
DIR="$(mktemp -d)"; PORT=55432
trap 'pg_ctl -D "$DIR" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT
initdb -D "$DIR" -U postgres >/dev/null
pg_ctl -D "$DIR" -o "-p $PORT -k $DIR" -l "$DIR/log" start -w >/dev/null
PSQL=(psql -h "$DIR" -p $PORT -U postgres -v ON_ERROR_STOP=1 -q -X)
"${PSQL[@]}" -f tests/supabase_stub.sql
for f in supabase/migrations/*.sql; do "${PSQL[@]}" -f "$f"; done
fail=0
for t in tests/test_*.sql; do
  if "${PSQL[@]}" -f "$t" >/dev/null 2>"$DIR/err"; then echo "PASS $t"; else echo "FAIL $t"; cat "$DIR/err"; fail=1; fi
done
export PSQL_ARGS="-h $DIR -p $PORT -U postgres"
for t in tests/test_*.sh; do
  if "$t" 2>"$DIR/err"; then echo "PASS $t"; else echo "FAIL $t"; cat "$DIR/err"; fail=1; fi
done
exit $fail
