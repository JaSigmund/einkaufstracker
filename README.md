# Einkaufstracker

Handy-App (Flutter, Android zuerst) zum Scannen von Einkaufsbons, Tracken der Ausgaben nach Kategorie/Artikel, Inventar mit Haltbarkeit und Einkaufsliste. Backend: Supabase.

**Die vollständige Dokumentation liegt im Obsidian-Vault:**
`C:\Users\jakob\Documents\ClaudeBrain\02 Projekte\Einkaufstracker\` (Einstieg: `Einkaufstracker.md`, Anforderungen: `01 Lastenheft.md`)

## Stand (Phase 1 abgeschlossen, 2026-09-26)

| Teil | Status |
|---|---|
| Doku (Lastenheft bis Roadmap) | Erstfassung fertig |
| `supabase/migrations` | 0001 bis 0004 (inkl. Inventar-Ledger): 50 Tests gegen eingebettetes Postgres (`supabase/tests/run_schema_tests.py`) **und** in das echte Supabase-Projekt (Frankfurt) eingespielt, RLS dort geprüft |
| `supabase/planned` | Entwurf Essenstagebuch (Phase 7), wird nicht eingespielt, aber von den Tests auf Einspielbarkeit geprüft |
| `supabase/functions/parse-receipt` | deployt, mit Deno typgeprüft, gegen echte Bons getestet (Sonnet 5 exakt, `tools/test_parse_receipt.py`); Standardmodell per Secret `RECEIPT_MODEL` |
| `spikes/spike_scanner` | Android-Spike auf dem Handy getestet, 17 Unit-Tests (inkl. 3 echte Billa-Bons als Regression, lokal) |
| `tools/test_parse_receipt.py` | Vergleichstest der Cloud-Erkennung (Modelle x Varianten x Fotos), Soll-Werte in `testdata/receipts/truth/` |
| `tools/parse_digital_billa.py` | Prototyp-Parser für digitale Billa-Bons (PDF-Textebene), 6 von 6 Bons exakt (Summe und Steuerblock) |
| Flutter-Umgebung | installiert unter `C:\Users\jakob\dev`, laden mit `. C:\Users\jakob\dev\env.ps1` |
| Flutter-App (`app/`) | Phase 1 fertig: Anmeldung, Offline-Sync (drift + Outbox, automatisch bei Netzrückkehr), Kategorien, Einstellungen, 19 Tests, signierter Release-Build läuft auf dem Handy. Debug-Build: `flutter build apk --debug --dart-define-from-file=dart_defines.local.json`, Release siehe unten |
| CI | GitHub Actions: App (analyze, test), Datenbank (Schema- und RLS-Tests), Edge Function (deno check), alle auf Linux grün |

## Struktur

```
Einkaufstracker/
  supabase/
    migrations/        0001_init, 0002_default_categories, 0003_inventory_movements
    planned/           meal_diary_draft.sql (Phase 7, noch nicht produktiv)
    tests/             run_schema_tests.py (Schema + RLS ohne Docker)
    functions/
      parse-receipt/   Edge Function (Claude Vision)
  tools/               Prototypen (parse_digital_billa.py)
  spikes/spike_scanner Phase-0-Messapp (Scanner, OCR, Barcode, Open Food Facts)
  app/                 Flutter-App (Phase 1, per `flutter create app`)
  testdata/receipts/   Golden Set (Bon-Fotos, OCR-Rohdaten, digital/*.pdf, NICHT einchecken, siehe .gitignore)
```

## Nächste Schritte

Phase 0 und Phase 1 sind abgeschlossen (Go/No-Go-Bericht M0 und Roadmap im Vault unter `02 Projekte/Einkaufstracker/`; Meilenstein M1 auf dem Handy bestätigt). Als Nächstes Phase 2: PDF-Import digitaler Billa-Bons (Branch `feat/pdf-import`), danach Foto-Pfad mit lokaler OCR und Cloud-Fallback. Offen und ohne Eile: Eintrag des Zertifikat-Fingerabdrucks in der Android Developer Console.

## Schema testen (ohne Docker)

```bash
pip install pgserver "psycopg[binary]" tzdata
python supabase/tests/run_schema_tests.py
```

## Lokal starten (sobald Docker + Supabase CLI installiert sind)

```bash
supabase init            # einmalig, erzeugt config.toml
supabase start           # lokale Instanz
supabase db reset        # spielt migrations ein
supabase functions serve parse-receipt --env-file .env.local
```

`.env.local` (nicht einchecken):

```
ANTHROPIC_API_KEY=...
RECEIPT_MODEL=claude-haiku-4-5-20251001
```

## Supabase-CLI (lokal im Repo per npm)

```powershell
cd C:\Users\jakob\Documents\Einkaufstracker
npx supabase login                          # einmalig, Browser-Bestaetigung
npx supabase link --project-ref <ref>       # einmalig (Projekt-ref steht in der Dashboard-URL), Datenbankpasswort nur im Terminal
npx supabase db push --dry-run              # Vorschau
npx supabase db push                        # einspielen
npx supabase db query --linked "select 1"   # Abfrage gegen das Projekt
```

Regel: bereits eingespielte Migrationen (0001 bis 0003) werden nie mehr geaendert, Aenderungen kommen als neue Migration. Datenbankpasswort, Access Tokens und API-Keys gehoeren nie in den Chat oder ins Repo.

## Entwicklungs-Workflow

Ein Projekt mit einer Person, aber mit den Regeln eines Teams, damit der Verlauf nachvollziehbar und `main` immer lauffaehig bleibt.

- **`main` ist stabil.** Es wird nicht direkt darauf gearbeitet. Jede Aenderung kommt ueber einen Branch und einen Pull Request.
- **Branch-Namen:** `feat/<thema>`, `fix/<thema>`, `docs/<thema>`, `chore/<thema>`, `ci/<thema>`, z.B. `feat/pdf-import`.
- **Commits** nach Conventional Commits: `feat(app): ...`, `fix(db): ...`, `docs: ...`, `chore: ...`, `ci: ...`, `test: ...`. Betreff im Imperativ, ein Gedanke pro Commit, im Rumpf das *Warum*.
- **Pull Requests** werden erst gemergt, wenn die CI gruen ist (App: analyze und test, Datenbank: Schema- und RLS-Tests, Edge Function: Typpruefung). Merge per **Squash**, damit `main` eine lineare, lesbare Historie hat.
- **Datenbank:** Migrationen in `supabase/migrations/` sind nach dem Einspielen unveraenderlich. Aenderungen kommen als neue, hoeher nummerierte Datei. Entwuerfe liegen in `supabase/planned/`.
- **Geheimnisse** (Passwoerter, Keystore, API-Keys, Bon-Fotos) gehoeren nie ins Repo. Sie stehen in `.gitignore`. Vor jedem Commit ist der Diff darauf zu pruefen.
- **Meilensteine** werden als Tag markiert (z.B. `m1-phase1`).


## Signierter Release-Build (Android)

1. Der Release-Keystore liegt **außerhalb** des Repos (`C:\Users\jakob\keys\einkaufstracker-release.jks`, Alias `einkaufstracker`), das Passwort im Passwortmanager. Java verlangt für Schlüsselpasswörter reines **ASCII** (keine Umlaute, kein ß, kein Eurozeichen).
2. `app/android/key.properties` nach der Vorlage `key.properties.example` anlegen. `storePassword` und `keyPassword` müssen **identisch** sein (der Schlüssel nutzt das Keystore-Passwort). Die Datei steht in `.gitignore`.
3. Bauen (im Ordner `app`): `flutter build apk --release --dart-define-from-file=dart_defines.local.json`
4. Signatur prüfen: `apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk`. Der Fingerabdruck muss dem des Keystores entsprechen (`keytool -list -v -keystore ... -alias einkaufstracker`, das Passwort gibst du dort selbst ein).

Öffentlicher Zertifikat-Fingerabdruck (SHA-256) der Release-Signatur:
`93:B7:B6:E4:76:FA:8B:AD:8B:D0:1D:19:B0:DE:52:43:F1:A4:0C:EC:8F:B6:AA:52:E3:B5:E0:DB:DD:70:BB:02`

Ohne `key.properties` fällt der Build auf den Debug-Schlüssel zurück, solche APKs sind nur zum lokalen Testen gedacht. Beim Wechsel zwischen Debug- und Release-Signatur muss die App auf dem Gerät vorher deinstalliert werden (die Daten liegen in der Cloud).

## Hinweis zum Branch-Schutz

GitHub bietet den Schutz für `main` (Pull Request und grüne Checks erzwingen) bei privaten Repositories nur mit einem bezahlten Tarif an. Im Free-Tarif gelten die Regeln oben deshalb **per Disziplin**. Aktiv sind dafür: nur Squash-Merge erlaubt, Branches werden nach dem Merge automatisch gelöscht.
