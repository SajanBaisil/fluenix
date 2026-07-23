-- Fluenix core schema (PLAN.md §5)
-- Everything is owned by auth.users; RLS on every table.
-- The FastAPI service uses the service-role key and bypasses RLS;
-- the Flutter app reads directly through RLS.

-- ─────────────────────────────────────────────────────────────
-- profiles
-- ─────────────────────────────────────────────────────────────
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null default '',
  level       text not null default 'intermediate'
              check (level in ('beginner', 'intermediate', 'advanced')),
  goal        text not null default 'daily'
              check (goal in ('interview', 'ielts', 'daily', 'business', 'abroad')),
  daily_target_min int not null default 15 check (daily_target_min between 5 and 60),
  accent_pref text not null default 'neutral',
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "own profile: read"   on public.profiles for select using (auth.uid() = id);
create policy "own profile: insert" on public.profiles for insert with check (auth.uid() = id);
create policy "own profile: update" on public.profiles for update using (auth.uid() = id);

-- Auto-create a profile row on signup.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- subscriptions (written only by the backend via store/Razorpay webhooks)
-- ─────────────────────────────────────────────────────────────
create table public.subscriptions (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  tier        text not null default 'free' check (tier in ('free', 'premium')),
  source      text check (source in ('play', 'appstore', 'razorpay')),
  status      text not null default 'active'
              check (status in ('active', 'grace', 'expired', 'canceled')),
  current_period_end timestamptz,
  store_ref   text,
  updated_at  timestamptz not null default now()
);

alter table public.subscriptions enable row level security;
create policy "own subscription: read" on public.subscriptions
  for select using (auth.uid() = user_id);
-- no insert/update policies: service-role only

-- ─────────────────────────────────────────────────────────────
-- minute_ledger: usage (negative) and top-ups/grants (positive).
-- Daily free/premium allowances are computed by the backend, not stored.
-- ─────────────────────────────────────────────────────────────
create table public.minute_ledger (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  delta_seconds int not null,
  reason      text not null check (reason in ('call', 'grant', 'topup', 'expiry')),
  call_id     uuid,
  created_at  timestamptz not null default now()
);

create index minute_ledger_user_day
  on public.minute_ledger (user_id, created_at desc);

alter table public.minute_ledger enable row level security;
create policy "own ledger: read" on public.minute_ledger
  for select using (auth.uid() = user_id);
-- writes: service-role only

-- ─────────────────────────────────────────────────────────────
-- calls + transcripts + reports
-- ─────────────────────────────────────────────────────────────
create table public.calls (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  scenario    text not null default 'casual',
  persona     text not null default 'emma',
  provider    text not null default 'gemini_live',
  started_at  timestamptz not null default now(),
  ended_at    timestamptz,
  duration_s  int not null default 0,
  audio_ref   text,
  status      text not null default 'active'
              check (status in ('active', 'ended', 'analyzed', 'failed'))
);

create index calls_user_recent on public.calls (user_id, started_at desc);

alter table public.calls enable row level security;
create policy "own calls: read" on public.calls
  for select using (auth.uid() = user_id);
-- writes: service-role only (created by /v1/session, closed by /v1/calls/:id/end)

create table public.transcripts (
  call_id   uuid primary key references public.calls (id) on delete cascade,
  -- [{role: 'user'|'assistant', text, t_start_ms, t_end_ms}]
  turns     jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.transcripts enable row level security;
create policy "own transcripts: read" on public.transcripts
  for select using (
    auth.uid() = (select user_id from public.calls where id = call_id)
  );

create table public.reports (
  call_id     uuid primary key references public.calls (id) on delete cascade,
  model       text not null,
  overall     int not null check (overall between 0 and 100),
  scores      jsonb not null default '{}'::jsonb,
  grammar_issues    jsonb not null default '[]'::jsonb,
  vocab_suggestions jsonb not null default '[]'::jsonb,
  filler_words      jsonb not null default '{}'::jsonb,
  focus_points      jsonb not null default '[]'::jsonb,
  created_at  timestamptz not null default now()
);

alter table public.reports enable row level security;
create policy "own reports: read" on public.reports
  for select using (
    auth.uid() = (select user_id from public.calls where id = call_id)
  );

-- ─────────────────────────────────────────────────────────────
-- progress rollups, vocab bank, streaks
-- ─────────────────────────────────────────────────────────────
create table public.user_progress (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  date      date not null,
  minutes   int not null default 0,
  calls     int not null default 0,
  grammar   int,
  fluency   int,
  vocab     int,
  filler_rate real,
  primary key (user_id, date)
);

alter table public.user_progress enable row level security;
create policy "own progress: read" on public.user_progress
  for select using (auth.uid() = user_id);

create table public.vocab_bank (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  word        text not null,
  meaning     text not null default '',
  example     text not null default '',
  source_call uuid references public.calls (id) on delete set null,
  learned_at  timestamptz not null default now(),
  unique (user_id, word)
);

alter table public.vocab_bank enable row level security;
create policy "own vocab: read" on public.vocab_bank
  for select using (auth.uid() = user_id);

create table public.streaks (
  user_id   uuid primary key references public.profiles (id) on delete cascade,
  current   int not null default 0,
  longest   int not null default 0,
  last_active_date date
);

alter table public.streaks enable row level security;
create policy "own streak: read" on public.streaks
  for select using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- Helper: seconds of call usage today (backend computes allowance - this)
-- ─────────────────────────────────────────────────────────────
create function public.call_seconds_today(p_user uuid)
returns int
language sql
stable
security definer set search_path = ''
as $$
  select coalesce(-sum(delta_seconds), 0)::int
  from public.minute_ledger
  where user_id = p_user
    and reason = 'call'
    and created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata');
$$;
