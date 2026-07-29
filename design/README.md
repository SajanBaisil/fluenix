# Handoff: Fluenix — AI calling app for spoken English

## Overview
Fluenix is a mobile app where learners practise spoken English on live voice calls with goal-specialised AI coaches (IELTS examiner, interview coach, daily-English partner, debate coach, pronunciation drills, kids tutor). This package covers 8 screens: Home, Coaches, Call setup, Active call, Call report, Practice, Community, Progress. Primary market: India.

## About the Design Files
The files in this bundle are **design references created in HTML** — an interactive prototype showing the intended look and behaviour. They are **not production code to copy**. The task is to **recreate these designs in your existing codebase** (React Native, Flutter, SwiftUI, Kotlin/Compose, etc.) using its established components, navigation, and theming. If no app environment exists yet, pick the framework that fits the product and implement the designs there.

`Fluenix App.dc.html` is a browser prototype: a left-hand screen index plus an iPhone frame (402 × 874 logical px) rendering one screen at a time. The frame chrome (bezel, status bar, home indicator) is scaffolding for the prototype only — the real app uses the platform's own status bar and safe areas.

## Fidelity
**High fidelity.** Colors, type, spacing, radii and copy are final-intent. Recreate pixel-close, but substitute your codebase's existing primitives (buttons, cards, list rows, tab bar) where they already match. Icons in the prototype are typographic placeholders (◆ ☏ ▲ ❍ ▮, ⌕, →) — replace with your real icon set.

## Design Tokens

### Color
| Token | Hex | Use |
|---|---|---|
| ink | #14110F | Primary text, dark surfaces, active tab |
| cream | #F6F1E8 | App background, text on dark |
| desk | #EFE9DE | Prototype page background only |
| white | #FFFFFF | Card surface |
| clay (primary) | #C9502B | Primary CTA, accent, streak, "now" markers |
| clay-hover | #DD5C33 | CTA hover/press |
| clay-tint | #FBEDE7 | Accent chip / soft accent card |
| clay-soft | #EFD3C6 | Low-value data cells (practice-only days) |
| teal | #0F5951 | Secondary accent, positive metrics, IELTS |
| teal-tint | #E4EEEC | Teal chip / soft card |
| mint | #7BC9A8 | CEFR badge, "your turn" dot |
| gold-text | #A9761A | Warning-ish metric text |
| gold | #E9A227 | Weekly-challenge mark, in-call FIX label |
| gold-tint | #FAF0D8 | Challenge card, daily-warmup chip |
| ink-hairline | rgba(20,17,15,.08) | Card border, dividers |
| ink-60 | rgba(20,17,15,.6) | Secondary text |
| ink-50 | rgba(20,17,15,.5) | Tertiary text |
| ink-35 | rgba(20,17,15,.35) | Inactive tab, placeholder |
| track | rgba(20,17,15,.07) | Progress-bar track |
| Call-screen glow | radial-gradient(circle, rgba(201,80,43,.34), transparent 66%) | Behind waveform |
| Dark-surface tints | rgba(246,241,232,.07 / .08 / .12 / .16) | Chips, borders on ink |

### Typography
- Display / numbers: **Newsreader** (Georgia fallback), weight 400. Sizes: 74px/.85 (report score), 44px (wordmark), 34px (stat), 30px (screen title), 26–28px (card headline), 20–24px (monogram).
- UI: **Schibsted Grotesk** (system-ui fallback). 15px/700 CTA, 13.5–15px/700 titles, 12.5–13px/500–600 body, 11–11.5px/500 meta.
- Labels / numeric: **IBM Plex Mono**. 9–12px, weight 500–600, letter-spacing .06–.16em, uppercase for eyebrow labels. Call timer 12px/600.
- Line-heights are baked into the `font:` shorthands in the source; body copy uses 1.4–1.5, titles 1.1–1.25.

### Spacing / shape
- Screen side padding 20px; top padding 60px (status bar); bottom scroll padding 24px.
- Vertical rhythm: 6–7px label→title, 11–14px into a group, 22–26px between sections.
- Radii: cards 18–26px, hero cards 26px, monogram tiles 11–16px (30px on the 96px setup avatar), chips 8–12px, pills/CTAs 999px, data cells 5–6px.
- Borders: 1px `ink-hairline` on white cards; 1px rgba(246,241,232,.16) on dark.
- No drop shadows anywhere except the prototype's device frame.
- Tab bar: 84px tall, 1px top border, translucent cream (rgba(246,241,232,.92) + blur 12px), 5 equal items, glyph 17px + 10px/600 label with 7px gap.

## Screens

### 01 Home
Purpose: resume practice in one tap.
Layout: scroll column.
1. Header row — left: mono eyebrow "Tuesday · Evening" + 30px display "Hello, Ananya"; right: streak pill (clay-tint bg, 1px rgba(201,80,43,.18), 6px clay dot + "12" mono 12/700) and 38px circular ink avatar with white initial. Streak pill is behind the `gamified` flag.
2. Next-up hero — ink card, radius 26, padding 22, blurred clay orb (170px, blur 30) at top-right, overflow hidden. Contents: mono eyebrow "NEXT UP", 26px display "IELTS Part 1 with Meera" (max-width 200), 12px meta "10 min · Hometown & studies · B2", then a row: clay pill CTA "Start call" (flex 1, padding 15/20, 15px/700) + 52px circular outline button "All" → Coaches.
3. "This week" section header with clay mono "DETAILS" link → Progress. White card: left column 34px display "64" + 13px "/ 90 min", 7px clay progress bar at 71%, 11px caption; 1px vertical divider; right 78px column with 30px teal "B2" + mono "CEFR LEVEL".
4. "Pick a goal" — 2×2 grid, 11px gap. Each: white card radius 20, 34px tinted rounded tile with 13px mono code (7+ / HR / 5m / 2), 14px/700 title, 11px caption. Targets: Coaches, Coaches, Practice, Community.
5. Last-report row — rgba(20,17,15,.045) card radius 18: 26px display "78", title "Yesterday's report is ready", caption "3 grammar fixes · pace a little slow", clay mono "OPEN" → Report.
Hover: goal cards border → rgba(20,17,15,.28); report row bg → rgba(20,17,15,.08).

### 02 Coaches
30px title "Coaches" + 13px subtitle. Search field: white, radius 14, padding 12/14, ⌕ glyph + placeholder `Search "salary negotiation"`. Filter chips: horizontal scroll row, 8px gap, radius 999, padding 9/14, 12px/600; selected = ink bg + cream text; unselected = transparent + 1px rgba(20,17,15,.14). Filters: All coaches, IELTS & exams, Interview, Daily English, Debate, Kids (filters the list by coach goal).
Coach card (white, radius 22, padding 16, 14px gap): 52px monogram tile (radius 16, coach tint bg, coach color, 24px display letter) + column: name 15/700 with mono "★ rating" right-aligned, role 12/600 in coach color, 11.5px bio, then two mono meta chips (accent, focus) on rgba(20,17,15,.05) radius 8. Tap → Call setup for that coach.

Coach data: Meera / IELTS Speaking Examiner / Band 6.5→8.0 / British RP / 4.9 / teal; Rohan / Interview Coach / HR + tech rounds / Neutral Indian / 4.8 / clay; Zoya / Daily English Partner / Small talk & confidence / Warm American / 4.9 / gold; Vikram / Debate & Fluency Coach / Argue under pressure / Crisp Indian / 4.7 / ink; Nisha / Pronunciation Drill Coach / Sounds & stress / Slow & clear / 4.9 / teal; Kabir / Kids & Teens Tutor / Ages 8–15 / Playful / 4.8 / clay. Bios are in the HTML source (COACHES array) — use verbatim.

### 03 Call setup (initiate call)
Back link "← COACHES" (11px mono, ink-50). Centered block: 96px monogram tile radius 30 (42px display letter), 28px display name, 12.5/600 role in coach color, 12.5px bio (max-width 270), all centre-aligned.
"TODAY'S TOPIC" mono eyebrow + wrapping chips (radius 12, padding 11/14): selected = clay-tint bg, clay text, 1px rgba(201,80,43,.35); else white + 1px rgba(20,17,15,.1). Topics: Hometown & studies, Work & career, Technology, Surprise me.
Two segmented controls side by side (flex 1 each, 11px gap): "LEVEL" (B1/B2/C1) and "LENGTH" (5m/10m/20m). Track rgba(20,17,15,.055), radius 12, 4px padding; selected segment = white, radius 9, ink text 12px mono/700; unselected text rgba(20,17,15,.45).
"Live captions" row: white card radius 18, title + 11.5px caption, and a 48×28 toggle (radius 999, 3px padding, 22px white knob; on = clay, off = rgba(20,17,15,.18)).
Primary CTA: full-width clay pill, padding 18, 16/700, "Call {coach} now" → Active call (resets timer). Below: centred 11px mono note "Uses {duration} of your 60 free minutes this month". No tab bar on this screen.

### 04 Active call (dark)
Full-bleed ink background, cream text, no tab bar. Centered 420px radial clay glow at y=180, blur 10.
Top bar: 40px monogram tile (radius 13) + name 14/700 + 11px context line ("IELTS mock · Part 1 of 3") + timer pill (rgba(246,241,232,.08), radius 999, padding 8/12) with 6px clay dot blinking (1.4s ease-in-out, opacity 1→.25) and mm:ss mono 12/600.
Centre: voice visual, two variants (`callVisual` prop):
- **waveform** (default): 18 bars, width 5, radius 9, heights 34–132px, colors #C9502B / #D9633A / #E8A06F / #F0C9A8, animation `wf` 1.1s ease-in-out infinite, staggered delay 0→1.36s in .08s steps; keyframes scaleY .18 → 1 → .18.
- **orb**: 190px stack — two concentric rings (1px rgba(201,80,43,.45–.5)) animating `orbp` 2.6s (scale 1→1.22, opacity .5→.12, second ring delayed .5s) around a 104px circle with linear-gradient(150deg,#E06B3F,#B03F1F).
Below the visual: status pill (rgba(246,241,232,.07), 1px rgba(246,241,232,.1), radius 999) with 6px mint dot + uppercase mono label — "{Coach} is speaking" or "Your turn — keep going".
Captions stack (toggleable, max-height 290, scrolls, 16px side padding, 10px gap): last 3 turns as bubbles, max-width 86%.
- Coach bubble: left-aligned, bg rgba(246,241,232,.08), border rgba(246,241,232,.12), radius 18/18/18/6, speaker label mono 9px rgba(246,241,232,.45).
- Learner bubble: right-aligned, bg rgba(201,80,43,.16), border rgba(201,80,43,.3), radius 18/18/6/18, label rgba(240,201,140,.85).
- Body text 13.5/500 cream. If the turn has a correction, append a block above the bubble's bottom edge: 1px dashed rgba(233,162,39,.4) top border, gold "FIX" mono 9px + 12/600 #F0D08C correction text.
- Entry animation `lineIn`: opacity 0→1, translateY 8px→0, .45s ease.
Controls row (padding 18/20/44): 56px circular MIC toggle (label flips MIC/OFF; on-mute bg cream, ink text), 56px circular CC toggle (active bg rgba(246,241,232,.16)), then flex-1 clay pill "End call" (56px tall, 15/700) → Call report.
Timing model in the prototype: 1s tick increments the timer; every 4s advances one conversation turn (6 scripted turns). Real app drives this from the voice session.

### 05 Call report
Eyebrow "CALL REPORT · 9 MIN 42 S" + "CLOSE ✕" (→ Home).
Score hero: ink card radius 26, padding 24, teal glow bottom-right (190px, blur 34). Left: 74px display "78" + mono "OVERALL / 100". Right column, right-aligned: mint badge "B2 · UPPER INT." (radius 999, ink-green text #0B2F27, 12px mono/700) and 11.5px "+3 vs your last IELTS mock call".
Breakdown card (white, radius 22, 15px gap): 4 rows — label 12.5/600, score mono in row color, 6px bar on track at score%, 11px note. Fluency & coherence 82 teal; Pronunciation 74 gold-text; Grammar range 71 clay; Vocabulary 80 teal (notes verbatim in source).
Stats grid: 3 white cards radius 18 — 9 FILLER WORDS (ink), 118 WORDS PER MIN (gold-text), 46% YOUR TALK TIME (teal); each 26px display + two-line 9.5px mono label. Caption below: fillers breakdown + target wpm.
"Three things to fix": 3 white cards radius 20 — clay mono kind label ("Tense · said 3×", "Preposition", "Filler habit"), struck-through wrong sentence 13/500 ink-45, corrected sentence 13.5/600 ink, then a hairline-topped 11.5px explanation.
"Practice this next": teal-tint card (40px teal tile "4m", title #0B3B35, teal →) → Practice; clay-tint card (clay tile "P2", title #5C2211, clay →) → Call setup.
Footer buttons: outline pill "Replay audio" + ink pill "Share to group" → Community.

### 06 Practice
Title + subtitle. Teal hero card radius 26 with mint glow: eyebrow "DAILY WARMUP · DAY 12", 25px display "Five minutes of shadowing", 12px description, cream pill "Start warmup" + mono "4 / 5 DONE THIS WEEK".
"Role-play scenarios": 4 white rows radius 20 — 42px tinted tile with 12px mono tag (JOB / AIR / RENT / CAFE), 13.5/700 title, 11.5px meta "8 min · Rohan · medium", trailing →. Tap → Call setup.
"Drills & decks": 2×2 grid of white cards radius 20 — Minimal pairs (62% clay bar, "18 / 30 PAIRS"), Flashcards (34% teal bar, "41 / 120 CARDS"), Listen & answer ("6 NEW CLIPS"), Fix your fillers (clay mono "FROM YOUR REPORT").

### 07 Community
Title + subtitle. "LIVE VOICE ROOMS" eyebrow with blinking clay dot. Horizontal scroll of 212px room cards:
- Ink card: overlapping 28px avatar circles (−8px margin-left, clay / teal / gold) + mono "+9"; title `"Should AI grade exams?"`; meta "Debate Club · moderated"; clay pill "Join room".
- White card: two tinted avatars + "+4"; "Part 2 cue-card swap"; "IELTS & Exams · 6 speaking"; outline pill "Listen in".
Weekly challenge: gold-tint card radius 22 — 44px gold tile "W29", title `Weekly challenge: talk for 2 min without "uh"`, meta "1,204 entries · ends Sunday", text #3D2A05.
"Your communities": 5 white rows radius 20 — 44px tinted tile with 20px display letter, name 13.5/700 with optional clay "LIVE" tag (8.5px mono on clay-tint, radius 6), 11.5px member meta, then latest-thread line in rgba(20,17,15,.72). Communities: IELTS & Exams 24.1k (live), Daily English 58.3k, Debate Club 7.8k (live), Interview Prep 12.4k, Kids' English 4.2k.
Leaderboard card: header "IELTS & Exams · this week" + mono "MINUTES SPOKEN"; 4 rows of rank mono, 30px avatar, name 12.5/600 (own row in clay), minutes mono. Footer above a hairline: peer-matchmaking copy + ink pill "Match me".

### 08 Progress
Title + subtitle "14 weeks in. Here's the shape of it."
CEFR journey card (white, radius 24): 5 stepped bars, radius 8/8/3/3 — A1 26px teal, A2 42px teal, B1 60px teal, B2 86px clay (flex 1.35, label "B2 · NOW" in clay), C1 104px rgba(20,17,15,.09); mono labels below; hairline-topped 12px explanation of the gate to C1.
Stat pair: ink card "12 DAY STREAK" and white card "9.4 HOURS SPOKEN" (34px display + 9.5px mono label).
Minutes-per-week card: header + teal mono "↑ 22%"; 8 bars, 96px band, current week clay, others rgba(201,80,43,.28), radius 6, mono week labels (W22–W29).
Skills card: 4 rows — label 12.5/600, delta mono (teal for ↑, clay for ↓), 6px bar at score%.
Last-28-days card: 14-column grid of square cells radius 5, gap 6 — clay = call, clay-soft = practice only, rgba(20,17,15,.08) = rest; legend row below.

## Interactions & Behavior
- Tab bar (Home / Coaches / Practice / Community / Progress) on Home, Coaches, Practice, Community, Progress. Call setup, Active call and Call report are full-screen (setup and report are pushed views; the call is modal).
- Flow: Home → Call setup (hero CTA or coach tap) → Active call ("Call X now") → Call report ("End call") → Home / Practice / Call setup / Community.
- Active-call tab highlight stays on Coaches.
- Toggles: captions (setup row and in-call CC button share one state), mic mute.
- Filters, topic chips, level and length segments are single-select and immediate.
- Animations: `wf` waveform 1.1s staggered; `orbp` 2.6s ring pulse; `blink` 1.4s live dots; `lineIn` .45s caption entry. Hover states only matter on web; use press states (opacity/scale) on mobile.
- Hit targets: keep everything ≥44px — CTAs are 52–56px, tab items 84px tall.

## State Management
`screen` (home | coaches | setup | call | report | practice | community | progress), `coach` index, `filter` id, `topic` index, `level` (B1/B2/C1), `dur` (5/10/20), `muted`, `captions`, `sec` (elapsed call seconds), `turn` (visible transcript turns).
Real implementation: replace the 1s interval + scripted turn list with the voice session (STT/LLM/TTS) stream; `turn` becomes appended transcript events, each optionally carrying a correction. The report is generated server-side from the finished session; screens 05 and 08 read from that API.
Prototype-only variants exposed as props: `callVisual` (waveform | orb), `showCaptions`, `gamified` (hides the streak pill).

## Assets
None bundled. All avatars are letter monograms on tinted tiles — swap for real coach portraits/illustrations. All icons are typographic placeholders; replace with your icon library (home, phone, target, community, chart; search; chevron/arrow; mic; CC). Fonts: Newsreader, Schibsted Grotesk, IBM Plex Mono (all Google Fonts, OFL) — bundle them in the app or map to the nearest faces you already ship.

## Files
- `Fluenix App.dc.html` — the interactive prototype (all 8 screens, screen index on the left). Open in a browser.
- `ios-frame.jsx` — device-frame scaffolding used by the prototype (bezel, status bar, home indicator). Not part of the product design.
