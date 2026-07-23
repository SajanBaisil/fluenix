from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Supabase
    supabase_url: str
    supabase_service_role_key: str
    # HS256 legacy JWT secret. Leave empty on new projects (asymmetric keys):
    # tokens are then verified against /auth/v1/.well-known/jwks.json.
    supabase_jwt_secret: str = ""

    # Gemini
    gemini_api_key: str
    live_model: str = "models/gemini-3.1-flash-live-preview"

    # Metering (seconds per day, IST day boundary — see call_seconds_today())
    free_daily_seconds: int = 300  # 5 min/day (PLAN.md §7 free tier)
    premium_daily_seconds: int = 1800  # 30 min/day fair use

    # Dev escape hatch: if ephemeral-token minting fails, return the raw API
    # key so the app keeps working. NEVER enable in production.
    dev_return_raw_key: bool = False


@lru_cache
def settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
