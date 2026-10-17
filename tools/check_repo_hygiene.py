"""Prueft die versionierten Dateien auf Geheimnisse und Dateien, die nie ins Repo gehoeren (Codereview 2026-10-16).

Die README-Regel "Geheimnisse gehoeren nie ins Repo, vor jedem Commit ist der Diff darauf zu pruefen" galt bisher nur
per Disziplin. Dieses Skript laeuft in der CI (Job "Repo-Hygiene") und lokal:

    python tools/check_repo_hygiene.py            # alle versionierten Dateien (git ls-files)
    python tools/check_repo_hygiene.py DATEI ...  # nur diese Dateien (z.B. als pre-commit-Hook)

Geprueft wird:
  * verbotene Pfade: Keystores, key.properties, .env-Dateien, die lokale App-Konfiguration, das Golden Set mit Bon-Fotos,
    Datenbank-Backups (siehe .gitignore)
  * Geheimnisse im Inhalt: Anthropic-Keys, Supabase-Secret-Keys, JWTs mit der Rolle service_role, private Schluessel,
    GitHub- und AWS-Tokens. Der oeffentliche Client-Schluessel (publishable/anon) ist kein Geheimnis, gehoert aber
    trotzdem nicht ins Repo (AppConfig liest ihn aus --dart-define) und wird deshalb ebenfalls gemeldet.

Eine bewusste Ausnahme (z.B. ein Test, der genau so ein Muster pruefen muss) steht mit Grund in ALLOW.
Rueckgabe: 0 = sauber, 1 = Funde (mit Datei und Zeile, ohne den Fund selbst auszugeben).
"""
import base64
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FORBIDDEN_PATHS = [
    (re.compile(r"\.(jks|keystore|p12|pem)$"), "Schluesseldatei"),
    (re.compile(r"(^|/)key\.properties$"), "Signier-Passwoerter"),
    (re.compile(r"(^|/)\.env($|\.)"), "Umgebungsvariablen mit Secrets"),
    (re.compile(r"(^|/)dart_defines\.local\.json$"), "lokale App-Konfiguration"),
    (re.compile(r"^testdata/receipts/"), "Bon-Fotos (persoenliche Daten)"),
    (re.compile(r"^backups/"), "Datenbank-Backup (alle Nutzerdaten)"),
    (re.compile(r"(^|/)\.test_config\.json$"), "Testkonfiguration mit Projekt-URL"),
]

SECRET_PATTERNS = [
    (re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}"), "Anthropic-API-Key"),
    (re.compile(r"sb_secret_[A-Za-z0-9_-]{20,}"), "Supabase-Secret-Key"),
    (re.compile(r"sb_publishable_[A-Za-z0-9_-]{20,}"), "Supabase-Client-Schluessel (gehoert in dart_defines.local.json)"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "privater Schluessel"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}"), "GitHub-Token"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS-Zugangsschluessel"),
]
JWT = re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}")

# (Pfad, Musterbeschreibung) -> Grund
ALLOW = {
    ("tools/test_check_repo_hygiene.py", "*"): "Tests dieses Skripts bauen die Muster absichtlich zusammen",
}

TEXT_SUFFIXES = {
    ".dart", ".ts", ".js", ".py", ".sql", ".json", ".yaml", ".yml", ".toml", ".md", ".txt", ".csv", ".sh", ".ps1",
    ".kts", ".gradle", ".xml", ".html", ".properties", ".env", ".cfg", ".ini", "",
}


def jwt_role(token_payload: str):
    """Rolle aus dem Payload eines JWT (zweiter Teil), None wenn nicht lesbar."""
    try:
        padded = token_payload + "=" * (-len(token_payload) % 4)
        return json.loads(base64.urlsafe_b64decode(padded)).get("role")
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError, AttributeError):
        return None


def scan_text(path: str, text: str):
    """Funde in einem Dateiinhalt als (Pfad, Zeile, Beschreibung)."""
    if (path, "*") in ALLOW:
        return []
    found = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for pattern, what in SECRET_PATTERNS:
            if pattern.search(line) and (path, what) not in ALLOW:
                found.append((path, lineno, what))
        for m in JWT.finditer(line):
            role = jwt_role(m.group(1))
            if role == "service_role":
                found.append((path, lineno, "JWT mit Rolle service_role (Service-Schluessel)"))
            elif role is not None:
                found.append((path, lineno, f"JWT (Rolle {role}) gehoert nicht ins Repo"))
    return found


def scan_path(path: str):
    return [(path, 0, what) for pattern, what in FORBIDDEN_PATHS if pattern.search(path)]


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def main(argv):
    paths = argv[1:] or tracked_files()
    findings = []
    for p in paths:
        rel = Path(p).as_posix()
        findings += scan_path(rel)
        file = ROOT / rel
        if not file.is_file() or file.suffix.lower() not in TEXT_SUFFIXES or file.stat().st_size > 5_000_000:
            continue
        try:
            text = file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        findings += scan_text(rel, text)
    for path, line, what in findings:
        print(f"FUND {path}{':' + str(line) if line else ''}: {what}")
    print(f"{len(paths)} Dateien geprueft, {len(findings)} Fund(e)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
