-- Migration 003 — per-round drop interval + reveal all hints when solved
-- Safe to run on a live database. Existing in-flight rounds get drop_interval_hours = 24
-- (matching the old daily cadence), so nothing breaks for them.

-- ---------- 1. Add the per-round interval column ----------

alter table rounds
  add column if not exists drop_interval_hours int not null default 24;

-- ---------- 2. Update submit_round to use the round's interval, not a fixed group hour ----------

create or replace function submit_round(p_round_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  r record;
begin
  select * into r from rounds where rounds.id = p_round_id;

  if r.setter_id != auth.uid() then
    raise exception 'only the setter can submit this round';
  end if;

  update rounds
  set status = 'active',
      submitted_at = now(),
      current_hint_index = 1,
      -- next unlock = now + the round's chosen interval
      next_unlock_at = now() + (r.drop_interval_hours || ' hours')::interval
  where id = p_round_id;

  update hints set unlocked_at = now() where round_id = p_round_id and position = 1;
end;
$$;

-- ---------- 3. Update submit_guess: when solved, reveal ALL remaining hints ----------

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
        solved_on_hint = r.current_hint_index,
        current_hint_index = 5,        -- reveal all hints
        next_unlock_at = null
    where id = p_round_id;
    -- Mark every remaining hint as unlocked so it shows up on the reveal screen
    update hints set unlocked_at = now()
    where round_id = p_round_id and unlocked_at is null;
  end if;

  return jsonb_build_object('correct', is_match);
end;
$$;

-- ---------- 4. Same treatment for setter override ----------

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
      solved_on_hint = g.hint_index_at_guess,
      current_hint_index = 5,
      next_unlock_at = null
  where id = r.id;
  update hints set unlocked_at = now()
  where round_id = r.id and unlocked_at is null;
end;
$$;

-- ---------- 5. Update the cron unlock to use the round's per-round interval ----------

create or replace function unlock_due_hints()
returns void
language plpgsql
security definer
as $$
declare
  r record;
begin
  for r in
    select * from rounds
    where status = 'active' and next_unlock_at <= now()
  loop
    if r.current_hint_index >= 5 then
      update rounds set status = 'unsolved' where id = r.id;
    else
      update rounds
      set current_hint_index = r.current_hint_index + 1,
          next_unlock_at = now() + (r.drop_interval_hours || ' hours')::interval
      where id = r.id;
      update hints set unlocked_at = now()
      where round_id = r.id and position = r.current_hint_index + 1;
    end if;
  end loop;
end;
$$;
