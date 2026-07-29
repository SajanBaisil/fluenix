-- Sprint: deeper feedback loop.
-- metrics: deterministic talk-time/pace numbers computed from turn timestamps.
-- hinglish: Hindi-mixed phrases the analysis model spotted, with English versions.
alter table public.reports
  add column if not exists metrics  jsonb not null default '{}'::jsonb,
  add column if not exists hinglish jsonb not null default '{}'::jsonb;
