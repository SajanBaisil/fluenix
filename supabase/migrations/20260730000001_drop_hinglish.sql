-- Hinglish detection removed by founder call — the analysis no longer
-- produces it and the report screen no longer shows it.
alter table public.reports drop column if exists hinglish;
