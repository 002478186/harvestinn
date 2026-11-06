begin;
-- three players: seller A, buyer B, stranger C
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b2'), ('00000000-0000-0000-0000-0000000000c3');
set role authenticated;

-- A deposits and lists
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ declare r jsonb; lid bigint; begin
  r := public.deposit('11111111-0000-0000-0000-000000000001', '{"egg": 10}', 0);
  assert r ->> 'ok' = 'true', 'deposit ok';
  r := public.deposit('11111111-0000-0000-0000-000000000001', '{"egg": 10}', 0);   -- retried request
  assert (select qty from public.escrow where item = 'egg') = 10, 'idempotent deposit: still 10';
  begin perform public.deposit(gen_random_uuid(), '{"egg": 95}', 0); assert false, 'cap';
  exception when others then assert sqlerrm = 'deposit_cap', 'daily cap: ' || sqlerrm; end;
  begin perform public.deposit(gen_random_uuid(), '{"gold_bar": 1}', 0); assert false, 'unknown';
  exception when others then assert sqlerrm = 'unknown_item', sqlerrm; end;
  begin perform public.deposit(gen_random_uuid(), '{"egg": -3}', 0); assert false, 'negative';
  exception when others then assert sqlerrm = 'bad_quantity', sqlerrm; end;
  begin perform public.deposit(gen_random_uuid(), '{"egg": 1.5}', 0); assert false, 'fraction';
  exception when others then assert sqlerrm = 'bad_quantity', sqlerrm; end;
  -- price limits: egg base 12 -> 6..36
  begin perform public.create_listing('egg', 5, 100); assert false, 'too pricey';
  exception when others then assert sqlerrm = 'price_out_of_range', sqlerrm; end;
  begin perform public.create_listing('egg', 50, 20); assert false, 'not owned';
  exception when others then assert sqlerrm = 'not_enough_items', sqlerrm; end;
  r := public.create_listing('egg', 5, 20);
  assert (select qty from public.escrow where item = 'egg') = 5, 'listed items leave escrow';
  perform public.create_listing('egg', 1, 20);
  perform public.create_listing('egg', 1, 20);
  perform public.create_listing('egg', 1, 20);
  begin perform public.create_listing('egg', 1, 20); assert false, 'slots';
  exception when others then assert sqlerrm = 'listing_slots_full', sqlerrm; end;
  begin perform public.buy_listing((r ->> 'id')::bigint); assert false, 'own';
  exception when others then assert sqlerrm = 'own_listing', sqlerrm; end;
end $$;

-- B buys
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
do $$ declare r jsonb; lid bigint; begin
  lid := (select id from public.browse_listings(array['egg']) where qty = 5);
  begin perform public.buy_listing(lid); assert false, 'broke';
  exception when others then assert sqlerrm = 'not_enough_coins', sqlerrm; end;
  perform public.deposit(gen_random_uuid(), '{}', 150);
  r := public.buy_listing(lid);
  assert (r ->> 'coins')::int = 100, 'paid 5 x 20';
  assert (select coins from public.wallets where user_id = (select auth.uid())) = 50, 'buyer wallet 150-100';
  assert (select qty from public.escrow where item = 'egg') = 5, 'buyer got eggs in escrow';
  begin perform public.buy_listing(lid); assert false, 'double buy';
  exception when others then assert sqlerrm = 'already_sold', sqlerrm; end;
  r := public.collect('22222222-0000-0000-0000-000000000001');
  assert (r -> 'items' ->> 'egg')::int = 5 and (r ->> 'coins')::int = 50, 'collect to device';
  r := public.collect('22222222-0000-0000-0000-000000000001');
  assert (r -> 'items' ->> 'egg')::int = 5, 'collect retry returns same result (idempotent)';
  assert (select count(*) from public.escrow where qty > 0) = 0, 'escrow empty after collect';
  assert (select volume from public.price_history where item = 'egg') = 5, 'price history';
  assert (select count(*) from public.market_news()) = 1, 'market news';
end $$;

-- Seller got paid minus 5% fee
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin
  assert (select coins from public.wallets where user_id = (select auth.uid())) = 95, 'seller 100 - 5 fee';
  assert (select count(*) from public.trade_log where kind = 'buy') = 1, 'trade logged';
  begin
    update public.wallets set coins = 1000000;
    assert false, 'direct wallet write must fail';
  exception when insufficient_privilege then null; end;
end $$;

-- Friends, help, offers
do $$ declare b_code text; r jsonb; oid bigint; begin
  b_code := (select friend_code from public.profiles where id = '00000000-0000-0000-0000-0000000000b2');
  begin perform public.send_offer('00000000-0000-0000-0000-0000000000b2', '{}', 10, '{}', 0); assert false, 'need friends';
  exception when others then assert sqlerrm = 'not_friends', sqlerrm; end;
  perform public.add_friend(lower(b_code));
  assert (select count(*) from public.list_friends()) = 1, 'friend added';
  r := public.help_friend('00000000-0000-0000-0000-0000000000b2', 3);
  assert (r ->> 'coins')::int = 15, 'help reward';
  begin perform public.help_friend('00000000-0000-0000-0000-0000000000b2', 4); assert false, 'once a day';
  exception when others then assert sqlerrm = 'already_helped', sqlerrm; end;
  assert public.visit_farm('00000000-0000-0000-0000-0000000000b2') ? 'level', 'visit snapshot';
  -- offer: A gives 2 eggs + 10 coins, wants 1 milk
  r := public.send_offer('00000000-0000-0000-0000-0000000000b2', '{"egg": 2}', 10, '{"milk": 1}', 0);
  oid := (r ->> 'id')::bigint;
  assert (select qty from public.escrow where item = 'egg' and user_id = (select auth.uid())) = 0, 'offer holds the last 2 eggs';
  perform set_config('harvest.offer', oid::text, false);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false);
do $$ begin
  begin perform public.respond_offer(current_setting('harvest.offer')::bigint, true); assert false, 'stranger';
  exception when others then assert sqlerrm = 'not_found', sqlerrm; end;
  begin perform public.visit_farm('00000000-0000-0000-0000-0000000000a1'); assert false, 'not friends';
  exception when others then assert sqlerrm = 'not_friends', sqlerrm; end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
do $$ declare oid bigint := current_setting('harvest.offer')::bigint; begin
  assert (select count(*) from public.claim_helps()) = 1, 'owner sees the help';
  assert (select count(*) from public.claim_helps()) = 0, 'only once';
  begin perform public.respond_offer(oid, true); assert false, 'no milk';
  exception when others then assert sqlerrm = 'not_enough_items', sqlerrm; end;
  perform public.deposit(gen_random_uuid(), '{"milk": 1}', 0);
  perform public.respond_offer(oid, true);
  assert (select qty from public.escrow where item = 'egg' and user_id = (select auth.uid())) = 2, 'B got eggs';
  assert (select coins from public.wallets where user_id = (select auth.uid())) = 10, 'B got coins';
  assert (select count(*) from public.escrow where user_id <> (select auth.uid())) = 0, 'RLS: cannot see other escrow';
  begin perform public.respond_offer(oid, true); assert false, 'twice';
  exception when others then assert sqlerrm = 'not_pending', sqlerrm; end;
  perform public.report_player('00000000-0000-0000-0000-0000000000a1', 'test report');
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin
  assert (select qty from public.escrow where item = 'milk') = 1, 'A got milk';
  assert (public.my_trading() ->> 'wallet')::int = 100, '95 sale + 15 help - 10 offered';
end $$;

-- rate limiting: wrong friend codes still count, so codes can't be brute-forced
do $$ declare hit boolean := false; begin
  assert public.add_friend('ZZZZZZZZ') ->> 'error' = 'unknown_code', 'unknown code';
  for i in 1..12 loop
    begin perform public.add_friend('ZZZZZZZZ');
    exception when others then if sqlerrm = 'rate_limited' then hit := true; end if; end;
  end loop;
  assert hit, 'rate limit kicks in';
end $$;
rollback;
