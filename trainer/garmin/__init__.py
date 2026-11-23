from .base import Activity, DailyMetrics, GarminSource, SourceError  # noqa: F401


def make_source(settings):
    """Wählt die Live-Quelle: Demo, offizielle Personal API, sonst der
    inoffizielle Garmin-Connect-Zugang (falls konfiguriert)."""
    if settings.demo_mode:
        from .demo import DemoSource

        return DemoSource()
    if settings.garmin_personal_api_key:
        from .personal_api import PersonalApiSource

        return PersonalApiSource(settings.garmin_personal_api_key,
                                 settings.data_dir / "garmin-personal-token.json")
    if settings.garmin_email or settings.garmin_tokenstore.exists():
        from .connect import GarminConnectSource

        return GarminConnectSource(
            settings.garmin_email, settings.garmin_password, settings.garmin_tokenstore
        )
    return None
