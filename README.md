# Fluenix

**A fitness tracker for spoken English.** Tap a button, get a phone call with an AI coach, and after every call receive a measurable report — grammar, vocabulary, fluency, filler words — plus a personalized plan to improve.

📋 Full product & engineering plan: [PLAN.md](PLAN.md)
🎨 UI direction (7-screen mockup board): [design/mockups.html](design/mockups.html)

## Repo layout

```
PLAN.md      product plan, unit economics, roadmap
design/      HTML mockups — open mockups.html in a browser
app/         Flutter app (iOS + Android)
backend/     FastAPI service — session tokens + analysis pipeline (week 2+)
```

## Current status: Week-1 spike

The spike answers the plan's riskiest question: **does Gemini Live over Indian 4G feel like a phone call?**

What's built:
- Flutter app with the Fluenix theme (tokens 1:1 with the mockups)
- `VoiceSession` abstraction (`app/lib/voice/voice_session.dart`) — provider-agnostic, so OpenAI Realtime can slot in later without touching UI
- `GeminiLiveSession` — WebSocket to Gemini Live, native audio speech-to-speech
- Mic capture at 16 kHz PCM16 (`record`) with echo cancellation; playback of the coach's 24 kHz stream (`flutter_soloud` buffer streams, 150 ms latency target)
- Call screen from mockup 02: breathing halo, waveform, live status, timer, mute, coral end-call
- Barge-in support: interrupting the coach flushes buffered audio instantly

### Run it (full stack, week-2+)

Secrets live in `app/env.json` and `backend/.env` (both gitignored). Three terminals... actually two:

```sh
# 1. Backend (leave running)
cd backend && uv run uvicorn app.main:app --port 8000

# 2. App — phone plugged in via USB
adb reverse tcp:8000 tcp:8000     # phone reaches the Mac backend over the cable
cd app && flutter run --dart-define-from-file=env.json
```

First run: **Create an account** (email/password), then tap **Start call**. The app now gets a single-use ephemeral token from the backend (the Gemini key never ships), minutes are metered (free = 5 min/day), and the transcript is stored for the upcoming report pipeline. If the backend is unreachable, the app falls back to the dev key in `env.json` with no metering.

> **Spike-only shortcut:** the API key is compiled into the binary via `--dart-define`. Production replaces this with ephemeral tokens minted by the backend `/session` endpoint (PLAN.md §2) — never ship a raw key.

### What to evaluate (the spike's exit criteria)

| Question | Pass looks like |
|---|---|
| Latency on Jio/Airtel 4G | Coach replies in ~1 s; conversation doesn't feel walkie-talkie |
| Indian accent handling | Coach almost never mishears; no "sorry, what?" loops |
| Barge-in | Interrupting the coach cuts her off within ~300 ms |
| Echo | On speaker at full volume, coach doesn't respond to herself |
| Voice quality | Sounds like a person, not a screen reader |

If any of these fail, the fallback is OpenAI `gpt-realtime-2.1-mini` behind the same `VoiceSession` interface — see the provider table in PLAN.md §2.

Config knobs are in `app/lib/config.dart` (model name, voice, Emma's persona prompt).

### Troubleshooting

- **"No API key"** on the call screen → you forgot `--dart-define`.
- **Coach interrupts herself / responds to her own voice** → use headphones, or lower speaker volume; device echo cancellation quality varies.
- **Silence after connecting** → check the model name in `config.dart` against the [Live API docs](https://ai.google.dev/gemini-api/docs/live-api) — preview model names rotate.

## Next milestones (from PLAN.md §8)

- **Week 2** — Supabase project + schema + auth, FastAPI skeleton
- **Weeks 3–5** — `/session` metering + token minting, personas & scenarios, call polish
- **Weeks 6–7** — transcript persistence, Claude analysis pipeline, report UI
