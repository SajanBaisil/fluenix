-- Tracks whether the user completed first-run onboarding (level/goal/name).
alter table public.profiles
  add column if not exists onboarded boolean not null default false;
