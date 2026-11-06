-- HarvestInn: server-authoritative trading, friends, farm help, price history, reports.
--
-- Model: the farm is simulated on the device, so anything that crosses players first
-- moves into server-held ESCROW (items) and a WALLET (coins). From then on only these
-- functions can move it. Every function:
--   * identifies the caller with (select auth.uid()), never a client-supplied id
--   * validates items/prices against item_rules
--   * locks the rows it changes (FOR UPDATE) inside one transaction
--   * is rate-limited and writes trade_log
-- Device <-> server transfers (deposit / collect) are idempotent by request_id, so a
-- lost response can be retried without duplicating or losing anything.

-- ------------------------------------------------------------------ tables
create table public.item_rules (
  item text primary key,
  base_price int not null check (base_price > 0),
  min_price int not null check (min_price > 0),
  max_price int not null check (max_price >= min_price)
);

create table public.wallets (
  user_id uuid primary key references auth.users (id) on delete cascade,
  coins bigint not null default 0 check (coins >= 0)
);

create table public.escrow (
  user_id uuid not null references auth.users (id) on delete cascade,
  item text not null references public.item_rules (item),
  qty int not null check (qty >= 0),
  primary key (user_id, item)
);

create table private.ops (                 -- idempotency ledger for device<->server moves
  request_id uuid primary key,
  user_id uuid not null,
  kind text not null,
  result jsonb not null,
  at timestamptz not null default now()
);

create table private.deposits_daily (
  user_id uuid not null,
  day date not null,
  item text not null,                      -- 'coins' for coin deposits
  qty bigint not null default 0,
  primary key (user_id, day, item)
);

create table private.rate_events (
  user_id uuid not null,
  action text not null,
  at timestamptz not null default now()
);
create index rate_events_lookup on private.rate_events (user_id, action, at);

create table public.listings (
  id bigint generated always as identity primary key,
  seller uuid not null references auth.users (id) on delete cascade,
  item text not null references public.item_rules (item),
  qty int not null check (qty between 1 and 999),
  price_each int not null check (price_each > 0),
  status text not null default 'active' check (status in ('active', 'sold', 'cancelled', 'expired')),
  buyer uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  sold_at timestamptz
);
create index listings_browse on public.listings (item, price_each) where status = 'active';
create index listings_seller on public.listings (seller, status);
create index listings_buyer on public.listings (buyer);

create table public.trade_offers (
  id bigint generated always as identity primary key,
  from_user uuid not null references auth.users (id) on delete cascade,
  to_user uuid not null references auth.users (id) on delete cascade,
  give_items jsonb not null default '{}',
  give_coins bigint not null default 0 check (give_coins >= 0),
  want_items jsonb not null default '{}',
  want_coins bigint not null default 0 check (want_coins >= 0),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (from_user <> to_user)
);
create index trade_offers_to on public.trade_offers (to_user, status);
create index trade_offers_from on public.trade_offers (from_user, status);

create table public.friendships (
  user_a uuid not null references auth.users (id) on delete cascade,
  user_b uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index friendships_b on public.friendships (user_b);

create table public.friend_help (
  helper uuid not null references auth.users (id) on delete cascade,
  owner uuid not null references auth.users (id) on delete cascade,
  day date not null default current_date,
  plot int not null,
  seen boolean not null default false,
  at timestamptz not null default now(),
  primary key (helper, owner, day)
);
create index friend_help_owner on public.friend_help (owner, seen);

create table public.trade_log (
  id bigint generated always as identity primary key,
  kind text not null,          -- deposit, collect, list, cancel, buy, offer, accept, decline, help
  actor uuid not null,
  counterparty uuid,
  item text,
  qty bigint,
  coins bigint,
  ref bigint,
  detail jsonb,
  at timestamptz not null default now()
);
create index trade_log_actor on public.trade_log (actor, at);

create table public.price_history (
  item text not null references public.item_rules (item),
  day date not null,
  volume bigint not null default 0,
  coins bigint not null default 0,
  primary key (item, day)
);

create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references auth.users (id) on delete cascade,
  reported uuid not null references auth.users (id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 300),
  at timestamptz not null default now()
);

-- ------------------------------------------------------------------ RLS (reads only)
alter table public.item_rules enable row level security;
alter table public.wallets enable row level security;
alter table public.escrow enable row level security;
alter table public.listings enable row level security;
alter table public.trade_offers enable row level security;
alter table public.friendships enable row level security;
alter table public.friend_help enable row level security;
alter table public.trade_log enable row level security;
alter table public.price_history enable row level security;
alter table public.reports enable row level security;

create policy item_rules_read on public.item_rules for select to authenticated using (true);
create policy wallets_own on public.wallets for select to authenticated using ((select auth.uid()) = user_id);
create policy escrow_own on public.escrow for select to authenticated using ((select auth.uid()) = user_id);
create policy listings_read on public.listings for select to authenticated
  using ((status = 'active' and expires_at > now()) or seller = (select auth.uid()) or buyer = (select auth.uid()));
create policy offers_own on public.trade_offers for select to authenticated
  using ((select auth.uid()) in (from_user, to_user));
create policy friendships_own on public.friendships for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));
create policy friend_help_own on public.friend_help for select to authenticated
  using ((select auth.uid()) in (helper, owner));
create policy trade_log_own on public.trade_log for select to authenticated
  using ((select auth.uid()) in (actor, counterparty));
create policy price_history_read on public.price_history for select to authenticated using (true);
-- reports: no read policy (moderators use the dashboard / service role)

revoke insert, update, delete on public.item_rules, public.wallets, public.escrow, public.listings,
  public.trade_offers, public.friendships, public.friend_help, public.trade_log, public.price_history,
  public.reports from anon, authenticated;

-- ------------------------------------------------------------------ helpers
create or replace function private.me()
returns uuid language plpgsql stable set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.profiles where id = uid and is_banned) then raise exception 'banned'; end if;
  return uid;
end $$;

-- At most p_max calls of p_action per p_window per user.
create or replace function private.rate_limit(p_uid uuid, p_action text, p_max int, p_window interval default '1 minute')
returns void language plpgsql set search_path = '' as $$
begin
  if (select count(*) from private.rate_events
      where user_id = p_uid and action = p_action and at > now() - p_window) >= p_max then
    raise exception 'rate_limited';
  end if;
  insert into private.rate_events (user_id, action) values (p_uid, p_action);
end $$;

-- Adds (positive) or removes (negative) escrow items; raises if it would go below zero.
create or replace function private.escrow_add(p_uid uuid, p_item text, p_qty bigint)
returns void language plpgsql set search_path = '' as $$
declare cur int;
begin
  if p_qty = 0 then return; end if;
  if not exists (select 1 from public.item_rules where item = p_item) then raise exception 'unknown_item'; end if;
  insert into public.escrow (user_id, item, qty) values (p_uid, p_item, 0) on conflict do nothing;
  select qty into cur from public.escrow where user_id = p_uid and item = p_item for update;
  if cur + p_qty < 0 then raise exception 'not_enough_items'; end if;
  update public.escrow set qty = qty + p_qty where user_id = p_uid and item = p_item;
end $$;

create or replace function private.wallet_add(p_uid uuid, p_coins bigint)
returns void language plpgsql set search_path = '' as $$
declare cur bigint;
begin
  if p_coins = 0 then return; end if;
  insert into public.wallets (user_id) values (p_uid) on conflict do nothing;
  select coins into cur from public.wallets where user_id = p_uid for update;
  if cur + p_coins < 0 then raise exception 'not_enough_coins'; end if;
  update public.wallets set coins = coins + p_coins where user_id = p_uid;
end $$;

-- Validates an {item: qty} object: known items, positive whole quantities, <= 20 kinds.
create or replace function private.check_items(p_items jsonb)
returns void language plpgsql stable set search_path = '' as $$
declare k text; v jsonb;
begin
  if jsonb_typeof(p_items) <> 'object' then raise exception 'bad_items'; end if;
  if (select count(*) from jsonb_object_keys(p_items)) > 20 then raise exception 'bad_items'; end if;
  for k, v in select * from jsonb_each(p_items) loop
    if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> floor((v #>> '{}')::numeric)
       or (v #>> '{}')::bigint < 1 or (v #>> '{}')::bigint > 999 then
      raise exception 'bad_quantity';
    end if;
    if not exists (select 1 from public.item_rules where item = k) then raise exception 'unknown_item'; end if;
  end loop;
end $$;

-- Returns the stored result if this request_id was already processed.
create or replace function private.op_done(p_req uuid, p_uid uuid)
returns jsonb language sql stable set search_path = '' as $$
  select result from private.ops where request_id = p_req and user_id = p_uid;
$$;

create or replace function private.expire_listings()
returns void language plpgsql set search_path = '' as $$
declare l record;
begin
  for l in select * from public.listings where status = 'active' and expires_at <= now() for update skip locked loop
    perform private.escrow_add(l.seller, l.item, l.qty);
    update public.listings set status = 'expired' where id = l.id;
  end loop;
end $$;

-- ------------------------------------------------------------------ device <-> server

-- Move items/coins from the device into escrow/wallet. Capped per item per day
-- (the device simulation is not trusted beyond reasonable daily amounts).
create or replace function public.deposit(p_request_id uuid, p_items jsonb, p_coins bigint default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := private.me();
  prev jsonb := private.op_done(p_request_id, uid);
  k text; v jsonb;
  item_cap constant int := 100;          -- per item per day (economy.json trade.daily_deposit_cap_per_item)
  coin_cap bigint;
  day_total bigint;
  res jsonb;
begin
  if prev is not null then return prev; end if;
  perform private.rate_limit(uid, 'deposit', 30);
  perform private.check_items(p_items);
  if p_coins < 0 then raise exception 'bad_quantity'; end if;
  -- coin cap grows with level: 2,000 + 1,000 per level per day
  coin_cap := 2000 + 1000 * (select level from public.profiles where id = uid);
  for k, v in select * from jsonb_each(p_items) loop
    insert into private.deposits_daily (user_id, day, item, qty) values (uid, current_date, k, 0) on conflict do nothing;
    update private.deposits_daily set qty = qty + (v #>> '{}')::bigint
      where user_id = uid and day = current_date and item = k returning qty into day_total;
    if day_total > item_cap then raise exception 'deposit_cap'; end if;
    perform private.escrow_add(uid, k, (v #>> '{}')::bigint);
  end loop;
  if p_coins > 0 then
    insert into private.deposits_daily (user_id, day, item, qty) values (uid, current_date, 'coins', 0) on conflict do nothing;
    update private.deposits_daily set qty = qty + p_coins where user_id = uid and day = current_date and item = 'coins';
    if (select qty from private.deposits_daily where user_id = uid and day = current_date and item = 'coins') > coin_cap then
      raise exception 'deposit_cap';
    end if;
    perform private.wallet_add(uid, p_coins);
  end if;
  res := jsonb_build_object('ok', true);
  insert into private.ops (request_id, user_id, kind, result) values (p_request_id, uid, 'deposit', res);
  insert into public.trade_log (kind, actor, coins, detail) values ('deposit', uid, p_coins, p_items);
  return res;
end $$;

-- Withdraw everything in escrow + wallet to the device. Idempotent: retrying the same
-- request_id returns the same items again so the device can add them exactly once.
create or replace function public.collect(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := private.me();
  prev jsonb := private.op_done(p_request_id, uid);
  items jsonb;
  coins bigint;
  res jsonb;
begin
  if prev is not null then return prev; end if;
  perform private.rate_limit(uid, 'collect', 20);
  select coalesce(jsonb_object_agg(item, qty), '{}') into items
    from (select item, qty from public.escrow where user_id = uid and qty > 0 for update) e;
  delete from public.escrow where user_id = uid;
  select coalesce((select w.coins from public.wallets w where user_id = uid for update), 0) into coins;
  update public.wallets set coins = 0 where user_id = uid;
  res := jsonb_build_object('ok', true, 'items', items, 'coins', coins);
  insert into private.ops (request_id, user_id, kind, result) values (p_request_id, uid, 'collect', res);
  insert into public.trade_log (kind, actor, coins, detail) values ('collect', uid, coins, items);
  return res;
end $$;

-- ------------------------------------------------------------------ marketplace

create or replace function public.create_listing(p_item text, p_qty int, p_price_each int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := private.me();
  r public.item_rules;
  new_id bigint;
begin
  perform private.rate_limit(uid, 'list', 10);
  select * into r from public.item_rules where item = p_item;
  if not found then raise exception 'unknown_item'; end if;
  if p_qty < 1 or p_qty > 999 then raise exception 'bad_quantity'; end if;
  if p_price_each < r.min_price or p_price_each > r.max_price then raise exception 'price_out_of_range'; end if;
  perform private.expire_listings();
  if (select count(*) from public.listings where seller = uid and status = 'active') >= 4 then
    raise exception 'listing_slots_full';
  end if;
  perform private.escrow_add(uid, p_item, -p_qty);              -- raises if not owned
  insert into public.listings (seller, item, qty, price_each, expires_at)
    values (uid, p_item, p_qty, p_price_each, now() + interval '48 hours') returning id into new_id;
  insert into public.trade_log (kind, actor, item, qty, coins, ref) values ('list', uid, p_item, p_qty, p_price_each, new_id);
  return jsonb_build_object('ok', true, 'id', new_id);
end $$;

create or replace function public.cancel_listing(p_listing bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me(); l public.listings;
begin
  select * into l from public.listings where id = p_listing for update;
  if not found or l.seller <> uid then raise exception 'not_found'; end if;
  if l.status <> 'active' then raise exception 'not_active'; end if;
  perform private.escrow_add(uid, l.item, l.qty);
  update public.listings set status = 'cancelled' where id = l.id;
  insert into public.trade_log (kind, actor, item, qty, ref) values ('cancel', uid, l.item, l.qty, l.id);
  return jsonb_build_object('ok', true);
end $$;

-- Buy a whole listing. The row lock makes concurrent buyers queue: the first one wins,
-- the rest see status <> 'active' and get 'already_sold' (no double sale).
create or replace function public.buy_listing(p_listing bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := private.me();
  l public.listings;
  total bigint;
  fee bigint;
begin
  perform private.rate_limit(uid, 'buy', 20);
  select * into l from public.listings where id = p_listing for update;
  if not found then raise exception 'not_found'; end if;
  if l.status <> 'active' then raise exception 'already_sold'; end if;
  if l.expires_at <= now() then raise exception 'expired'; end if;
  if l.seller = uid then raise exception 'own_listing'; end if;
  total := l.qty::bigint * l.price_each;
  fee := ceil(total * 0.05);
  perform private.wallet_add(uid, -total);                       -- raises if not enough coins
  perform private.wallet_add(l.seller, total - fee);
  perform private.escrow_add(uid, l.item, l.qty);
  update public.listings set status = 'sold', buyer = uid, sold_at = now() where id = l.id;
  insert into public.price_history (item, day, volume, coins) values (l.item, current_date, l.qty, total)
    on conflict (item, day) do update set volume = public.price_history.volume + excluded.volume,
      coins = public.price_history.coins + excluded.coins;
  insert into public.trade_log (kind, actor, counterparty, item, qty, coins, ref)
    values ('buy', uid, l.seller, l.item, l.qty, total, l.id);
  return jsonb_build_object('ok', true, 'item', l.item, 'qty', l.qty, 'coins', total);
end $$;

-- Browse active listings (optionally for a set of items), cheapest first, excluding mine.
create or replace function public.browse_listings(p_items text[] default null, p_limit int default 50)
returns table (id bigint, seller_name text, item text, qty int, price_each int, expires_at timestamptz)
language sql security definer stable set search_path = '' as $$
  select l.id, p.display_name, l.item, l.qty, l.price_each, l.expires_at
  from public.listings l join public.profiles p on p.id = l.seller
  where l.status = 'active' and l.expires_at > now() and l.seller <> (select auth.uid())
    and (p_items is null or l.item = any (p_items)) and not p.is_banned
  order by l.price_each asc, l.created_at asc
  limit least(greatest(p_limit, 1), 100);
$$;

create or replace function public.price_history(p_item text, p_days int default 14)
returns table (day date, avg_price numeric, volume bigint)
language sql security definer stable set search_path = '' as $$
  select day, round(coins::numeric / nullif(volume, 0), 1), volume
  from public.price_history
  where item = p_item and day > current_date - least(greatest(p_days, 1), 90)
  order by day;
$$;

-- "Market news": items with the most trading in the last 24h and their price vs base.
create or replace function public.market_news(p_limit int default 5)
returns table (item text, volume bigint, avg_price numeric, base_price int)
language sql security definer stable set search_path = '' as $$
  select l.item, sum(l.qty)::bigint, round(avg(l.price_each), 1), r.base_price
  from public.listings l join public.item_rules r using (item)
  where l.status = 'sold' and l.sold_at > now() - interval '24 hours'
  group by l.item, r.base_price
  order by 2 desc
  limit least(greatest(p_limit, 1), 20);
$$;

-- ------------------------------------------------------------------ friends + help

create or replace function private.are_friends(a uuid, b uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.friendships where user_a = least(a, b) and user_b = greatest(a, b));
$$;

create or replace function public.add_friend(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me(); other uuid;
begin
  perform private.rate_limit(uid, 'add_friend', 10);
  select id into other from public.profiles where friend_code = upper(btrim(p_code));
  -- returned, not raised: a raise would roll back the rate-limit row and allow code guessing
  if other is null then return jsonb_build_object('error', 'unknown_code'); end if;
  if other = uid then raise exception 'own_code'; end if;
  if (select count(*) from public.friendships where uid in (user_a, user_b)) >= 100 then raise exception 'too_many_friends'; end if;
  insert into public.friendships (user_a, user_b) values (least(uid, other), greatest(uid, other)) on conflict do nothing;
  return jsonb_build_object('ok', true, 'friend', other);
end $$;

create or replace function public.remove_friend(p_friend uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me();
begin
  delete from public.friendships where user_a = least(uid, p_friend) and user_b = greatest(uid, p_friend);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.list_friends()
returns table (id uuid, display_name text, level int, friend_code text)
language sql security definer stable set search_path = '' as $$
  select p.id, p.display_name, p.level, p.friend_code
  from public.friendships f
  join public.profiles p on p.id = case when f.user_a = (select auth.uid()) then f.user_b else f.user_a end
  where (select auth.uid()) in (f.user_a, f.user_b)
  order by p.display_name;
$$;

-- Read-only farm snapshot for a visit (friends only).
create or replace function public.visit_farm(p_friend uuid)
returns jsonb language plpgsql security definer stable set search_path = '' as $$
declare uid uuid := private.me();
begin
  if not private.are_friends(uid, p_friend) then raise exception 'not_friends'; end if;
  return (select farm_snapshot || jsonb_build_object('display_name', display_name, 'level', level)
          from public.profiles where id = p_friend);
end $$;

-- Water one crop on a friend's farm: once per friend per day, 5 helps per day.
-- Reward (coins) goes to the helper's wallet; the owner's device reads friend_help to apply the boost.
create or replace function public.help_friend(p_friend uuid, p_plot int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me();
begin
  if not private.are_friends(uid, p_friend) then raise exception 'not_friends'; end if;
  if (select count(*) from public.friend_help where helper = uid and day = current_date) >= 5 then
    raise exception 'help_limit';
  end if;
  insert into public.friend_help (helper, owner, plot) values (uid, p_friend, p_plot)
    on conflict do nothing;
  if not found then raise exception 'already_helped'; end if;
  perform private.wallet_add(uid, 15);
  insert into public.trade_log (kind, actor, counterparty, coins, detail)
    values ('help', uid, p_friend, 15, jsonb_build_object('plot', p_plot));
  return jsonb_build_object('ok', true, 'coins', 15, 'xp', 3);
end $$;

-- The owner's device fetches unseen helps once and marks them seen.
create or replace function public.claim_helps()
returns table (helper_name text, plot int)
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me();
begin
  return query
    with h as (
      update public.friend_help fh set seen = true
      where fh.owner = uid and not fh.seen
      returning fh.helper, fh.plot
    )
    select p.display_name, h.plot from h join public.profiles p on p.id = h.helper;
end $$;

-- ------------------------------------------------------------------ trade offers

create or replace function public.send_offer(p_to uuid, p_give_items jsonb, p_give_coins bigint, p_want_items jsonb, p_want_coins bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me(); k text; v jsonb; new_id bigint;
begin
  perform private.rate_limit(uid, 'offer', 10);
  if not private.are_friends(uid, p_to) then raise exception 'not_friends'; end if;
  if p_give_items <> '{}' then perform private.check_items(p_give_items); end if;
  if p_want_items <> '{}' then perform private.check_items(p_want_items); end if;
  if p_give_coins < 0 or p_want_coins < 0 then raise exception 'bad_quantity'; end if;
  if p_give_items = '{}' and p_give_coins = 0 then raise exception 'empty_offer'; end if;
  if (select count(*) from public.trade_offers where from_user = uid and status = 'pending') >= 10 then
    raise exception 'too_many_offers';
  end if;
  -- what I give is held now, so the offer can't bounce later
  for k, v in select * from jsonb_each(p_give_items) loop
    perform private.escrow_add(uid, k, -((v #>> '{}')::bigint));
  end loop;
  perform private.wallet_add(uid, -p_give_coins);
  insert into public.trade_offers (from_user, to_user, give_items, give_coins, want_items, want_coins)
    values (uid, p_to, p_give_items, p_give_coins, p_want_items, p_want_coins) returning id into new_id;
  insert into public.trade_log (kind, actor, counterparty, coins, ref, detail)
    values ('offer', uid, p_to, p_give_coins, new_id, jsonb_build_object('give', p_give_items, 'want', p_want_items, 'want_coins', p_want_coins));
  return jsonb_build_object('ok', true, 'id', new_id);
end $$;

create or replace function private.refund_offer(o public.trade_offers)
returns void language plpgsql set search_path = '' as $$
declare k text; v jsonb;
begin
  for k, v in select * from jsonb_each(o.give_items) loop
    perform private.escrow_add(o.from_user, k, (v #>> '{}')::bigint);
  end loop;
  perform private.wallet_add(o.from_user, o.give_coins);
end $$;

create or replace function public.respond_offer(p_offer bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me(); o public.trade_offers; k text; v jsonb;
begin
  perform private.rate_limit(uid, 'respond', 20);
  select * into o from public.trade_offers where id = p_offer for update;
  if not found or o.to_user <> uid then raise exception 'not_found'; end if;
  if o.status <> 'pending' then raise exception 'not_pending'; end if;
  if not p_accept then
    perform private.refund_offer(o);
    update public.trade_offers set status = 'declined', resolved_at = now() where id = o.id;
    insert into public.trade_log (kind, actor, counterparty, ref) values ('decline', uid, o.from_user, o.id);
    return jsonb_build_object('ok', true, 'status', 'declined');
  end if;
  -- accepter pays what is wanted (raises if they don't have it), then both sides receive
  for k, v in select * from jsonb_each(o.want_items) loop
    perform private.escrow_add(uid, k, -((v #>> '{}')::bigint));
    perform private.escrow_add(o.from_user, k, (v #>> '{}')::bigint);
  end loop;
  perform private.wallet_add(uid, -o.want_coins);
  perform private.wallet_add(o.from_user, o.want_coins);
  for k, v in select * from jsonb_each(o.give_items) loop
    perform private.escrow_add(uid, k, (v #>> '{}')::bigint);
  end loop;
  perform private.wallet_add(uid, o.give_coins);
  update public.trade_offers set status = 'accepted', resolved_at = now() where id = o.id;
  insert into public.trade_log (kind, actor, counterparty, coins, ref) values ('accept', uid, o.from_user, o.want_coins, o.id);
  return jsonb_build_object('ok', true, 'status', 'accepted');
end $$;

create or replace function public.cancel_offer(p_offer bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me(); o public.trade_offers;
begin
  select * into o from public.trade_offers where id = p_offer for update;
  if not found or o.from_user <> uid then raise exception 'not_found'; end if;
  if o.status <> 'pending' then raise exception 'not_pending'; end if;
  perform private.refund_offer(o);
  update public.trade_offers set status = 'cancelled', resolved_at = now() where id = o.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.report_player(p_player uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me();
begin
  perform private.rate_limit(uid, 'report', 5, '1 hour');
  if p_player = uid then raise exception 'own_report'; end if;
  insert into public.reports (reporter, reported, reason) values (uid, p_player, left(btrim(p_reason), 300));
  return jsonb_build_object('ok', true);
end $$;

-- My trading state in one call: wallet, escrow, my listings, offers to/from me.
create or replace function public.my_trading()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.me();
begin
  perform private.expire_listings();
  return jsonb_build_object(
    'wallet', coalesce((select coins from public.wallets where user_id = uid), 0),
    'escrow', coalesce((select jsonb_object_agg(item, qty) from public.escrow where user_id = uid and qty > 0), '{}'),
    'listings', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.listings l
                          where seller = uid and (status = 'active' or created_at > now() - interval '3 days')), '[]'),
    'offers_in', coalesce((select jsonb_agg(to_jsonb(o) || jsonb_build_object('from_name', p.display_name)) from public.trade_offers o
                           join public.profiles p on p.id = o.from_user where to_user = uid and status = 'pending'), '[]'),
    'offers_out', coalesce((select jsonb_agg(to_jsonb(o)) from public.trade_offers o where from_user = uid and status = 'pending'), '[]'));
end $$;

-- ------------------------------------------------------------------ privileges
revoke all on all functions in schema private from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'deposit(uuid,jsonb,bigint)', 'collect(uuid)', 'create_listing(text,integer,integer)', 'cancel_listing(bigint)',
    'buy_listing(bigint)', 'browse_listings(text[],integer)', 'price_history(text,integer)', 'market_news(integer)',
    'add_friend(text)', 'remove_friend(uuid)', 'list_friends()', 'visit_farm(uuid)', 'help_friend(uuid,integer)',
    'claim_helps()', 'send_offer(uuid,jsonb,bigint,jsonb,bigint)', 'respond_offer(bigint,boolean)', 'cancel_offer(bigint)',
    'report_player(uuid,text)', 'my_trading()']
  loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
