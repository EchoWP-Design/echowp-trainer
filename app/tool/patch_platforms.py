"""Passt die von `flutter create` erzeugten Android-Dateien an (läuft im GitHub-Build).

Plattformordner liegen nicht im Repo, sie entstehen im Build neu (wie bei EchoWP-Mail).
"""
import os
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
KEYSTORE = root / "keystore" / "echowp-release.jks"
PW = os.environ.get("ANDROID_KEYSTORE_PASSWORD", "")
_alias_file = root / "keystore" / "alias.txt"
ALIAS = _alias_file.read_text().strip() if _alias_file.exists() else "echowp"


def patch(path: pathlib.Path, fn):
    if not path.exists():
        raise SystemExit(f"fehlt: {path}")
    old = path.read_text(encoding="utf-8")
    new = fn(old)
    if new != old:
        path.write_text(new, encoding="utf-8")
        print(f"angepasst: {path.relative_to(root)}")


def manifest(t: str) -> str:
    t = re.sub(r'android:label="[^"]*"', 'android:label="EchoWP Trainer"', t, count=1)
    # Keine Android-Cloud-/ADB-Sicherung (Schlüssel, Gesundheitsdaten)
    if "android:allowBackup" not in t:
        t = t.replace("<application", '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"', 1)
    if "android.permission.CAMERA" not in t:
        t = t.replace("<application", '<uses-permission android:name="android.permission.CAMERA"/>\n    <application', 1)
    if "android.permission.INTERNET" not in t:
        t = t.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
    return t


def gradle_kts(t: str) -> str:
    t = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", t)
    if KEYSTORE.exists() and PW:
        if 'create("release")' not in t:
            signing = (
                "    signingConfigs {\n"
                '        create("release") {\n'
                '            storeFile = file("../../keystore/echowp-release.jks")\n'
                f'            storePassword = "{PW}"\n'
                f'            keyAlias = "{ALIAS}"\n'
                f'            keyPassword = "{PW}"\n'
                "        }\n"
                "    }\n"
            )
            t = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + signing.rstrip("\n") + r"\1", t, count=1)
        t = t.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
        print("Signatur: EchoWP-Release-Schlüssel")
    else:
        print("::warning::Kein Release-Schlüssel (Secrets ANDROID_KEYSTORE_B64/ANDROID_KEYSTORE_PASSWORD fehlen): "
              "Testversion mit Debug-Signatur, Updates nur nach Deinstallation möglich.")
    return t


patch(root / "android/app/src/main/AndroidManifest.xml", manifest)
patch(root / "android/app/build.gradle.kts", gradle_kts)
print("Plattform-Anpassungen abgeschlossen.")
