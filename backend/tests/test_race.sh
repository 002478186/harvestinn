#!/usr/bin/env bash
# Two buyers hit the same listing at the same instant: exactly one may win.
# Called by run.sh with the connection args in $PSQL_ARGS.
set -euo pipefail
P=(psql $PSQL_ARGS -v ON_ERROR_STOP=1 -q -X -t -A)
"${P[@]}" >/dev/null <<'SQL'
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d2'), ('00000000-0000-0000-0000-0000000000d3');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select public.deposit(gen_random_uuid(), '{"wool": 1}', 0);
select public.create_listing('wool', 1, 30);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select public.deposit(gen_random_uuid(), '{}', 100);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', false);
select public.deposit(gen_random_uuid(), '{}', 100);
SQL
LID=$("${P[@]}" -c "select id from public.listings where item='wool' and status='active'")
buy() { "${P[@]}" -c "set role authenticated; select set_config('request.jwt.claim.sub','$1',false); begin; select public.buy_listing($LID); select pg_sleep(0.5); commit;" >/dev/null 2>&1 && echo win || echo lose; }
buy 00000000-0000-0000-0000-0000000000d2 > /tmp/harvest_race_1 &
buy 00000000-0000-0000-0000-0000000000d3 > /tmp/harvest_race_2 &
wait
WINS=$(cat /tmp/harvest_race_1 /tmp/harvest_race_2 | grep -c win || true)
PAID=$("${P[@]}" -c "select count(*) from public.wallets where coins = 70")
rm -f /tmp/harvest_race_1 /tmp/harvest_race_2
[ "$WINS" = "1" ] && [ "$PAID" = "1" ] || { echo "race: wins=$WINS paid=$PAID"; exit 1; }

# Collect racing a listing of the same items: the wool must end up in exactly one place.
U=00000000-0000-0000-0000-0000000000e1
"${P[@]}" >/dev/null -c "insert into auth.users (id) values ('$U'); set role authenticated; select set_config('request.jwt.claim.sub','$U',false); select public.deposit(gen_random_uuid(), '{\"wool\": 5}', 0);"
as_u() { "${P[@]}" -c "set role authenticated; select set_config('request.jwt.claim.sub','$U',false); $1" 2>&1; }
( as_u "begin; select public.collect(gen_random_uuid()); select pg_sleep(0.5); commit;" > /tmp/harvest_race_c ) &
sleep 0.1
( as_u "select public.create_listing('wool', 5, 30);" > /tmp/harvest_race_l ) &
wait
COLLECTED=$(grep -c '"wool": 5' /tmp/harvest_race_c || true)
LISTED=$("${P[@]}" -c "select count(*) from public.listings where seller='$U'")
rm -f /tmp/harvest_race_c /tmp/harvest_race_l
[ $((COLLECTED + LISTED)) = "1" ] || { echo "collect/list race duplicated: collected=$COLLECTED listed=$LISTED"; exit 1; }
