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
HEALTH_READ = [
    "STEPS", "ACTIVE_CALORIES_BURNED", "TOTAL_CALORIES_BURNED", "BASAL_METABOLIC_RATE",
    "RESTING_HEART_RATE", "HEART_RATE_VARIABILITY", "SLEEP", "EXERCISE", "DISTANCE",
]


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
    # Health Connect (Amazfit/Zepp, Suunto und andere Uhren): nur Leserechte
    if "android.permission.health." not in t:
        perms = "".join(f'<uses-permission android:name="android.permission.health.READ_{p}"/>\n    ' for p in HEALTH_READ)
        queries = (
            "<queries>\n"
            '        <package android:name="com.google.android.apps.healthdata"/>\n'
            '        <intent><action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/></intent>\n'
            "    </queries>\n    "
        )
        t = t.replace("<application", perms + queries + "<application", 1)
    if "ACTION_SHOW_PERMISSIONS_RATIONALE\"/>\n            </intent-filter>" not in t:
        rationale = (
            "<intent-filter>\n"
            '                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>\n'
            "            </intent-filter>\n"
            "        </activity>"
        )
        t = t.replace("</activity>", rationale, 1)
    if "ViewPermissionUsageActivity" not in t:
        alias = (
            "</activity>\n"
            "        <activity-alias\n"
            '            android:name="ViewPermissionUsageActivity"\n'
            '            android:exported="true"\n'
            '            android:targetActivity=".MainActivity"\n'
            '            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">\n'
            "            <intent-filter>\n"
            '                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>\n'
            '                <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>\n'
            "            </intent-filter>\n"
            "        </activity-alias>"
        )
        t = t.replace("</activity>", alias, 1)
    return t


def main_activity(t: str) -> str:
    # Health Connect fragt Berechtigungen über registerForActivityResult ab
    t = t.replace("io.flutter.embedding.android.FlutterActivity", "io.flutter.embedding.android.FlutterFragmentActivity")
    return re.sub(r"\bFlutterActivity\(\)", "FlutterFragmentActivity()", t)


def gradle_kts(t: str) -> str:
    t = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 26", t)
    # Lint-Absturz in einem Plugin (ExifDataCopier.java, Fehler im Lint-Werkzeug) bricht sonst den Release-Build ab
    if "checkReleaseBuilds" not in t:
        t = re.sub(r"(\nandroid\s*\{)", r"\1\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }", t, count=1)
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
_acts = list((root / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
if not _acts:
    raise SystemExit("fehlt: MainActivity.kt")
patch(_acts[0], main_activity)
print("Plattform-Anpassungen abgeschlossen.")
