import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from trainer.coach import Coach  # noqa: E402
from trainer.config import Settings  # noqa: E402
from trainer.garmin.demo import DemoSource  # noqa: E402
from trainer.service import TrainerService  # noqa: E402


@pytest.fixture
def settings(tmp_path):
    return Settings(
        data_dir=tmp_path,
        db_path=tmp_path / "t.db",
        app_token=None,
        garmin_personal_api_key=None,
        garmin_email=None,
        garmin_password=None,
        garmin_tokenstore=tmp_path / "tok",
        anthropic_model="claude-opus-5-5",
        coach_enabled=False,
        timezone="Europe/Berlin",
        demo_mode=True,
    )


@pytest.fixture
def service(settings):
    return TrainerService(settings, coach=Coach(False, "claude-opus-5-5"), source=DemoSource())
