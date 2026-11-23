"""Konfiguration aus Umgebungsvariablen (siehe .env.example)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    db_path: Path
    app_token: str | None
    garmin_personal_api_key: str | None
    garmin_email: str | None
    garmin_password: str | None
    garmin_tokenstore: Path
    anthropic_model: str
    coach_enabled: bool
    timezone: str
    demo_mode: bool

    @classmethod
    def load(cls) -> "Settings":
        data_dir = Path(_env("TRAINER_DATA_DIR", "./data")).resolve()
        data_dir.mkdir(parents=True, exist_ok=True)
        has_key = bool(_env("ANTHROPIC_API_KEY") or _env("ANTHROPIC_AUTH_TOKEN"))
        return cls(
            data_dir=data_dir,
            db_path=data_dir / "trainer.db",
            app_token=_env("TRAINER_TOKEN"),
            garmin_personal_api_key=_env("GARMIN_PERSONAL_API_KEY"),
            garmin_email=_env("GARMIN_EMAIL"),
            garmin_password=_env("GARMIN_PASSWORD"),
            garmin_tokenstore=Path(_env("GARMIN_TOKENSTORE", str(data_dir / "garmin-tokens"))),
            anthropic_model=_env("TRAINER_MODEL", "claude-opus-5-5"),
            coach_enabled=has_key and _env("TRAINER_COACH", "on") != "off",
            timezone=_env("TZ", "Europe/Berlin"),
            demo_mode=_env("TRAINER_DEMO", "off") == "on",
        )
