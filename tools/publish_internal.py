#!/usr/bin/env python3
"""Laedt ein signiertes App Bundle in die Google Play Console hoch, IMMER auf den Track
"internal" (Internal Testing) -- niemals automatisiert oeffentlich sichtbar.

WICHTIGE REGEL (2026-09-29, feste Anweisung): Automatisierte Play-Console-Releases duerfen
NUR auf Internal Testing gehen, nie auf alpha/beta/production. Der Track ist deshalb absichtlich
nirgends als Kommandozeilen-Parameter oder Umgebungsvariable veraenderbar, sondern fest im Code
verdrahtet (siehe TRACK unten) und wird vor jedem Aufruf per assert geprueft.

Nutzung:
    python tools/publish_internal.py [--aab PFAD] [--notes TEXT] [--key PFAD]

Vorbereitung (einmalig, siehe Vault 02 Projekte/Einkaufstracker/18 Play Console Store-Eintrag.md):
    1. Google-Cloud-Projekt + Android Publisher API aktiviert
    2. Service-Konto angelegt, JSON-Schluessel heruntergeladen
    3. Service-Konto in Play Console -> Nutzer und Berechtigungen mit "Releases verwalten"
       eingeladen (kein Bestaetigungsschritt fuer Service-Konten noetig, wird automatisch aktiv)
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# Fest verdrahtet, siehe Modul-Docstring oben -- absichtlich kein CLI-Parameter.
TRACK = "internal"
PACKAGE_NAME = "at.jakob.einkaufstracker"
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]

DEFAULT_KEY_PATH = r"C:\Users\jakob\keys\einkaufstracker-release-510121-4f068f5a5735.json"
DEFAULT_AAB_PATH = Path(__file__).resolve().parent.parent / "app" / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"


def publish(aab_path: Path, key_path: Path, notes: str) -> None:
    assert TRACK == "internal", "Sicherheitsregel: automatisierte Releases gehen NUR auf internal"
    if not aab_path.is_file():
        sys.exit(f"App Bundle nicht gefunden: {aab_path}")
    if not key_path.is_file():
        sys.exit(f"Service-Konto-Schluessel nicht gefunden: {key_path}")

    creds = service_account.Credentials.from_service_account_file(str(key_path), scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds)
    edits = service.edits()

    edit = edits.insert(body={}, packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]
    print(f"Edit angelegt: {edit_id}")

    try:
        media = MediaFileUpload(str(aab_path), mimetype="application/octet-stream")
        upload = edits.bundles().upload(editId=edit_id, packageName=PACKAGE_NAME, media_body=media).execute()
        version_code = upload["versionCode"]
        print(f"Bundle hochgeladen, versionCode {version_code}")

        release = {"versionCodes": [str(version_code)], "status": "completed"}
        if notes:
            release["releaseNotes"] = [{"language": "de-DE", "text": notes}]

        edits.tracks().update(
            editId=edit_id,
            track=TRACK,
            packageName=PACKAGE_NAME,
            body={"track": TRACK, "releases": [release]},
        ).execute()
        print(f"Track '{TRACK}' aktualisiert")

        edits.commit(editId=edit_id, packageName=PACKAGE_NAME).execute()
        print(f"Release {version_code} auf '{TRACK}' veroeffentlicht.")
    except Exception:
        edits.delete(editId=edit_id, packageName=PACKAGE_NAME).execute()
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aab", type=Path, default=DEFAULT_AAB_PATH, help="Pfad zum .aab")
    parser.add_argument("--notes", default="", help="Versionshinweise (release notes)")
    parser.add_argument(
        "--key",
        type=Path,
        default=Path(os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", DEFAULT_KEY_PATH)),
        help="Pfad zum Service-Konto-JSON-Schluessel",
    )
    args = parser.parse_args()
    publish(args.aab, args.key, args.notes)


if __name__ == "__main__":
    main()
