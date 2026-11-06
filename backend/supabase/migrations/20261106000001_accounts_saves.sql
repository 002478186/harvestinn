-- HarvestInn: player profiles, moderation and cloud saves.
-- Clients may READ through RLS but every WRITE goes through a SECURITY DEFINER
-- function below that checks (select auth.uid()) itself.

create schema if not exists private;

-- ------------------------------------------------------------------ moderation
create table private.blocked_words (word text primary key);
insert into private.blocked_words (word) values
  ('fuck'),('shit'),('bitch'),('cunt'),('nigger'),('nigga'),('faggot'),('fag'),('retard'),('whore'),
  ('slut'),('dick'),('cock'),('pussy'),('penis'),('vagina'),('rape'),('nazi'),('hitler'),('kys'),
  ('killyourself'),('asshole'),('bastard'),('twat'),('wank'),('spic'),('chink'),('kike'),('tranny'),('dyke');

-- Same normalisation as scripts/core/name_filter.gd: lowercase, l33t -> letters, keep a-z only.
create or replace function private.name_is_clean(p_name text)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1 from private.blocked_words w
    where position(w.word in regexp_replace(
      translate(lower(p_name), '013457@$!', 'oieastasi'), '[^a-z]', '', 'g')) > 0
  );
$$;

-- ------------------------------------------------------------------ profiles
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Farmer' check (char_length(display_name) between 2 and 16),
  friend_code text not null unique check (friend_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  level int not null default 1 check (level between 1 and 50),
  farm_snapshot jsonb not null default '{}'::jsonb,   -- read-only view for friends' visits
  is_banned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
-- Names and levels are public in-game; friend codes and farm snapshots are only
-- reachable through RPCs (my_profile, visit_farm for friends).
create policy profiles_read on public.profiles for select to authenticated using (true);
revoke select on public.profiles from anon, authenticated;
grant select (id, display_name, level) on public.profiles to authenticated;

create or replace function private.new_friend_code()
returns text language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no I/O/0/1
  code text;
begin
  loop
    code := '';
    for i in 1..8 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where friend_code = code);
  end loop;
  return code;
end $$;

-- Every new auth user (including anonymous guests) gets a profile.
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, friend_code) values (new.id, private.new_friend_code());
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

create or replace function public.set_display_name(p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  n text := btrim(p_name);
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if char_length(n) not between 2 and 16 then return jsonb_build_object('error', 'name_short'); end if;
  if not private.name_is_clean(n) then return jsonb_build_object('error', 'name_blocked'); end if;
  update public.profiles set display_name = n, updated_at = now() where id = uid;
  return jsonb_build_object('ok', true, 'name', n);
end $$;

-- ------------------------------------------------------------------ cloud saves
create table public.cloud_saves (
  user_id uuid primary key references auth.users (id) on delete cascade,
  revision bigint not null default 0,
  save_version int not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  check (octet_length(data::text) < 1000000)
);
alter table public.cloud_saves enable row level security;
create policy cloud_saves_own on public.cloud_saves for select to authenticated
  using ((select auth.uid()) = user_id);

-- Optimistic concurrency: the write succeeds only if the client saw the latest revision.
-- On conflict the server copy is returned so the client can ask the player which to keep.
create or replace function public.save_game(p_data jsonb, p_base_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  cur public.cloud_saves;
  lvl int := least(greatest(coalesce((p_data ->> 'level')::int, 1), 1), 50);
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into cur from public.cloud_saves where user_id = uid for update;
  if not found then
    insert into public.cloud_saves (user_id, revision, save_version, data)
      values (uid, 1, coalesce((p_data ->> 'version')::int, 1), p_data);
  elsif cur.revision <> p_base_revision then
    return jsonb_build_object('conflict', true, 'revision', cur.revision, 'data', cur.data, 'updated_at', cur.updated_at);
  else
    update public.cloud_saves set revision = revision + 1, data = p_data,
      save_version = coalesce((p_data ->> 'version')::int, save_version), updated_at = now()
      where user_id = uid;
  end if;
  -- Friends see a small read-only snapshot (plots, buildings, avatar), never the inventory.
  update public.profiles set level = lvl, updated_at = now(),
    farm_snapshot = jsonb_build_object('plots', p_data -> 'plots', 'cols', p_data -> 'cols', 'rows', p_data -> 'rows',
      'buildings', p_data -> 'buildings', 'decor', p_data -> 'decor', 'pos', p_data -> 'pos', 'avatar', p_data -> 'avatar',
      'name', p_data -> 'name')
    where id = uid;
  return jsonb_build_object('ok', true, 'revision', (select revision from public.cloud_saves where user_id = uid));
end $$;

create or replace function public.my_profile()
returns jsonb language sql security definer stable set search_path = '' as $$
  select jsonb_build_object('id', id, 'display_name', display_name, 'friend_code', friend_code, 'level', level)
  from public.profiles where id = (select auth.uid());
$$;

create or replace function public.load_game()
returns jsonb language sql security definer stable set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('revision', revision, 'data', data, 'updated_at', updated_at)
       from public.cloud_saves where user_id = (select auth.uid())),
    jsonb_build_object('revision', 0));
$$;

-- Lock down: only the functions above are callable, and only by signed-in users.
revoke all on all functions in schema private from public, anon, authenticated;
revoke execute on function public.set_display_name(text), public.save_game(jsonb, bigint), public.load_game(), public.my_profile() from public, anon;
grant execute on function public.set_display_name(text), public.save_game(jsonb, bigint), public.load_game(), public.my_profile() to authenticated;
revoke insert, update, delete on public.profiles, public.cloud_saves from anon, authenticated;
