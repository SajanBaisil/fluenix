# Fluenix — Competitive Position & B2B Plan

*Last updated: 23 Jul 2026*

## 1. The market as it stands

### B2C conversation-AI apps

| App | What they do well | Weakness we exploit | Price |
|---|---|---|---|
| **Speak** | Polished speech recognition, lesson tracks | Lesson-shaped, not call-shaped; feedback per exercise, not per conversation | ~$165/yr |
| **Loora** | Guided daily tutor sessions, inline corrections | Corrections in the moment, weak longitudinal evidence of improvement | ~$10–20/mo |
| **Praktika** | Avatar roleplay immersion | Feels like a game character, not a phone call; no coaching arc across sessions | ~$15/mo |
| **TalkPal** | 57+ languages, cheap | Breadth over depth; generic feedback | ~$6–12/mo |
| **ELSA** | Phoneme-level pronunciation, strong for Indian MTI patterns | Pronunciation only — not conversation, not fluency coaching | ~$12/mo |
| **EngVarta** (India) | Real human experts on live calls | Doesn't scale, ~₹150/session, no analytics | ~$1.80/session |
| **Stimuler** (India) | IELTS-focused voice feedback | Exam niche, not real-world conversation | freemium |

Sources: [Kippy comparison](https://kippy.ai/blog/best-ai-language-learning-apps-comparison), [Talkio 2026 roundup](https://www.talkio.ai/blog/best-ai-language-speaking-practice-apps-in-2026), [EngVarta alternatives](https://engvarta.com/best-speak-app-alternatives-for-english-fluency/), [Lingtuitive tests](https://lingtuitive.com/blog/best-ai-speaking-apps), [PracticeMe comparison](https://practiceme.app/blog/best-ai-english-tutor-apps)

### B2B corporate language training

| Provider | Model | Weakness we exploit |
|---|---|---|
| **goFluent** | AI self-study + 1,500 human coaches; BPO candidate assessment "in 1 hour" | Heavy, expensive, assessment separate from practice |
| **Speexx** | CEFR-aligned training + assessment, SCORM/SSO, 1,800 brands | LMS-era product; sessions ≠ real conversations |
| **Voxy** | Real-world content (Bloomberg, AP) for professional vocab | Content-first, speaking-second |

Sources: [goFluent BPO](https://www.gofluent.com/us-en/industries/bpo-language-training-assessment/), [Speexx corporate](https://www.speexx.com/solutions/corporate-language-training/), [Voxy](https://voxy.com/), [enterprise platform roundup](https://www.speexx.com/speexx-blog/10-best-corporate-language-training-platforms-for-enterprise/), [Talaera comparisons](https://www.talaera.com/business-english-platforms/gofluent-alternatives/)

## 2. The differentiator (one sentence)

**Every real conversation is simultaneously practice, assessment, and curriculum: the call produces a measurable report, the report produces targeted practice, and the next call knows both — nobody in the table above closes that loop.**

Concretely, Fluenix is the only product where:
1. Practice feels like a **phone call** (earpiece-first, barge-in, a coach who *remembers your life* across calls)
2. Every call yields **assessment-grade evidence** (scores, verbatim mistakes with corrections, filler counts, trend lines)
3. The mistakes become **drills** (Practice section), and the drills become the **next call's focus** (prompt injection)
4. It's **India-first**: Indian-English error patterns in the analysis prompt, interview/placement scenarios, IST day-caps, UPI-friendly pricing

Items 1–3 are the moat: the longitudinal per-learner speaking dataset gets more valuable with every call, and it's precisely what enterprises pay for (evidence, not vibes).

## 3. B2B plan (India-first)

### Target segments, in order of attack

**Segment A — College placement cells (T&P officers).** Every engineering/MBA college runs interview prep; it's manual, unmeasured mock interviews. Offer: each student gets unlimited AI mock interviews (David) + weekly progress reports; the placement officer gets a **cohort dashboard** — average readiness score, most-common error patterns, an at-risk list, exportable per-student reports for recruiters. Buying season: Aug–Dec (placement season). Pricing: **₹1,200–2,400 per student per year**, bulk-licensed. A 2,000-student college at ₹1,500 = ₹30 lakh ARR from one logo.

**Segment B — IT services & BPO fresher onboarding.** Infosys/TCS/Wipro-class companies run months of communication training before freshers go client-facing; BPOs assess candidate English at hiring (goFluent sells exactly this). Offer: a **communication-readiness score** built from real simulated client calls (not a one-off test), plus L&D dashboards showing cohort progression. Pricing: **₹500–800/user/month** for active training seats, or an assessment SKU (5 interview simulations + report) priced per candidate for hiring funnels.

**Segment C — White-label for ed-tech/upskilling platforms** (later). The call+report+practice engine behind someone else's brand, per-seat licensing.

### What enterprise needs that we must build (in order)

1. **Org accounts & cohorts** — `orgs`, `org_members`, seat licensing; students join via invite code *(schema + RLS, ~1 week)*
2. **Admin dashboard** (web) — cohort averages, trend, error-pattern aggregates, at-risk list, CSV/PDF export *(the actual selling screen, ~2–3 weeks)*
3. **Assigned tracks** — an admin pins scenarios/coaches ("Interview readiness: 3 David calls/week"), completion tracking
4. **Compliance** — DPDP-compliant data handling, data-deletion endpoints, audio-off-by-default for org accounts; SSO only when a deal demands it
5. **Report credibility** — stable rubric version per cohort so scores are comparable across a semester

### GTM sequence

1. **Now → +6 weeks**: ship consumer core (done), Practice section (this week), dogfood daily
2. **+6 → +10 weeks**: build items 1–2 (cohorts + admin dashboard) — *only after* one college conversation confirms the dashboard spec
3. **Pilot**: 1–2 colleges via founder network, free or ₹99/student for one placement season, in exchange for a measured case study ("cohort grammar score +14 in 8 weeks; interview-readiness ↑")
4. **Sell the case study**: T&P officer WhatsApp/LinkedIn networks are tight — one credible result travels; then approach BPO/IT L&D with the same evidence
5. **Do not** build SSO/SCORM/LMS integrations speculatively — Speexx/goFluent win those RFPs; win the segment they ignore (placement cells) first

### Why we win where incumbents don't

goFluent/Speexx sell to global L&D at global prices with human-coach cost structures. A placement cell with a ₹3-lakh budget is invisible to them — but 40,000+ colleges in India need exactly this, and the product (AI mock interviews with evidence) is our consumer core with a dashboard on top. Start where the giants can't price.

## 4. What this means for the build queue

> **Decision (24 Jul 2026): B2C only for now.** The enterprise track (org
> accounts, cohorts, admin dashboard — §3) is shelved by founder call; §1–2
> remain as the competitive reference. Revisit only if inbound interest shows.

| Priority | Item | Status |
|---|---|---|
| 1 | Practice section (mistakes → drills → next call) | ✅ shipped |
| 2 | Onboarding (level/goal → calibrated coaching from call one) | ✅ shipped |
| 3 | Paywall + RevenueCat (B2C revenue) | next — needs Play Console + RevenueCat accounts |
| 4 | Store prep: SMTP + email confirm, privacy policy, listing assets | after paywall |
