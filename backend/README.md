# Fluenix backend

Slim FastAPI service (PLAN.md §2): the only two things the Flutter app can't do
safely through Supabase RLS — minting voice-session tokens with metering, and
(week 6–7) the Claude analysis pipeline.

## Endpoints

| Method | Path | What it does |
|---|---|---|
| `POST` | `/v1/session` | Checks today's minute balance → creates a `calls` row → mints a **single-use, model-locked, 35-min Gemini ephemeral token**. The raw API key never reaches the device. |
| `POST` | `/v1/calls/{id}/end` | Marks the call ended, stores the transcript, burns seconds into `minute_ledger`, bumps the daily rollup. Idempotent. |
| `GET` | `/v1/me/limits` | Tier + remaining seconds today — drives the home screen goal ring. |
| `GET` | `/healthz` | Liveness. |

Auth: every `/v1/*` call needs the Supabase access token as `Authorization: Bearer <jwt>`. Verified via the project's JWKS (or `SUPABASE_JWT_SECRET` on legacy projects).

Metering: free = 300 s/day, premium = 1800 s/day (config), day boundary in IST via `call_seconds_today()` (see migration). Values are deliberately remote-tunable per PLAN.md §7.

## Setup

```sh
# 1. Create the Supabase project (dashboard), then from the repo root:
supabase login
supabase link --project-ref <your-project-ref>
supabase db push          # applies supabase/migrations/

# 2. Configure the backend:
cd backend
cp .env.example .env      # fill in: SUPABASE_URL, SERVICE_ROLE_KEY, GEMINI_API_KEY

# 3. Run:
uv run uvicorn app.main:app --reload
# → http://127.0.0.1:8000/docs
```

## Notes

- `supa.py` is a deliberately thin PostgREST wrapper using the service-role key — no client-library magic between us and the DB.
- Ephemeral tokens: `POST /v1alpha/auth_tokens` with `bidiGenerateContentSetup` (field name verified against the live API 2026-07-23 — the docs' `liveConnectConstraints` no longer exists). The Flutter client connects with `?access_token=<token>` instead of `?key=`.
- `DEV_RETURN_RAW_KEY=true` in `.env` falls back to returning the raw key if minting breaks (preview APIs drift). Dev only.
- Deploy target: Railway/Fly hobby tier (PLAN.md §9). `uvicorn app.main:app --host 0.0.0.0 --port $PORT`.
