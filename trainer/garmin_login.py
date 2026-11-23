"""Einmalige Garmin-Anmeldung im Terminal (auch mit Zwei-Faktor-Code).

    python -m trainer.garmin_login

Speichert Tokens im Datenordner. Danach braucht die App dein Passwort nicht mehr;
GARMIN_PASSWORD kann aus der .env wieder raus.
"""

from __future__ import annotations

import getpass

from .config import Settings


def main() -> None:
    from garminconnect import Garmin

    s = Settings.load()
    email = s.garmin_email or input("Garmin-E-Mail: ").strip()
    password = s.garmin_password or getpass.getpass("Garmin-Passwort: ")
    client = Garmin(email, password, prompt_mfa=lambda: input("Code aus der Garmin-Mail/App: ").strip())
    s.garmin_tokenstore.mkdir(parents=True, exist_ok=True)
    client.login(str(s.garmin_tokenstore))
    client.client.dump(str(s.garmin_tokenstore))
    print(f"Angemeldet als {client.get_full_name()}. Tokens gespeichert in {s.garmin_tokenstore}")


if __name__ == "__main__":
    main()
