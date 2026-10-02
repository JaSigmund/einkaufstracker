# Einkaufstracker

Handy-App (Flutter, Android zuerst) zum Scannen von Einkaufsbons, Tracken der Ausgaben nach Kategorie/Artikel, Inventar mit Haltbarkeit und Einkaufsliste. Backend: Supabase.

**Die vollständige Dokumentation liegt im Obsidian-Vault:**
`C:\Users\jakob\Documents\ClaudeBrain\02 Projekte\Einkaufstracker\` (Einstieg: `Einkaufstracker.md`, Anforderungen: `01 Lastenheft.md`)

## Stand (Phase 5 abgeschlossen, Phase 7a Fundament läuft, 2026-10-02)

| Teil | Status |
|---|---|
| Doku (Lastenheft bis Roadmap) | Laufend nachgeführt, siehe Roadmap für den Phasenstand |
| `supabase/migrations` | 0001 bis 0014 (Schema, Kategorien, Ledger, Bon-Import, Kategorie-Aliase, Bon-Rabatte, Originalbelege, Fehlerberichte + Bearbeitungsstatus/Changelog, Feature-Requests, App-Konfiguration, Essenstagebuch + BLS-Referenztabelle); Schema-/RLS-Tests gegen eingebettetes Postgres (`supabase/tests/run_schema_tests.py`, 78 Tests) **und** gegen das echte Supabase-Projekt (Frankfurt) eingespielt. `shopping_lists`/`shopping_list_items` lagen schon seit 0001 bereit, client-seitig erst seit Phase 3 angebunden |
| `supabase/planned` | Leer. Entwürfe für kommende Phasen (z.B. Haushalts-Einladungen, Phase 6) liegen hier, werden nicht eingespielt, aber von den Tests auf Einspielbarkeit geprüft |
| `supabase/functions/parse-receipt` | deployt, mit Deno typgeprüft, gegen echte Bons getestet (Sonnet 5 exakt, `tools/test_parse_receipt.py`); Standardmodell per Secret `RECEIPT_MODEL` |
| `spikes/spike_scanner` | Android-Spike auf dem Handy getestet, 17 Unit-Tests (inkl. 3 echte Billa-Bons als Regression, lokal) |
| `tools/test_parse_receipt.py` | Vergleichstest der Cloud-Erkennung (Modelle x Varianten x Fotos), Soll-Werte in `testdata/receipts/truth/` |
| `tools/metrics.py` | Kennzahlen aus dem Testkonzept (Bons je Quelle, Summenstimmigkeit, Fallback-Quote, Kosten, Kategorisierung) aus den Live-Daten, nur lesend: `python tools/metrics.py` |
| `tools/parse_digital_billa.py` | Prototyp-Parser für digitale Billa-Bons (PDF-Textebene), 6 von 6 Bons exakt (Summe und Steuerblock) |
| Flutter-Umgebung | installiert unter `C:\Users\jakob\dev`, laden mit `. C:\Users\jakob\dev\env.ps1` |
| Flutter-App (`app/`) | Phase 2 bis 5 fertig (Phase 5: Abnahme nach Lastenheft §6 bestanden, siehe Roadmap), Phase 4 (Preisvergleich und Trends) komplett umgesetzt: Anmeldung, Offline-Sync, Kategorien, Einstellungen, Bon-Import (PDF, Teilen, Foto+Cloud-Fallback), Kategorisierung, Monatsauswertung mit Grundpreis/Produkt-Zuordnung je Artikel, Duplikate zusammenführen, Artikel-Detail (Preisverlauf, Händlervergleich), Trend über 6/12 Monate, Monatsbudget, CSV-Export, Barcode-Inventar mit Haltbarkeit und Ampel, Haltbarkeits-Vorbelegung nach Produkttyp, Einkaufsliste (Menge/Inhalt, Vorschläge aus „Leer“/„Ablauf“, hakt sich bei Bon-Zuordnung selbst ab), lokale Ablauf-Benachrichtigungen mit Aktionen, Stückgewicht aus Open Food Facts. 673 Tests, signierter Release-Build (aktuell v1.7.15) läuft auf dem Handy. Debug-Build: `flutter build apk --debug --dart-define-from-file=dart_defines.local.json`, Release siehe unten |
| CI | GitHub Actions: App (analyze, test), Datenbank (Schema- und RLS-Tests), Edge Function (deno check), alle auf Linux grün |

## Struktur

```
Einkaufstracker/
  supabase/
    migrations/        0001 bis 0014 (Schema inkl. Einkaufsliste, Kategorien, Ledger, Bon-Import, Kategorie-Aliase,
                        Bon-Rabatte, Originalbelege, Fehlerberichte, Bearbeitungsstatus/Changelog,
                        Feature-Requests, App-Konfiguration, Essenstagebuch + BLS-Referenztabelle)
    planned/           leer (Entwürfe für kommende Phasen, z.B. Haushalts-Einladungen)
    tests/             run_schema_tests.py (Schema + RLS ohne Docker)
    functions/
      parse-receipt/   Edge Function (Claude Vision)
  tools/               Prototypen und einmalige SQL-Skripte (parse_digital_billa.py, changelog_*.sql, bugstatus_*.sql)
  spikes/spike_scanner Phase-0-Messapp (Scanner, OCR, Barcode, Open Food Facts)
  app/                 Flutter-App (Phase 2 bis 4)
  testdata/receipts/   Golden Set (Bon-Fotos, OCR-Rohdaten, digital/*.pdf, NICHT einchecken, siehe .gitignore)
```

## Nächste Schritte

Phase 0 bis 4 sind aus Code-Sicht abgeschlossen (siehe [[11 Roadmap und Meilensteine]] im Vault). **Offen aus Phase 3:** Ausloeser „Wiederkehrend“ für Listen-Vorschläge, die Haltbarkeits-Startwerte selbst sind noch nicht gegen Herstellerangaben/AGES verifiziert (Doku 06 §3.2), und M3 (zwei Wochen Praxistest mit den Ablauf-Erinnerungen im Alltag). **Offen aus Phase 4:** M4 selbst (Praxistest mit echten Daten; aktuell nur 7 Bons über ~3 Monate, Händlervergleich damit noch nicht aussagekräftig, zeigt aber korrekt „zu wenig Daten“), `share_plus` (CSV-Export) noch nicht auf dem Handy geprüft. **Weiterhin offen aus Phase 2, läuft parallel:** Hofer-Bons, weitere jö-PDFs fürs Golden Set, Diagnose der lokalen Foto-Erkennung. **Als Nächstes:** Phase 5 (Härtung und Abnahme) oder die offenen Phase-3/4-Punkte zuerst schliessen.

**Migrationen anwenden:** `npx supabase db push --dry-run`, dann `npx supabase db push --yes` (gegen das Live-Projekt, verknüpft per `supabase link`). Neue Migrationen müssen live sein, **bevor** die App-Version mit dem neuen Schema installiert wird.

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

Regel: bereits eingespielte Migrationen (alle bis einschliesslich 0014) werden nie mehr geaendert, Aenderungen kommen als neue Migration. Datenbankpasswort, Access Tokens und API-Keys gehoeren nie in den Chat oder ins Repo.

## Entwicklungs-Workflow

Ein Projekt mit einer Person, aber mit den Regeln eines Teams, damit der Verlauf nachvollziehbar und `main` immer lauffaehig bleibt.

- **`main` ist stabil.** Es wird nicht direkt darauf gearbeitet. Jede Aenderung kommt ueber einen Branch und einen Pull Request.
- **Branch-Namen:** `feat/<thema>`, `fix/<thema>`, `docs/<thema>`, `chore/<thema>`, `ci/<thema>`, z.B. `feat/pdf-import`.
- **Commits** nach Conventional Commits: `feat(app): ...`, `fix(db): ...`, `docs: ...`, `chore: ...`, `ci: ...`, `test: ...`. Betreff im Imperativ, ein Gedanke pro Commit, im Rumpf das *Warum*.
- **Pull Requests** werden erst gemergt, wenn die CI gruen ist (App: analyze und test, Datenbank: Schema- und RLS-Tests, Edge Function: Typpruefung). Merge per **Squash**, damit `main` eine lineare, lesbare Historie hat.
- **Datenbank:** Migrationen in `supabase/migrations/` sind nach dem Einspielen unveraenderlich. Aenderungen kommen als neue, hoeher nummerierte Datei. Entwuerfe liegen in `supabase/planned/`.
- **Lokale Datenbank (Drift):** Wer `schemaVersion` in `app/lib/data/local/database.dart` erhoeht, ergaenzt den Zweig in `onUpgrade`, fuehrt `dart run build_runner build --delete-conflicting-outputs` aus und erzeugt danach das neue Schema fuer den Migrationstest: `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/` und `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`. `test/db_migration_test.dart` prueft, dass sich jeder installierte Stand auf das aktuelle Schema hochziehen laesst (die neue Version dort in der Liste der Vorgaengerstaende ergaenzen, sobald sie in einem Release war).
- **Geheimnisse** (Passwoerter, Keystore, API-Keys, Bon-Fotos) gehoeren nie ins Repo. Sie stehen in `.gitignore`. Vor jedem Commit ist der Diff darauf zu pruefen.
- **Meilensteine** werden als Tag markiert (z.B. `m1-phase1`).


## Signierter Release-Build (Android)

1. Der Release-Keystore liegt **außerhalb** des Repos (`C:\Users\jakob\keys\einkaufstracker-release.jks`, Alias `einkaufstracker`), das Passwort im Passwortmanager. Java verlangt für Schlüsselpasswörter reines **ASCII** (keine Umlaute, kein ß, kein Eurozeichen).
2. `app/android/key.properties` nach der Vorlage `key.properties.example` anlegen. `storePassword` und `keyPassword` müssen **identisch** sein (der Schlüssel nutzt das Keystore-Passwort). Die Datei steht in `.gitignore`.
3. Bauen (im Ordner `app`): `flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.local.json`. Das erzeugt je Prozessor-Architektur eine APK (`app-arm64-v8a-release.apk`, ca. 41 MB, für moderne Handys; ohne `--split-per-abi` ca. 113 MB). Installieren mit `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
4. Signatur prüfen: `apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk`. Der Fingerabdruck muss dem des Keystores entsprechen (`keytool -list -v -keystore ... -alias einkaufstracker`, das Passwort gibst du dort selbst ein).

Öffentlicher Zertifikat-Fingerabdruck (SHA-256) der Release-Signatur:
`93:B7:B6:E4:76:FA:8B:AD:8B:D0:1D:19:B0:DE:52:43:F1:A4:0C:EC:8F:B6:AA:52:E3:B5:E0:DB:DD:70:BB:02`

Ohne `key.properties` fällt der Build auf den Debug-Schlüssel zurück, solche APKs sind nur zum lokalen Testen gedacht. Beim Wechsel zwischen Debug- und Release-Signatur muss die App auf dem Gerät vorher deinstalliert werden (die Daten liegen in der Cloud).

## Hinweis zum Branch-Schutz

GitHub bietet den Schutz für `main` (Pull Request und grüne Checks erzwingen) bei privaten Repositories nur mit einem bezahlten Tarif an. Im Free-Tarif gelten die Regeln oben deshalb **per Disziplin**. Aktiv sind dafür: nur Squash-Merge erlaubt, Branches werden nach dem Merge automatisch gelöscht.
