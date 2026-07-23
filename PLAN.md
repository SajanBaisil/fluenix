# Fluenix — Complete Product & Engineering Plan

> **One-liner:** A fitness tracker for spoken English. Tap a button, get a phone call with an AI, and after every call receive a measurable coaching report — grammar, vocabulary, fluency, filler words — plus a personalized plan to improve.

**Locked decisions** (2026-07-23):

| Decision | Choice |
|---|---|
| Voice engine | Speech-to-speech API (single model hears & speaks) behind a provider-abstraction layer |
| Backend | Supabase (auth / Postgres / storage) + slim FastAPI service (voice tokens + analysis pipeline) |
| Market | India-first, ₹ pricing, Razorpay + store billing |
| Frontend | Flutter (iOS + Android) |
| Analysis model | Claude Opus 4.8 (`claude-opus-4-8`) with structured outputs |

---

## 1. Positioning

Many apps let you "talk to AI" (Speak, TalkPal, Loora, ChatGPT voice). Fluenix's wedge:

1. **It feels like a phone call**, not a chatbot — WhatsApp-call UX, human-like turn-taking, interruptions, laughter. Speech-to-speech models make this real; STT→LLM→TTS competitors feel walkie-talkie-ish.
2. **Every call ends in a report.** The call is the workout; the report is the product. Users leave knowing exactly what they did well, what to fix, and whether they're improving week over week.
3. **India-first**: IELTS/interview scenarios, Indian-accent-tolerant models, ₹ pricing, UPI.

Target users: students, job seekers, IELTS/PTE aspirants, engineers moving into client-facing roles, people relocating abroad, anyone afraid of speaking English.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter app (iOS / Android)                                 │
│  onboarding · home · call UI · report UI · progress · paywall│
└──────┬───────────────────────────────┬──────────────────────┘
       │ Supabase SDK                  │ WebRTC / WebSocket (direct)
       ▼                               ▼
┌──────────────────┐          ┌─────────────────────────┐
│ Supabase          │          │ Realtime voice provider │
│  Auth (phone/OTP, │          │  Gemini Live (default)  │
│   Google, Apple)  │          │  OpenAI Realtime (alt)  │
│  Postgres         │          └────────────▲────────────┘
│  Storage (audio,  │                       │ ephemeral session token
│   opt-in)         │          ┌────────────┴────────────┐
│  Edge cron        │◀────────▶│ Slim FastAPI service    │
└──────────────────┘  service  │  /session  → mint token │
                      role key │  /analyze  → post-call  │
                               │    pipeline (queued)    │
                               │  /webhooks → Razorpay,  │
                               │    RevenueCat           │
                               │  Claude Opus 4.8 calls  │
                               └─────────────────────────┘
```

Key principles:

- **Audio never proxies through our backend.** The FastAPI service only mints short-lived provider tokens with per-user minute budgets baked in; the Flutter client streams audio directly to the provider. This keeps our infra tiny and latency low.
- **Provider abstraction.** One `VoiceSession` interface in Flutter + one `SessionMinter` interface in the backend. Gemini Live and OpenAI Realtime are config-selectable per user/tier — we can arbitrage price/quality without an app release.
- **Analysis is async.** Call ends → transcript (provided by the realtime API) is written to Postgres → a queued job runs the Claude analysis → the app gets the report via Supabase Realtime subscription. The user watches a 5–10 s "Analyzing your call…" animation.

### Voice provider choice (within speech-to-speech)

| | Gemini Live (native audio) | OpenAI `gpt-realtime-2.1-mini` | OpenAI `gpt-realtime-2.1` |
|---|---|---|---|
| Audio pricing | $3/1M in, $12/1M out | $10/1M in, $20/1M out | $32/1M in, $64/1M out |
| Effective cost/min (mixed talk) | **~$0.01/min ≈ ₹0.9** | ~$0.02–0.05/min ≈ ₹2–4 | ~$0.06–0.11/min ≈ ₹5–10 |
| Notes | GA on Vertex; 70 languages; cheapest | Best price/quality balance | Most natural; premium voice tier later |

**Recommendation: launch on Gemini Live** for both tiers (it's ~⅓ the cost of OpenAI mini and handles Indian accents well), keep OpenAI mini wired up as fallback + A/B option. Revisit after real quality data.

---

## 3. MVP scope (what ships in v1)

### IN
- Phone/Google/Apple auth; onboarding: level (beginner/intermediate/advanced) + goal (daily English, interview, IELTS, travel, business) + daily target (10/20/30 min)
- **AI call**: one big 📞 button; call screen mirrors WhatsApp (connecting → timer, mute, speaker, end); AI persona greets by name, interrupts naturally, asks follow-ups
- **6 launch scenarios**: Casual friend · Job interview (HR) · IELTS speaking Part 1/2 · Coffee shop / ordering · Travel (airport/hotel) · Debate-lite ("convince me")
- **3 personas** (voice + personality): Emma (friendly), David (interviewer), Asha (Indian-accent teacher)
- **Post-call report** (Premium): overall score + grammar corrections with "why" + vocabulary upgrades + filler-word count + speaking-pace + fluency proxy (pauses/restarts from transcript timestamps) + 3 focus points for next call
- **Free-tier report teaser**: locked card — "We found 7 grammar issues and 12 filler words. Upgrade to see them."
- Call history, streaks, weekly progress chart, vocabulary bank (words the AI taught you)
- Metering + paywall + subscriptions (Play Billing / StoreKit + Razorpay on web)
- Analytics (PostHog), crash reporting (Sentry), remote config for provider/caps

### OUT (deliberately deferred)
- Group calls / multi-user (v3 — the killer feature, but it needs a userbase first)
- Phoneme-level pronunciation scoring with IPA (v2 — needs Azure Speech/Speechace on raw audio)
- Live in-call subtitles/corrections (v2)
- AI homework generation, leaderboards, friends (v2)
- Custom personas, teacher/enterprise dashboards (v3)

---

## 4. Core user flows

**Call flow:** Home → pick scenario (or "Surprise me") → `POST /session` (checks minute balance, mints ephemeral provider token with max-duration = remaining balance) → Flutter opens WebRTC/WS session with system prompt = persona + scenario + user level + last report's focus points → call runs, provider streams transcript deltas → user ends call (or budget hard-stops with a polite AI goodbye) → client posts transcript-final marker → backend enqueues analysis → report lands via Realtime subscription.

**The feedback loop (retention engine):** every report ends with 3 focus points → they're injected into the next call's system prompt ("gently create openings for past-tense; note when the user says 'basically'") → next report scores those same points → visible progress.

---

## 5. Data model (Postgres / Supabase)

```sql
profiles          (id → auth.users, name, level, goal, daily_target_min,
                   accent_pref, created_at)
subscriptions     (user_id, tier free|premium, source play|appstore|razorpay,
                   status, current_period_end, store_ref)
minute_ledger     (id, user_id, delta_seconds, reason call|grant|topup|expiry,
                   call_id, created_at)          -- balance = SUM(delta)
calls             (id, user_id, scenario, persona, provider, started_at,
                   ended_at, duration_s, audio_ref nullable,
                   status active|ended|analyzed|failed)
transcripts       (call_id PK, turns jsonb)      -- [{role, text, t_start_ms, t_end_ms}]
reports           (call_id PK, model, overall, scores jsonb,
                   grammar_issues jsonb, vocab_suggestions jsonb,
                   filler_words jsonb, focus_points jsonb, created_at)
user_progress     (user_id, date, minutes, calls, grammar, fluency,
                   vocab, filler_rate)           -- daily rollup for charts
vocab_bank        (id, user_id, word, meaning, example, source_call, learned_at)
streaks           (user_id, current, longest, last_active_date)
```

RLS on everything; the FastAPI service uses the service-role key.

---

## 6. Post-call analysis pipeline (Claude)

Runs in the FastAPI worker per completed call. Model: **`claude-opus-4-8`** with structured outputs — the report *is* the paid product, so quality is non-negotiable here. (A cheaper Haiku 4.5 pass for the free-tier teaser is possible; that's a cost decision to make with real data.)

```python
from pydantic import BaseModel
import anthropic

class GrammarIssue(BaseModel):
    said: str; corrected: str; rule: str; explanation: str

class Report(BaseModel):
    overall: int                      # 0–100
    grammar_score: int; vocab_score: int; fluency_score: int
    grammar_issues: list[GrammarIssue]
    vocab_suggestions: list[dict]     # {used, better, example}
    filler_words: dict[str, int]
    strengths: list[str]
    focus_points: list[str]           # exactly 3, fed into the next call

client = anthropic.Anthropic()

def analyze(transcript_turns, profile, prev_focus_points) -> Report:
    resp = client.messages.parse(
        model="claude-opus-4-8",
        max_tokens=16000,
        thinking={"type": "adaptive"},
        system=[{
            "type": "text",
            "text": COACH_SYSTEM_PROMPT,          # static — cached
            "cache_control": {"type": "ephemeral"},
        }],
        messages=[{"role": "user", "content": render(transcript_turns, profile,
                                                     prev_focus_points)}],
        output_format=Report,
    )
    return resp.parsed_output
```

Analysis-prompt essentials: only correct what the user said (never the AI's lines); calibrate severity to level (don't drown a beginner in 30 corrections — cap at the 5 most impactful); explanations in simple English; compare against `prev_focus_points` and say explicitly whether they improved.

Fluency signals computed in plain code from transcript timestamps (not the LLM): words/min, pause distribution, response latency, restarts, filler-word counts — passed into the prompt as pre-computed stats so scores stay consistent across calls.

**Cost per analysis:** ~4K in (mostly cached) + ~2.5K out ≈ **$0.07–0.09 ≈ ₹6–8 per call** — incurred only for Premium calls.

---

## 7. Monetization & honest unit economics

(₹87/USD; Gemini Live ≈ ₹0.9/min voice; analysis ≈ ₹7/premium call)

### Tiers

| | Free | Premium |
|---|---|---|
| Price | ₹0 | **₹499/mo** or **₹2,999/yr** (≈₹250/mo) · launch offer ₹299 first month |
| Calls | 1 call/day, 5 min cap | 30 min/day fair use |
| Report | Locked teaser | Full report + focus plan |
| Scenarios | 2 | All + IELTS + interview |
| History/progress | 7 days | Unlimited + weekly email |

### Cost per user per month

| Persona | Usage | Voice | Analysis | Total cost |
|---|---|---|---|---|
| Free, typical | ~40 min/mo | ₹36 | — | **~₹36** |
| Free, maxed | 150 min/mo | ₹135 | — | ₹135 (cap protects tail) |
| Premium, typical | ~200 min/mo, 20 calls | ₹180 | ₹140 | **~₹320** |
| Premium, heavy | 900 min/mo, 60 calls | ₹810 | ₹420 | ₹1,230 (fair-use cap + soft throttle) |

### Where the margin is — and isn't

- ₹499 − 18% GST = ₹423 net. Via Play/App Store at 15% (small-business tier): **₹359**. Typical premium cost ₹320 → **thin but positive**; yearly plans and web/Razorpay sales (~2% fees → ₹414 net) are meaningfully better. Push yearly + web checkout hard.
- **The heavy tail is the killer.** Mitigations: daily fair-use cap, top-up minute packs (₹99/100 min — sold at ~stable margin), and per-token caching hygiene (system prompts static → provider prompt-caching keeps voice near the low end of the range).
- Break-even sanity check: 10,000 MAU, 5% premium → 500 × ₹359 ≈ ₹1.8L/mo revenue vs costs ≈ 500×₹320 + 9,500×₹36 + infra ₹15K ≈ ₹5.2L… **negative at 5% conversion with generous free tier.** Two levers make it work: free tier at 1×5-min call/day *without* maxing (realistic avg ₹25–40) **and** conversion ≥ 8% (achievable — the report teaser converts at the moment of highest motivation), or a tighter free tier (3 calls/week). Model this weekly from real data; remote-config the caps so tuning needs no release.

---

## 8. Delivery roadmap

### Phase 1 — MVP (12 weeks)

| Weeks | Milestone |
|---|---|
| 1–2 | Foundation: Supabase project, schema + RLS, Flutter scaffold (Riverpod, go_router), auth + onboarding, CI (GitHub Actions → TestFlight/Play internal) |
| 3–5 | **Voice core**: FastAPI `/session` with metering, Gemini Live integration via `VoiceSession` abstraction, call UI (CallKit/ConnectionService polish), personas + scenario prompts, hard-stop on budget |
| 6–7 | **Analysis**: transcript persistence, worker queue, Claude pipeline + structured outputs, report UI, free-tier teaser card |
| 8 | Progress: streaks, charts, vocab bank, call history |
| 9 | **Money**: RevenueCat (Play + App Store), Razorpay web checkout, minute ledger, paywall screens |
| 10 | Polish: onboarding tune, empty states, offline handling, Hindi UI strings (UI only — coaching stays English) |
| 11 | Closed beta: 50–100 users (college WhatsApp groups, r/IELTS, LinkedIn), PostHog funnels, cost dashboards |
| 12 | Launch prep: store listings, privacy policy (DPDP Act — explicit consent for audio processing; transcripts stored, raw audio opt-in only), pricing experiments armed |

### Phase 2 (months 4–5)
Pronunciation scoring (Azure Speech Pronunciation Assessment on call audio, IPA + play-correct-audio, ~₹25/audio-hour, premium only) · AI homework from mistakes · live subtitle corrections (optional toggle) · IELTS band estimator · weekly email reports · referral program.

### Phase 3 (months 6–9)
**Group calls** (you + friends + AI moderator via LiveKit room with an agent participant; per-person reports) · interview coach with company-specific prep · business English track · leaderboards/community · B2B pilot (colleges & training institutes — one dashboard, bulk seats; likely the best revenue/₹ in India).

---

## 9. Budget

| Item | Cost |
|---|---|
| Apple Developer | ₹8,600/yr |
| Google Play | ₹2,200 one-time |
| Domain + mail | ₹1,500/yr |
| Supabase Pro | $25/mo ≈ ₹2,200/mo |
| FastAPI host (Railway/Fly) | ₹800–2,000/mo |
| RevenueCat / Sentry / PostHog | free tiers at MVP scale |
| AI (dev + beta, ~100 users) | ₹8,000–20,000/mo |
| **Launch total (3 months)** | **≈ ₹60,000–90,000** out of pocket |

Marketing after launch is the real spend — budget separately (content-led: IELTS YouTube/Shorts of real call+report demos is the obvious channel).

---

## 10. Top risks & mitigations

| Risk | Mitigation |
|---|---|
| Voice AI cost blows past subscription revenue | Meter server-side at token-mint time; remote-config caps; Gemini-first; top-up packs; watch cost/user weekly |
| Provider quality/price shifts | `VoiceSession` abstraction; both providers integrated by week 5 |
| Latency/quality on Indian networks | WebRTC (not WS) where possible; test on Jio/Airtel 4G early; degrade to shorter AI turns on packet loss |
| Free→paid conversion below 8% | Teaser report at the emotional peak; 7-day premium trial; yearly-first pricing page |
| Store billing cuts margin | Web/Razorpay checkout for renewals; India alternative-billing options |
| Speech recognition struggles with strong accents | Gemini Live accent robustness is good; keep OpenAI A/B; add "the AI misheard me" report feedback loop |
| Privacy (DPDP Act) | Consent screens; transcripts only by default; audio opt-in; delete-my-data flow at launch |

## 11. KPIs

Activation: signup → first completed call ≥ 60% · D7 retention ≥ 25% · calls/WAU ≥ 4 · teaser→paywall view ≥ 40% · free→premium ≥ 8% · AI cost per MAU ≤ ₹60 · premium gross margin ≥ 25%.

---

## 12. Immediate next steps

1. `flutter create` + Supabase project + repo/CI scaffold
2. Spike (week 1): Flutter ↔ Gemini Live round-trip on a real phone over 4G — validate latency + transcript quality with an Indian-accent speaker **before** building anything else
3. Write the 3 persona × 6 scenario prompt pack
4. Build `/session` metering + the call screen
5. Claude analysis pipeline + report UI
