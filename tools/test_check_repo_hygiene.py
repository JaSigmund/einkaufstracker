"""Tests fuer tools/check_repo_hygiene.py. Aufruf: python tools/test_check_repo_hygiene.py

Die Geheimnisse hier sind ausgedacht und werden zur Laufzeit zusammengesetzt, damit diese Datei selbst keinen Fund
ausloest (und keine echte Zeichenfolge eines Dienstes enthaelt).
"""
import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_repo_hygiene as m  # noqa: E402

results = []


def check(name, cond):
    results.append(bool(cond))
    print(("PASS " if cond else "FAIL ") + name)


def b64(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")


def jwt(role):
    return f"{b64({'alg': 'HS256', 'typ': 'JWT'})}.{b64({'iss': 'supabase', 'role': role})}.{'x' * 30}"


def whats(path, text):
    return [w for _, _, w in m.scan_text(path, text)]


# --- Inhalt -----------------------------------------------------------------------------------------------------------
check("Service-Role-JWT wird erkannt", whats("a.dart", f"const k = '{jwt('service_role')}';") ==
      ["JWT mit Rolle service_role (Service-Schluessel)"])
check("Anon-JWT wird gemeldet (gehoert nach dart_defines.local.json)", any("anon" in w for w in whats("a.dart", jwt("anon"))))
check("Anthropic-Key wird erkannt", whats("x.ts", "sk-" + "ant-" + "a" * 30) == ["Anthropic-API-Key"])
check("Supabase-Secret-Key wird erkannt", whats("x.ts", "sb_" + "secret_" + "b" * 30) == ["Supabase-Secret-Key"])
check("privater Schluessel wird erkannt", whats("k.txt", "-----BEGIN " + "PRIVATE KEY-----") == ["privater Schluessel"])
check("GitHub-Token wird erkannt", whats("c.yml", "token: gh" + "p_" + "c" * 36) == ["GitHub-Token"])
check("Zeilennummer stimmt", m.scan_text("a.md", "eins\nzwei\nsk-" + "ant-" + "d" * 30)[0][1] == 3)
check("normaler Code ist sauber", whats("a.dart", "final url = String.fromEnvironment('SUPABASE_URL');\nconst x = 'eyJ';") == [])
check("kaputtes JWT-aehnliches Muster ohne lesbare Rolle ist kein Fund", whats("a.dart", "eyJ" + "a" * 20 + ".eyJ" + "!" * 5) == [])
check("Ausnahmeliste greift fuer die Tests des Skripts", m.scan_text("tools/test_check_repo_hygiene.py", jwt("service_role")) == [])

# --- Pfade ------------------------------------------------------------------------------------------------------------
for bad in ["app/android/key.properties", "release.jks", ".env", "supabase/.env.local", "app/dart_defines.local.json",
            "testdata/receipts/bon1.jpg", "backups/2026-10-01.sql", "tools/.test_config.json"]:
    check(f"verbotener Pfad: {bad}", m.scan_path(bad) != [])
for ok in ["app/dart_defines.example.json", "app/android/key.properties.example", "supabase/migrations/0001_init.sql",
           "tools/env_notes.md"]:
    check(f"erlaubter Pfad: {ok}", m.scan_path(ok) == [])

# --- Das Repo selbst --------------------------------------------------------------------------------------------------
check("das Repository ist sauber (dasselbe, was die CI prueft)", m.main(["check_repo_hygiene.py"]) == 0)

failed = results.count(False)
print(f"\n{len(results) - failed}/{len(results)} Tests bestanden")
sys.exit(1 if failed else 0)
