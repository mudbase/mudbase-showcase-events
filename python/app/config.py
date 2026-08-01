"""Environment configuration.

Mirrors ../web/src/lib/config.ts and the sibling mudbase-showcase-kanban/
mudbase-showcase-social Python ports' app/config.py: fail fast at startup if
a required project/collection ID is missing, rather than surfacing a
confusing error deep inside a request handler later.
"""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    mudbase_url: str = Field(default="https://cloud.mudbase.dev", alias="MUDBASE_URL")
    mudbase_project_id: str = Field(alias="MUDBASE_PROJECT_ID")
    events_collection_id: str = Field(alias="EVENTS_COLLECTION_ID")
    bookings_collection_id: str = Field(alias="BOOKINGS_COLLECTION_ID")
    activity_collection_id: str = Field(alias="ACTIVITY_COLLECTION_ID")

    session_secret_key: str = Field(alias="SESSION_SECRET_KEY")
    session_cookie_name: str = Field(default="mudbase_showcase_events_session", alias="SESSION_COOKIE_NAME")
    session_https_only: bool = Field(default=False, alias="SESSION_HTTPS_ONLY")

    # Quick sign-in demo accounts for the /login page — the two already-verified accounts this
    # showcase's task description provides. Not a production secret: this whole app is a public
    # demo and these credentials are already published in this project's own README/build-plan.
    # Override via .env for a private deployment.
    demo_organizer_email: str = Field(default="events.organizer.demo@gmail.com", alias="DEMO_ORGANIZER_EMAIL")
    demo_attendee_email: str = Field(default="events.attendee.demo@gmail.com", alias="DEMO_ATTENDEE_EMAIL")
    demo_password: str = Field(default="DemoTest123!", alias="DEMO_PASSWORD")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached so env parsing/validation happens once per process, not per request."""
    return Settings()  # type: ignore[call-arg]  # values come from the environment/.env file
