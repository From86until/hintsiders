-- ============================================================
-- INSIDE — database schema
-- Run this in Supabase SQL Editor (Database -> SQL Editor -> New Query)
-- ============================================================

-- ---------- TABLES ----------

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz default now()
);

create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text unique not null default substring(md5(random()::text), 1, 8),
  created_by uuid references profiles(id),
  hint_drop_hour int not null default 9,            -- 0-23, local hour hints unlock
  timezone text not null default 'America/New_York',
  created_at timestamptz default now()
);

create table if not exists group_members (
  group_id uuid references groups(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, profile_id)
);

create table if not exists setter_queue (
  group_id uuid references groups(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  position int not null,
  primary key (group_id, profile_id)
);

create table if not exists rounds (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups(id) on delete cascade,
  setter_id uuid references profiles(id),
  round_number int not null,
  category text not null,                            -- 'person' | 'place' | 'song' | 'movie' | 'moment'
  answer text not null,
  status text not null default 'drafting',           -- 'drafting' | 'active' | 'solved' | 'unsolved'
  current_hint_index int not null default 0,         -- 0 means none unlocked yet, 1-5 means N unlocked
  next_unlock_at timestamptz,
  solved_by uuid references profiles(id),
  solved_at timestamptz,
  solved_on_hint int,
  created_at timestamptz default now(),
  submitted_at timestamptz
);

create table if not exists hints (
  id uuid primary key default gen_random_uuid(),
  round_id uuid references rounds(id) on delete cascade,
  position int not null,                             -- 1..5
  text text not null,
  annotation text,
  unlocked_at timestamptz,
  unique(round_id, position)
);

create table if not exists guesses (
  id uuid primary key default gen_random_uuid(),
  round_id uuid references rounds(id) on delete cascade,
  guesser_id uuid references profiles(id),
  hint_index_at_guess int not null,                  -- which hint was the latest when they guessed
  text text not null,
  is_correct boolean not null default false,
  overridden boolean not null default false,         -- setter manually marked correct
  created_at timestamptz default now()
);

-- ---------- INDEXES ----------

create index if not exists rounds_group_status_idx on rounds(group_id, status);
create index if not exists rounds_next_unlock_idx on rounds(next_unlock_at) where status = 'active';
create index if not exists guesses_round_idx on guesses(round_id, created_at);

-- ---------- ROW LEVEL SECURITY ----------

alter table profiles enable row level security;
alter table groups enable row level security;
alter table group_members enable row level security;
alter table setter_queue enable row level security;
alter table rounds enable row level security;
alter table hints enable row level security;
alter table guesses enable row level security;

-- profiles: anyone authenticated can read; users can update their own
create policy "profiles_read" on profiles for select using (auth.role() = 'authenticated');
create policy "profiles_insert_self" on profiles for insert with check (auth.uid() = id);
create policy "profiles_update_self" on profiles for update using (auth.uid() = id);

-- groups: members can read; anyone authenticated can create
create policy "groups_read_member" on groups for select using (
  exists (select 1 from group_members where group_id = groups.id and profile_id = auth.uid())
);
create policy "groups_create" on groups for insert with check (auth.uid() = created_by);
create policy "groups_update_member" on groups for update using (
  exists (select 1 from group_members where group_id = groups.id and profile_id = auth.uid())
);

-- group_members: members can read; users add themselves
create policy "members_read" on group_members for select using (
  exists (select 1 from group_members gm where gm.group_id = group_members.group_id and gm.profile_id = auth.uid())
);
create policy "members_insert_self" on group_members for insert with check (auth.uid() = profile_id);

-- setter_queue: members read/write within their groups
create policy "queue_read" on setter_queue for select using (
  exists (select 1 from group_members where group_id = setter_queue.group_id and profile_id = auth.uid())
);
create policy "queue_write" on setter_queue for all using (
  exists (select 1 from group_members where group_id = setter_queue.group_id and profile_id = auth.uid())
);

-- rounds: members read; setter writes
create policy "rounds_read_member" on rounds for select using (
  exists (select 1 from group_members where group_id = rounds.group_id and profile_id = auth.uid())
);
create policy "rounds_insert_setter" on rounds for insert with check (auth.uid() = setter_id);
create policy "rounds_update_setter_or_system" on rounds for update using (
  auth.uid() = setter_id or
  exists (select 1 from group_members where group_id = rounds.group_id and profile_id = auth.uid())
);

-- hints: members can read ONLY unlocked hints; setter can read all of their own and write
create policy "hints_read_unlocked_or_own" on hints for select using (
  exists (
    select 1 from rounds r
    join group_members gm on gm.group_id = r.group_id
    where r.id = hints.round_id
      and gm.profile_id = auth.uid()
      and (
        hints.position <= r.current_hint_index    -- unlocked
        or r.setter_id = auth.uid()               -- setter sees all
      )
  )
);
create policy "hints_write_setter" on hints for all using (
  exists (select 1 from rounds where id = hints.round_id and setter_id = auth.uid())
);

-- guesses: members can read all guesses on rounds in their groups; users insert their own
create policy "guesses_read_member" on guesses for select using (
  exists (
    select 1 from rounds r
    join group_members gm on gm.group_id = r.group_id
    where r.id = guesses.round_id and gm.profile_id = auth.uid()
  )
);
create policy "guesses_insert_self" on guesses for insert with check (auth.uid() = guesser_id);
create policy "guesses_update_setter_override" on guesses for update using (
  exists (select 1 from rounds where id = guesses.round_id and setter_id = auth.uid())
);

-- ---------- HELPER FUNCTIONS ----------

-- Compute the next unlock time given a timezone and drop hour
create or replace function compute_next_unlock(tz text, drop_hour int)
returns timestamptz
language plpgsql
as $$
declare
  next_drop timestamptz;
begin
  next_drop := (date_trunc('day', (now() at time zone tz)) + (drop_hour || ' hours')::interval) at time zone tz;
  if next_drop <= now() then
    next_drop := next_drop + interval '1 day';
  end if;
  return next_drop;
end;
$$;

-- Submit a round (transition from drafting to active, unlock hint 1)
create or replace function submit_round(p_round_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  r record;
begin
  select rounds.*, g.timezone, g.hint_drop_hour
  into r
  from rounds
  join groups g on g.id = rounds.group_id
  where rounds.id = p_round_id;

  if r.setter_id != auth.uid() then
    raise exception 'only the setter can submit this round';
  end if;

  update rounds
  set status = 'active',
      submitted_at = now(),
      current_hint_index = 1,
      next_unlock_at = compute_next_unlock(r.timezone, r.hint_drop_hour)
  where id = p_round_id;

  update hints set unlocked_at = now() where round_id = p_round_id and position = 1;
end;
$$;

-- Submit a guess
create or replace function submit_guess(p_round_id uuid, p_text text)
returns jsonb
language plpgsql
security definer
as $$
declare
  r record;
  correct_answer text;
  is_match boolean;
  already_guessed boolean;
begin
  select * into r from rounds where id = p_round_id;

  if r.status != 'active' then
    raise exception 'round is not active';
  end if;
  if r.setter_id = auth.uid() then
    raise exception 'setter cannot guess';
  end if;

  -- one guess per current hint window
  select exists(
    select 1 from guesses
    where round_id = p_round_id
      and guesser_id = auth.uid()
      and hint_index_at_guess = r.current_hint_index
  ) into already_guessed;

  if already_guessed then
    raise exception 'already guessed this hint window';
  end if;

  correct_answer := lower(trim(r.answer));
  is_match := lower(trim(p_text)) = correct_answer;

  insert into guesses (round_id, guesser_id, hint_index_at_guess, text, is_correct)
  values (p_round_id, auth.uid(), r.current_hint_index, p_text, is_match);

  if is_match then
    update rounds
    set status = 'solved',
        solved_by = auth.uid(),
        solved_at = now(),
        solved_on_hint = r.current_hint_index
    where id = p_round_id;
  end if;

  return jsonb_build_object('correct', is_match);
end;
$$;

-- Setter override (mark a wrong guess as correct)
create or replace function override_guess(p_guess_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  g record;
  r record;
begin
  select * into g from guesses where id = p_guess_id;
  select * into r from rounds where id = g.round_id;

  if r.setter_id != auth.uid() then
    raise exception 'only the setter can override';
  end if;
  if r.status != 'active' then
    raise exception 'round is not active';
  end if;

  update guesses set is_correct = true, overridden = true where id = p_guess_id;
  update rounds
  set status = 'solved',
      solved_by = g.guesser_id,
      solved_at = now(),
      solved_on_hint = g.hint_index_at_guess
  where id = r.id;
end;
$$;

-- The cron-driven hint unlocker. Called every minute by pg_cron.
create or replace function unlock_due_hints()
returns void
language plpgsql
security definer
as $$
declare
  r record;
begin
  for r in
    select rounds.*, g.timezone, g.hint_drop_hour
    from rounds
    join groups g on g.id = rounds.group_id
    where rounds.status = 'active'
      and rounds.next_unlock_at <= now()
  loop
    if r.current_hint_index >= 5 then
      -- last hint already shown, mark as unsolved
      update rounds set status = 'unsolved' where id = r.id;
    else
      update rounds
      set current_hint_index = r.current_hint_index + 1,
          next_unlock_at = compute_next_unlock(r.timezone, r.hint_drop_hour)
      where id = r.id;
      update hints set unlocked_at = now()
      where round_id = r.id and position = r.current_hint_index + 1;
    end if;
  end loop;
end;
$$;

-- ---------- SCHEDULE THE UNLOCK FUNCTION ----------
-- This requires pg_cron, which Supabase has built-in.
-- Run this AFTER enabling the pg_cron extension (Database -> Extensions -> pg_cron).

-- Uncomment after enabling pg_cron:
-- select cron.schedule('inside-unlock-hints', '* * * * *', $$select unlock_due_hints()$$);

-- ---------- REALTIME ----------
-- Enable realtime on the tables clients need to subscribe to.
-- Run AFTER tables exist (Supabase auto-creates publication 'supabase_realtime').
alter publication supabase_realtime add table rounds;
alter publication supabase_realtime add table hints;
alter publication supabase_realtime add table guesses;
