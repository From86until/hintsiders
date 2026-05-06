-- Migration 004 — add pronoun column to profiles
-- Used to render "X has Y in mind. See if you can figure out what's in his/her/their head."
-- Existing users get 'their' as the default until they update their profile.

alter table profiles
  add column if not exists pronoun text not null default 'their';

-- Constrain to the three valid values
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_pronoun_check'
  ) then
    alter table profiles add constraint profiles_pronoun_check
      check (pronoun in ('his', 'her', 'their'));
  end if;
end $$;
