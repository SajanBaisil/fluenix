from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routes.daily import router as daily_router
from .routes.practice import router as practice_router
from .routes.session import router as session_router

app = FastAPI(title="Fluenix API", version="0.1.0")

# The app talks to us from device IPs; lock this down before production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(session_router)
app.include_router(practice_router)
app.include_router(daily_router)


@app.get("/healthz")
async def healthz() -> dict[str, bool]:
    return {"ok": True}
