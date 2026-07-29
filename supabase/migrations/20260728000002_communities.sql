-- Phase 1 community spaces: fixed category rooms, membership, realtime chat,
-- shared report cards, and report/block moderation (BUSINESS.md).

create table public.communities (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  emoji       text not null default '💬',
  description text not null default '',
  created_at  timestamptz not null default now()
);

alter table public.communities enable row level security;
create policy "communities: read" on public.communities
  for select to authenticated using (true);
-- writes: service-role only (rooms are curated, not user-created)

create table public.community_members (
  community_id uuid not null references public.communities (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (community_id, user_id)
);

alter table public.community_members enable row level security;
-- read-all so the app can show member counts and joined state
create policy "members: read" on public.community_members
  for select to authenticated using (true);
create policy "members: join" on public.community_members
  for insert to authenticated with check (auth.uid() = user_id);
create policy "members: leave" on public.community_members
  for delete to authenticated using (auth.uid() = user_id);

create table public.community_messages (
  id           uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  kind         text not null default 'text'
               check (kind in ('text', 'report_share')),
  body         text not null default ''
               check (char_length(body) between 1 and 1000),
  -- report_share: {overall, headline}
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

create index community_messages_recent
  on public.community_messages (community_id, created_at desc);

alter table public.community_messages enable row level security;
create policy "messages: read (members only)" on public.community_messages
  for select to authenticated using (
    exists (
      select 1 from public.community_members m
      where m.community_id = community_messages.community_id
        and m.user_id = auth.uid()
    )
  );
create policy "messages: post (members only)" on public.community_messages
  for insert to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.community_members m
      where m.community_id = community_messages.community_id
        and m.user_id = auth.uid()
    )
  );
create policy "messages: delete own" on public.community_messages
  for delete to authenticated using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- moderation: flag a message, block a user (client hides their messages)
-- ─────────────────────────────────────────────────────────────
create table public.community_flags (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.community_messages (id) on delete cascade,
  reporter   uuid not null references public.profiles (id) on delete cascade,
  reason     text not null default '',
  created_at timestamptz not null default now()
);

alter table public.community_flags enable row level security;
create policy "flags: file" on public.community_flags
  for insert to authenticated with check (auth.uid() = reporter);
-- reads: service-role only (moderation dashboard, later)

create table public.community_blocks (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  blocked    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, blocked)
);

alter table public.community_blocks enable row level security;
create policy "blocks: own" on public.community_blocks
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Chat needs display names; profiles are otherwise own-row-only. This view
-- deliberately exposes id + name (nothing else) to signed-in users.
create view public.member_names with (security_invoker = off) as
  select id, name from public.profiles;
grant select on public.member_names to authenticated;

-- Stream new messages to room subscribers (RLS still applies per subscriber).
alter publication supabase_realtime add table public.community_messages;

insert into public.communities (slug, name, emoji, description) values
  ('interview-prep', 'Interview Prep', '💼',
   'Mock answers, JDs, offer stories — get interview-ready together.'),
  ('ielts-exams', 'IELTS & Exams', '🎓',
   'Band scores, cue cards and speaking-partner talk for test day.'),
  ('daily-english', 'Daily English', '☕',
   'Casual everyday chat — the easiest place to start typing.'),
  ('debate-club', 'Debate Club', '🗣️',
   'Pick a side and defend it. Strong opinions, friendly fights.'),
  ('wins-reports', 'Wins & Reports', '🏆',
   'Share your call reports, streaks and breakthroughs.');
