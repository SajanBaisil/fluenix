-- Coach memory: 2-4 sentences per call capturing personal facts and topics,
-- fed into the next call's prompt for conversational continuity.
alter table public.reports
  add column if not exists memory text not null default '';
