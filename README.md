# Einkaufstracker

Handy-App (Flutter, Android zuerst) zum Scannen von Einkaufsbons, Tracken der Ausgaben nach Kategorie/Artikel, Inventar mit Haltbarkeit und Einkaufsliste. Backend: Supabase.

**Die vollständige Dokumentation liegt im Obsidian-Vault:**
`C:\Users\jakob\Documents\ClaudeBrain\02 Projekte\Einkaufstracker\` (Einstieg: `Einkaufstracker.md`, Anforderungen: `01 Lastenheft.md`)

## Stand (Phase 0, 2026-09-26)

| Teil | Status |
|---|---|
| Doku (Lastenheft bis Roadmap) | Erstfassung fertig |
| `supabase/migrations` | 0001 bis 0003 (inkl. Inventar-Ledger): 46 Tests gegen eingebettetes Postgres (`supabase/tests/run_schema_tests.py`) **und** in das echte Supabase-Projekt (Frankfurt) eingespielt, RLS dort geprüft |
| `supabase/planned` | Entwurf Essenstagebuch (Phase 7), wird nicht eingespielt, aber von den Tests auf Einspielbarkeit geprüft |
| `supabase/functions/parse-receipt` | deployt, mit Deno typgeprüft, gegen echte Bons getestet (Sonnet 5 exakt, `tools/test_parse_receipt.py`); Standardmodell per Secret `RECEIPT_MODEL` |
| `spikes/spike_scanner` | Android-Spike auf dem Handy getestet, 17 Unit-Tests (inkl. 3 echte Billa-Bons als Regression, lokal) |
| `tools/test_parse_receipt.py` | Vergleichstest der Cloud-Erkennung (Modelle x Varianten x Fotos), Soll-Werte in `testdata/receipts/truth/` |
| `tools/parse_digital_billa.py` | Prototyp-Parser für digitale Billa-Bons (PDF-Textebene), 6 von 6 Bons exakt (Summe und Steuerblock) |
| Flutter-Umgebung | installiert unter `C:\Users\jakob\dev`, laden mit `. C:\Users\jakob\dev\env.ps1` |
| Flutter-App (`app/`) | Phase 1: Anmeldung, Offline-Sync (drift + Outbox), Kategorien, Einstellungen, 19 Tests, läuft auf dem Handy. Bauen: `flutter build apk --debug --dart-define-from-file=dart_defines.local.json` |

## Struktur

```
Einkaufstracker/
  supabase/
    migrations/        0001_init, 0002_default_categories, 0003_inventory_movements
    planned/           0005_meal_diary.sql (Phase 7, noch nicht produktiv)
    tests/             run_schema_tests.py (Schema + RLS ohne Docker)
    functions/
      parse-receipt/   Edge Function (Claude Vision)
  tools/               Prototypen (parse_digital_billa.py)
  spikes/spike_scanner Phase-0-Messapp (Scanner, OCR, Barcode, Open Food Facts)
  app/                 Flutter-App (Phase 1, per `flutter create app`)
  testdata/receipts/   Golden Set (Bon-Fotos, OCR-Rohdaten, digital/*.pdf, NICHT einchecken, siehe .gitignore)
```

## Nächste Schritte

Phase 0 läuft in Schritten S1 bis S8, siehe `11 Roadmap und Meilensteine.md` im Vault. Phase 0 ist abgeschlossen (Go/No-Go-Bericht: `16 Go-No-Go-Bericht M0.md` im Vault, Ergebnis Go mit 4 Bedingungen). Phase 1 läuft (Meilenstein M1 auf dem Handy geprüft). Offen: signierter Release-Build (`app/android/key.properties`), CI, danach Phase 2 mit dem PDF-Import.

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
