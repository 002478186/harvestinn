-- Each test file runs in one transaction and raises on the first failed assertion.
begin;
insert into auth.users (id) values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.profiles) = 2, 'profiles created by trigger';
  assert (select friend_code from public.profiles limit 1) ~ '^[A-HJ-NP-Z2-9]{8}$', 'friend code format';
  assert private.name_is_clean('Farmer Joy'), 'clean name';
  assert not private.name_is_clean('Sh1t Farmer'), 'l33t blocked';
  assert not private.name_is_clean('f.u.c.k'), 'punctuation blocked';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$ declare r jsonb; begin
  r := public.set_display_name('Hazel');
  assert r ->> 'ok' = 'true', 'rename ok';
  r := public.set_display_name('b1tch');
  assert r ->> 'error' = 'name_blocked', 'blocked name refused';
  r := public.save_game('{"version":2,"level":7,"coins":10}', 0);
  assert (r ->> 'revision')::int = 1, 'first save rev 1';
  r := public.save_game('{"version":2,"level":8,"coins":20}', 1);
  assert (r ->> 'revision')::int = 2, 'second save rev 2';
  r := public.save_game('{"version":2,"level":3,"coins":1}', 1);   -- stale device
  assert (r ->> 'conflict')::boolean, 'stale base revision -> conflict';
  assert (r -> 'data' ->> 'level')::int = 8, 'conflict returns server copy';
  assert (public.load_game() ->> 'revision')::int = 2, 'load';
  assert (select level from public.profiles where id = (select auth.uid())) = 8, 'profile level synced';
end $$;

-- RLS: no direct writes, and saves are private.
do $$ begin
  begin
    update public.profiles set level = 50;
    assert false, 'direct profile update must fail';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.cloud_saves (user_id, save_version, data) values ((select auth.uid()), 1, '{}');
    assert false, 'direct save insert must fail';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
do $$ begin
  assert (select count(*) from public.cloud_saves) = 0, 'cannot read other players saves';
  assert (select count(*) from public.profiles) = 2, 'profiles are public';
end $$;
rollback;
