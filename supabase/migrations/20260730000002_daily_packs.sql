-- "Today's 5" daily practice (BUSINESS.md §5, Sprint 1).
-- One generated pack per user per day; completion synced here so the
-- streak survives reinstalls and device switches. Dates are IST days.
create table public.daily_packs (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  date         date not null,
  items        jsonb not null default '[]'::jsonb,
  -- indexes into items the user has finished, e.g. [0,2,3]
  done         jsonb not null default '[]'::jsonb,
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  primary key (user_id, date)
);

alter table public.daily_packs enable row level security;
create policy "own packs: read" on public.daily_packs
  for select using (auth.uid() = user_id);
-- writes: service-role only (created/updated by /v1/practice/daily)
