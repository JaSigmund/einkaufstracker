# Code-Review Einkaufstracker, 2026-10-16

Stand: `main` bei Version 1.15.0+37 (fe1e94d). Geprüft wurden die Flutter-App (`app/`, rund 26 000 Zeilen ohne
generierten Code), die Datenbank (`supabase/migrations/`, 27 Migrationen mit RLS), die sieben Edge Functions und die CI.
Alle Testsuiten wurden dafür lokal unter Linux ausgeführt (Flutter 3.47.5, Deno 2, Python 3.12 mit pgserver).

**Legende.** Schwere: **Hoch** (Datenverlust, Kosten- oder Sicherheitsrisiko), **Mittel** (falsches Verhalten,
Datenschutz), **Niedrig** (Robustheit, Komfort), **Info** (Hinweis). Status: ✅ behoben und mit Test abgesichert,
➖ bewusst so belassen (mit Begründung), ⏳ offen mit Empfehlung.

**Nachtrag 2026-10-17.** Die Funde mit Status ✅ aus der ersten Runde kamen mit
[#92](https://github.com/JaSigmund/einkaufstracker/pull/92). Die damals offenen Empfehlungen sind im Branch
`claude/studienhub-review-tests-yndgfp` umgesetzt; jeder Abschnitt nennt unter „Umgesetzt (2026-10-17)“, was sich
geändert hat. Offen bleibt nur die Content-Security-Policy für die Web-Version (S11). Hinweise zum Ausrollen der drei
neuen Migrationen stehen am Ende.

## Zusammenfassung

Das Projekt ist in einem guten Zustand: klare Schichten, offline-first mit nachvollziehbarer Konfliktregel, ein
append-only Ledger für den Bestand, RLS auf jeder Tabelle mit eigenen Schema-Tests, eine durchdachte Datenschutz-Kette
beim Bon-Scan (lokal zuerst, Zahlungsblock wird vor dem Cloud-Upload abgeschnitten) und eine sehr gute Testabdeckung der
Fachlogik. Viele frühere Review-Funde sind im Code als „Codereview-Fund“ dokumentiert und mit Tests belegt.

Die wichtigsten neuen Funde:

| # | Bereich | Fund | Schwere | Status |
|---|---|---|---|---|
| B1 | Bugs | **`main` ist rot**: ein Test hängt an der echten Uhr und schlägt seit 2026-10-05 fehl | Mittel | ✅ |
| B2 | Bugs / Sync | Holen bleibt für immer hängen, wenn > 500 Zeilen denselben `updated_at` haben | Hoch (latent) | ✅ |
| S1 | Sicherheit | `parse-receipt` prüft das KI-Tageslimit nicht und die Eingabe kaum | Hoch | ✅ |
| S2 | Sicherheit | `delete-account` löscht bei einem Lesefehler den **gemeinsamen** Haushalt aller Mitglieder | Hoch | ✅ |
| S6 | Datenschutz | Abmelden/Konto löschen lässt Bon-Fotos, Essensfotos und geplante Erinnerungen auf dem Gerät | Mittel | ✅ |
| U2 | UI | Sekundärtexte in 41 Stellen unter dem WCAG-Kontrast (4,33 : 1 statt 4,5 : 1) | Mittel | ✅ |
| U1/U3/U4 | Barrierefreiheit | IconButtons ohne Beschriftung, zu kleine Tippflächen, namenlose Long-Press-Aktionen | Mittel | ✅ |

Neu sind außerdem automatisierte Querschnittstests (Architektur, Barrierefreiheit, Layout, Sicherheits-Invarianten der
Datenbank, Repo-Hygiene) und eine erweiterte CI, siehe [Tests und CI](#tests-und-ci).

---

## 1. Bugs

### B1 ✅ `main` ist rot: Test mit fester Uhrzeit gegen echte Uhr (Mittel)
`app/test/receipt_inventory_suggestions_test.dart`, Test „bestaetigter Inventar-Eintrag wird nach erneutem Scan
automatisch wieder verknuepft“. Der Bon ist auf 2026-09-28 datiert, `InventoryRepository.findRefinableSuggestion`
verfeinert aber nur Vorschläge der letzten 7 Tage relativ zu `DateTime.now()`. Seit 2026-10-05 findet der Scan den
Vorschlag nicht mehr und legt einen zweiten Eintrag an; die letzte grüne CI war am 2026-10-04, der nächste Push auf
`main` wäre rot gewesen. **Behoben:** der Test übergibt `now:` explizit.

Empfehlung damals: Weitere solche „Zeitbomben“ sind wahrscheinlich, weil `DateTime.now()` in Repositories und Seiten
direkt aufgerufen wird. Eine injizierbare Uhr (z.B. `package:clock` mit `withClock` in Tests) macht das systematisch
testbar. Ein Versuch, die ganze Suite mit `libfaketime` um 200 Tage vorzustellen, scheitert, weil der Flutter-Testläufer
damit hängen bleibt.

**Umgesetzt (2026-10-17):** App und Tests lesen die Zeit nur noch über `appClock` (`app/lib/core/clock.dart`, auf
Basis von `package:clock`), alle 131 Aufrufe von `DateTime.now()` sind ersetzt; `architecture_test.dart` lässt keinen
neuen zu. `appClock` folgt `withClock` und in `testWidgets` der FakeAsync-Uhr, dazu einem Versatz, den
`test/flutter_test_config.dart` aus `--dart-define=TEST_CLOCK_OFFSET_DAYS=N` setzt (ein reiner Zonenwert reicht nicht:
package:test führt die Testkörper nicht in der Zone aus, in der sie deklariert wurden). Der neue CI-Job „Zeitreise“ lässt
die ganze Suite 200 und 400 Tage in der Zukunft laufen. Der erste Lauf fand drei weitere Zeitbomben:
`product_price_page_test.dart` prüft den Händlervergleich (Fenster 180 Tage) mit Bons vom August/September 2026 und wäre
ab Ende Jänner 2027 rot gewesen. `ProductPricePage` bekommt dafür wie die anderen Seiten einen Stichtag `now:`.

### B2 ✅ Sync: Holen bleibt bei Zeitstempel-Gleichstand dauerhaft stehen (Hoch, latent)
`app/lib/data/sync/sync_engine.dart`, `_pull`. Seiten werden mit `updated_at >= since`, `limit 500` geholt, danach gilt
`since = rows.last.updated_at`. Haben mehr als 500 Zeilen denselben Zeitstempel (Postgres vergibt in einer Transaktion
für alle Zeilen dasselbe `now()`, z.B. bei einer Daten-Migration oder einem SQL-Skript aus `tools/`), liefert jede Seite
wieder dieselben 500 Zeilen. `since` kommt nie weiter, die übrigen Zeilen **und alle späteren Änderungen dieser
Tabelle** werden auf diesem Gerät nie mehr geholt. Die Test-Attrappe vergab streng monotone Zeitstempel, deshalb fiel es
nicht auf. **Behoben:** stabile Sortierung `updated_at, <Primärschlüssel>` und ein Versatz für schon geholte Zeilen mit
gleichem Zeitstempel (`RemoteStore.fetchChanges(offset:, orderKeys:)`). Drei Regressionstests in `test/sync_test.dart`
(1 200 Zeilen in einer Transaktion, Folgeänderungen, Gleichstand genau an der Seitengrenze); ohne den Fix schlagen alle
drei fehl.

### B3 ✅ Abmelden/Konto löschen räumt nicht alles weg (Mittel, siehe S6)

### B4 ✅ Rückbuchung einer Mahlzeit lässt den Posten „geöffnet“ (Niedrig)
`app/lib/data/repositories/inventory_repository.dart`, `restoreForMeal` (Zeile ~615). Wird ein versiegelter Posten durch
eine Mahlzeit nur angebrochen, setzt `deductForMeal` ihn auf `opened` (mit verkürzter Haltbarkeit). Wird die Mahlzeit
gelöscht, kommt die Menge zurück, der Status bleibt aber `opened`. Ein ganz verbrauchter Posten kehrt dagegen als
`sealed` zurück: uneinheitlich, und nach einem versehentlichen Eintrag zeigt die App für eine ungeöffnete Packung eine zu
kurze Haltbarkeit. Empfehlung: beim Abzug vermerken, ob die Mahlzeit den Posten geöffnet hat (z.B. als eigene
`open`-Bewegung mit `meal_id`), und das bei der Rückbuchung zurücknehmen.

**Umgesetzt (2026-10-17):** Die `meal`-Bewegung vermerkt, wenn sie einen versiegelten Posten angebrochen hat
(`InventoryRepository.openedByMealNote`). Die Rückbuchung versiegelt ihn dann wieder, mit der ursprünglichen Haltbarkeit,
solange keine andere Mahlzeit oder Entnahme ihn verbraucht hat. Tests in `meal_repository_test.dart` (wieder versiegelt,
zweite Mahlzeit hält ihn offen, vorher schon geöffnet bleibt geöffnet).

### B5 ✅ Ledger-Bewegungen mit Gleitkomma-Resten (Niedrig)
`inventory_repository.dart:571` schreibt `delta: -a.quantity` ungerundet (z.B. `-0.30000000000000004`), während die
Bestandsmenge mit `_round3` gerundet wird und der Server `numeric(10,3)` speichert. Lokal und am Server ergeben die
Summen dann minimal unterschiedliche Werte. Empfehlung: `_round3(a.quantity)` auch für die Bewegung.

**Umgesetzt (2026-10-17)** wie empfohlen, mit Regressionstest (Bestände 0,7 + 1,0, die ohne Rundung einen Rest ergeben).

### B6 ✅ CSV-Export funktioniert in der Web-Version nicht (Niedrig–Mittel)
`app/lib/features/settings/settings_page.dart:96–118` schreibt über `dart:io` `File` in `getTemporaryDirectory()`. Beides
gibt es im Browser nicht, die PWA zeigt nur „Export nicht möglich.“. Empfehlung: `XFile.fromData(utf8.encode(csv),
mimeType: 'text/csv')` mit `fileNameOverrides` an `SharePlus` übergeben (funktioniert auf Android und im Web) oder den
Eintrag im Web ausblenden.

**Umgesetzt (2026-10-17):** `csvShareParams` teilt im Web die Datei direkt aus dem Speicher (`XFile.fromData`, der
Browser bietet sie zum Herunterladen an), auf dem Handy weiter über den Temp-Ordner (`test/csv_share_test.dart`).

### B7 ✅ Tageslimit der Bon-Erkennung erschien als „Fehler 429“
Mit S1 antwortet `parse-receipt` beim Tageslimit mit 429. `SupabaseCloudReceiptReader` bildet das jetzt über die neue,
testbare Funktion `cloudReceiptExceptionFor` auf eine verständliche Meldung ab (`test/cloud_receipt_errors_test.dart`).

### B8 ✅ Technische Fehlertexte in der Oberfläche (Niedrig)
`SyncController._friendly` (`app/lib/app/providers.dart:192`) fällt auf `e.toString()` zurück; `settings_page.dart:150`
und `:196` zeigen die rohe Ausnahme. Empfehlung: unbekannte Fehler mit einem festen Text plus „Fehler melden“ anzeigen,
das Detail nur im Fehlerbericht.

**Umgesetzt (2026-10-17):** Unbekannte Sync-Fehler zeigen „Synchronisierung fehlgeschlagen, wird erneut versucht.
Details stehen im Fehlerbericht.“, das Detail steht in `SyncStatus.errorDetail` und geht mit dem Fehlerbericht mit.
Abmelden und Konto löschen zeigen bei einem Fehlschlag die Meldung der Anmeldung statt der rohen Ausnahme.

---

## 2. Sicherheitskonzepte

Gesamteindruck: stark. RLS auf jeder Tabelle über `is_household_member` (SECURITY DEFINER mit festem `search_path`),
Views mit `security_invoker`, private Buckets mit Pfad-Prüfung, Einladungen mit 59-Bit-Code, E-Mail-Bindung,
Fehlversuchs-Sperre und `service_role`-only-Funktionen, KI-Functions mit Einwilligung und Tageslimit, keine Geheimnisse
im Repo (geprüft über alle versionierten Dateien und die verfügbare Historie).

### S1 ✅ `parse-receipt` ohne Tageslimit und mit schwacher Eingabeprüfung (Hoch)
Die drei anderen KI-Functions zählen vor dem Modellaufruf die Aufrufe der letzten 24 Stunden (Limit 40), die
Bon-Erkennung nicht, obwohl sie mit bis zu vier Bildern je Aufruf und einer Nachfrage (v3) die teuerste ist. Ein direkter
API-Aufruf mit gültigem JWT und erteilter Einwilligung konnte beliebig viele Kosten erzeugen. Dazu: Bilder wurden nicht
auf Typ geprüft (`img.length` von Nicht-Texten), Händler-Hinweis und Kategorien ohne Längengrenze in den Prompt.
**Behoben:** neues Modul `supabase/functions/parse-receipt/validate.ts` (Typen, Längen, nur JPEG in Base64, Variante,
Bon-ID als UUID) mit 9 Deno-Tests; Tageslimit wie in den anderen Functions.

### S2 ✅ Unbekannte `receipt_id` hebelt die Kostenprotokollierung aus (Mittel)
`llm_usage.receipt_id` ist ein Fremdschlüssel. Eine erfundene Bon-ID ließ das Insert scheitern, der Fehler wurde
ignoriert: der Aufruf zählte dann nicht zum Tageslimit. **Behoben:** Insert-Fehler werden geprüft, bei einer unbekannten
Bon-ID wird ohne Verweis protokolliert.

### S3 ✅ `delete-account` kann den gemeinsamen Haushalt löschen (Hoch)
`supabase/functions/delete-account/index.ts`: Die Mitgliederzahl wurde ohne Fehlerprüfung gelesen (`count ?? 0`).
Schlug die Zählung fehl, galt der Nutzer als einziges Mitglied, und der **ganze Haushalt** samt Daten aller anderen
Mitglieder wurde per Cascade gelöscht. Fehler beim Löschen des Haushalts bzw. beim Austritt wurden ebenfalls ignoriert,
danach wurde trotzdem das Auth-Konto gelöscht (verwaiste Daten, kein zweiter Versuch möglich). **Behoben:** neues Modul
`plan.ts` (`planDeletion`, 4 Deno-Tests): eine unbekannte oder unplausible Mitgliederzahl bricht ab, bevor etwas gelöscht
ist; jeder Löschschritt wird geprüft, das Konto wird nur nach erfolgreichem Aufräumen gelöscht.

### S4 ✅ `suggest-recipes`: Menge ungeprüft im Prompt, `null` führt zu 500 (Niedrig–Mittel)
Name und Einheit waren seit dem Review vom 2026-10-01 begrenzt, die Menge nicht (`${i.quantity}` landet im Prompt).
**Behoben:** `suggest-recipes/validate.ts` mit 6 Tests.

### S5 ✅ `cooking-chat`: Nicht-Listen führen zu TypeError/500, `from_user` ungeprüft (Niedrig)
**Behoben:** `cooking-chat/validate.ts` mit 6 Tests; Kappung von Verlauf und Zutaten bleibt serverseitig.

### S6 ✅ Lokale Kontodaten bleiben nach dem Abmelden auf dem Gerät (Mittel, Datenschutz)
`settings_page.dart` leerte beim Abmelden und nach „Konto löschen“ nur die Datenbank. Liegen blieben:
* lokale Kopien der Originalbelege (`receipt_files/`, Fotos u.U. mit Kartenendziffern) und Essensfotos (`meal_photos/`),
* die geplanten Ablauf-Erinnerungen: nach dem Abmelden kam noch eine Benachrichtigung mit den Produktnamen des alten
  Kontos (`rescheduleExpiryReminders` bricht ohne Haushalt ab, ohne zu stornieren).

Gerade „Konto löschen“ verspricht, alle Daten zu entfernen. **Behoben:** `clearLocalAccountData` in `providers.dart`
(Datenbank, beide Dateiordner, `NotificationScheduler.cancelExpiryReminders`), Tests in `settings_page_test.dart`,
`receipt_file_service_test.dart`, `meal_photo_service_test.dart`.

### S7 ✅ Fremdschlüssel prüfen den Haushalt nicht (Niedrig)
Beispiele: `inventory_items.product_id` (`0001_init.sql:206`, `on delete restrict`), `receipt_items.receipt_id` (:179),
`shopping_list_items.list_id` (:250). RLS prüft nur das `household_id` der eigenen Zeile. Ein Mitglied von Haushalt A, das
eine UUID aus Haushalt B kennt, kann eine eigene Zeile auf B's Objekt zeigen lassen und damit z.B. das Löschen eines
Produkts in B blockieren. Lesen ist nicht möglich, und UUIDs sind nicht erratbar, daher niedrig. Empfehlung: zusammen-
gesetzte Fremdschlüssel `(household_id, id)` oder ein Trigger, der denselben Haushalt verlangt (als neue Migration).

**Umgesetzt (2026-10-17):** Migration `0028_same_household_references.sql`. Der Trigger `ensure_same_household` prüft
alle 27 Fremdschlüssel zwischen Haushaltstabellen (Fehlercode 23503, die App stuft ihn als Datenfehler ein und blockiert
die Outbox nicht). Bestehende Zeilen werden nicht nachgeprüft. Eine neue Invariante im Schema-Test lässt jeden künftigen
Fremdschlüssel ohne diesen Trigger scheitern.

### S8 ✅ Einladungen: Clients setzen Ablauf, Fehlversuche und Code selbst (Niedrig)
`household_invites_insert` (`0017_household_invites.sql:60`) prüft nur Mitgliedschaft und `invited_by`. Ein Mitglied
kann `expires_at` in die ferne Zukunft, `failed_attempts` negativ (hebelt die Sperre nach 5 Versuchen aus) oder einen
schwachen `token` setzen. Da es nur den eigenen Haushalt betrifft, niedrig; Empfehlung: Trigger, der beim Insert
`failed_attempts = 0`, `accepted_at is null`, `expires_at <= now() + 7 days` erzwingt und `token` immer selbst erzeugt.

**Umgesetzt (2026-10-17):** Migration `0029_invite_insert_defaults.sql`: beim Anlegen setzt der Server Code, Ablauf
(7 Tage), Fehlversuche (0), Annahme (leer) und Zeitpunkt selbst. Die App schickt diese Felder nie mit.

### S9 ✅ Tageslimit nicht atomar (Niedrig)
Zählen und Aufruf sind getrennt, parallele Anfragen können das Limit um die Zahl der gleichzeitigen Aufrufe
überschreiten. Empfehlung: eine RPC, die atomar reserviert (Insert einer Platzhalterzeile und Zählen in einer
Transaktion), danach die Kosten nachtragen.

**Umgesetzt (2026-10-17):** Migration `0030_llm_call_reservation.sql` mit `reserve_llm_call` (zählt und legt die Zeile in
einer Transaktion an, je Haushalt per Advisory-Sperre serialisiert, nur für `service_role`). Die Functions tragen danach
Tokens und Kosten ein oder geben die Reservierung frei, wenn der Modellaufruf scheitert. Der Schema-Test prüft das mit
parallelen Verbindungen.

### S10 ✅ Android-Backup enthält Datenbank und Sitzung (Niedrig–Mittel)
`app/android/app/src/main/AndroidManifest.xml:9`: kein `android:allowBackup`/`dataExtractionRules`, damit gilt
`allowBackup=true`. Die lokale Datenbank (alle Haushaltsdaten) und die Supabase-Sitzung landen in der Cloud-Sicherung
bzw. beim Geräteumzug. Empfehlung: `android:allowBackup="false"` (die Daten liegen ohnehin in der Cloud) oder
Ausschlussregeln für `databases/` und `shared_prefs/`.

**Umgesetzt (2026-10-17):** `allowBackup="false"`, `fullBackupContent="false"` (bis Android 11) und
`dataExtractionRules` ohne jede Domain (Android 12+). Neuer CI-Job „Android-Build (Debug-APK)“, damit Manifest und
Ressourcen nicht erst beim lokalen Release-Build auffallen.

### S11 Kleinere Punkte (Info/Niedrig)
* ✅ Release-Build fällt ohne `key.properties` still auf den Debug-Schlüssel zurück (`build.gradle.kts:54`). Empfehlung:
  bei `assembleRelease` ohne Schlüssel abbrechen. **Umgesetzt (2026-10-17)** als deutliche Warnung statt Abbruch: lokale
  Release-Builds zum Testen bleiben so möglich, ein versehentlich debug-signiertes Release fällt aber auf.
* ✅ `supabase/config.toml`: lokal `enable_signup = true` (:175) und `minimum_password_length = 6` (:181), während die App
  und `accept-invite` 10 Zeichen verlangen. Für das Live-Projekt im Dashboard prüfen (laut README ist Registrierung aus).
  `refresh-online-prices` fehlt in `config.toml` mit `verify_jwt = false`: ein Deploy ohne `--no-verify-jwt` legt den
  Cron-Abruf still. **Umgesetzt (2026-10-17):** Registrierung aus, Mindestlänge 10, `refresh-online-prices` mit
  `verify_jwt = false`. Die Einstellungen des Live-Projekts im Dashboard bitte trotzdem einmal vergleichen.
* ➖ `refresh-online-prices` ist ohne Anmeldung aufrufbar. Nach einem fehlgeschlagenen Lauf startet jeder Aufruf (höchstens
  alle 20 Minuten) die Verarbeitung des 216-MB-Feeds neu. Empfehlung: ein gemeinsames Geheimnis im Header des Cron-Jobs.
  **Bewusst so belassen (Entscheidung 2026-10-17):** Schlimmstenfalls kostet es Rechenzeit der Function, Daten lassen
  sich darüber weder lesen noch ändern; ein Geheimnis müsste zusätzlich im Cron-Job gepflegt werden. Die Begründung steht
  als Kommentar in `config.toml`.
* Nutzereingaben (Händler-Hinweis, Rezepttitel, Produktnamen) stehen in Prompts; Auswirkung beschränkt sich auf den
  eigenen Haushalt, die System-Prompts weisen Anweisungen im Bild/Text bereits zurück.
* ⏳ Web: keine Content-Security-Policy in `app/web/index.html`. Noch offen: eine CSP muss mindestens CanvasKit
  (`wasm-unsafe-eval`, Schriften und Engine vom Google-CDN, sofern nicht mit `--no-web-resources-cdn` gebaut), Supabase
  (`connect-src https://*.supabase.co wss://*.supabase.co`), Open Food Facts und die Rezeptseiten im Koch-Modus zulassen.
  Das sollte gegen die ausgerollte PWA geprüft werden (erst als `Content-Security-Policy-Report-Only`), sonst bleibt die
  Seite weiß.
* Mitglieder können Status/Schweregrad ihrer Fehlerberichte selbst setzen (bewusst so, siehe `0011`).

---

## 3. Architekturstruktur

Schichten `domain/` (reine Logik), `data/` (Drift, Supabase, Dateien), `features/` (Seiten), `app/` (Provider, Router)
sind klar und werden weitgehend eingehalten; `features/` spricht nie direkt mit Supabase. Neu sichert
`app/test/architecture_test.dart` das ab („Sperrklinke“: bestehende Ausnahmen stehen mit Grund im Test, jede neue
Verletzung schlägt fehl, eine behobene muss aus der Liste). Seit dem 2026-10-17 sind die Ausnahmelisten leer.

### A1 ✅ Bestehende Schichtverletzungen (Niedrig)
* `data/` → `features/`: `CookingChatContext`/`ChatMessage` liegen in `features/recipes/cooking_chat_panel.dart`,
  `ReceiptScanner`/`ScannedPage` in `features/receipt_import/photo_receipt_service.dart`, benutzt von `data/cloud/*` und
  `data/ocr/mlkit_receipt_scanner.dart`. Empfehlung: Typen nach `domain/recipes/` bzw. `data/ocr/` verschieben.
* `domain/` → `data/local/database.dart` (drift-Zeilenklassen) in `csv_export`, `expiry_reminders`, `data_snapshot`.
* Kreis `core/format.dart` → `domain/…` → `core/format.dart`.

**Umgesetzt (2026-10-17):** Kochchat-Typen nach `domain/recipes/cooking_chat.dart`, Scanner-Schnittstelle nach
`data/ocr/receipt_scanner.dart`; CSV-Export und Datensnapshot nach `data/`, die Erinnerungsplanung arbeitet auf einem
eigenen Record statt auf der Drift-Zeile; `vienna_time` nach `core/`, domain-abhängige Formatierer nach
`features/common/domain_format.dart`.

### A2 ✅ `providers.dart` als Sammelstelle (Niedrig)
802 Zeilen, die Haushalts-ID-Closure steht 12-mal wortgleich darin. Empfehlung: Hilfsfunktion
`Future<String> requireHouseholdId(Ref ref)` und Aufteilung der Provider je Feature (`features/*/providers.dart`).

**Umgesetzt (2026-10-17):** `requireHouseholdId(ref)` ersetzt die zwölf Closures. Die Aufteilung je Feature ist
zurückgestellt: sie verschiebt viel Code, ohne Verhalten zu ändern, und lässt sich am besten zusammen mit dem nächsten
größeren Umbau eines Features erledigen.

### A3 ✅ `HomeShell` (Niedrig)
`features/home/home_shell.dart:105–140`: verschachtelte Ternär-Kette mit einem unerreichbaren „Noch nicht gebaut“-Zweig
samt veralteter Phasen-Hinweise; beim Tab-Wechsel geht der Zustand der Seite verloren (kein `IndexedStack`), und der Tab
steht nicht in der URL (kein Deep-Link, Zurück-Taste im Web verlässt die App). Empfehlung: `StatefulShellRoute` von
go_router.

**Umgesetzt (2026-10-17):** `StatefulShellRoute` mit einem Navigator je Tab: Eingaben, Filter und Scrollstand bleiben
beim Wechsel erhalten, jeder Tab hat eine URL (`/`, `/inventory`, `/list`, `/report`, `/diary`). In verdeckten Tabs
sind Heroes abgeschaltet (sonst Konflikt der FABs von Inventar und Tagebuch). Nach dem Speichern eines Barcode-Scans geht
es jetzt ins Inventar statt auf die Übersicht. Tests: `test/home_shell_test.dart`.

### A4 ✅ Doppelter Code in den Edge Functions (Niedrig)
Preistabelle, `json`-Helfer, Tageslimit und Anthropic-Aufruf stehen fünfmal da (das Tageslimit fehlte deshalb in einer,
siehe S1). Empfehlung: `supabase/functions/_shared/` (Supabase-Konvention); der CI-Schleife dann Ordner mit `_` am Anfang
überspringen lassen.

**Umgesetzt (2026-10-17):** `supabase/functions/_shared/` (`http.ts`, `llm.ts` mit Preistabelle, Tageslimit,
Protokollierung und Anthropic-Aufruf, dazu `llm_test.ts`). Der CI-Job kopiert den ganzen Ordner und prüft nur Ordner mit
`index.ts` als Function.

### A5 ✅ Outbox: dauerhaft scheiternde Einträge (Niedrig)
`remote_store.dart:65` stuft alle `PGRST…`- und `42…`-Codes als Datenfehler ein, auch abgelaufene JWTs (`PGRST301`) und
RLS-Verletzungen (`42501`). Solche Einträge bleiben mit `lastError` in der Outbox und werden bei jedem Sync wiederholt;
sichtbar ist nur die Zahl „wartend“. Empfehlung: JWT-Fehler wie Auth-Fehler behandeln (Sync abbrechen, Sitzung
erneuern), dauerhafte Datenfehler nach N Versuchen in der Oberfläche anzeigen bzw. im Fehlerbericht mitsenden.

**Umgesetzt (2026-10-17):** `isRemoteDataError` (mit Tests): `PGRST3xx` (JWT) sowie HTTP 401, 403, 408 und 429 brechen
den Sync ab, statt Einträge als fehlerhaft zu markieren. Dabei fiel auf, dass auch 429 auf das Muster `^42` passte;
SQLSTATE-Codes werden jetzt exakt erkannt. Nach drei Ablehnungen zeigt der Sync-Banner die Einträge als vom Server
abgelehnt, mit Hinweis auf „Fehler melden“. `42501` (RLS) bleibt ein Datenfehler: ein erneuter Versuch ändert daran
nichts.

### A6 ✅ Sync: `updated_at` ist der Beginn der Transaktion, nicht ihr Ende (Niedrig)
Der Trigger setzt `updated_at = now()`, also den Startzeitpunkt der Transaktion. Schreibt Gerät A eine Zeile, deren
Transaktion um 12:00:00,000 beginnt und erst um 12:00:00,050 sichtbar wird, und holt Gerät B dazwischen Zeilen bis
12:00:00,020, dann steht B's `since` schon hinter A's Zeile: B holt sie erst bei der nächsten Änderung. Das Fenster ist
bei den kurzen Upserts der App sehr klein, aber vorhanden. Empfehlung: zu Beginn jedes Syncs einige Sekunden Überlappung
(`since - 10 s`), die mit der jetzt stabilen Sortierung und dem idempotenten Anwenden nichts kostet außer ein paar
doppelt geholten Zeilen. (`clock_timestamp()` oder eine Sequenz lösen es nicht, auch sie werden vor dem Commit vergeben.)

**Umgesetzt (2026-10-17)** wie empfohlen (`pullOverlap`, 10 s), mit Test für eine spät sichtbar gewordene Zeile.

---

## 4. Teilkonzepte

| Konzept | Bewertung |
|---|---|
| Offline-first-Sync (Outbox, Last-write-wins mit sichtbarem Konflikt, ADR-018) | Gut durchdacht, Prüfung und Anwenden in einer Transaktion. B2 (Paginierung), A5 und A6 behoben. |
| Bestands-Ledger (append-only, Gegenbuchung statt Löschen, FEFO) | Sauber und gut getestet. Die Randfälle B4/B5 sind behoben. |
| Bon-Import (PDF-Text, lokale OCR, Cloud nur mit Einwilligung und ohne Zahlungsblock) | Sehr gutes Datenschutzkonzept (auch im Web mit manuellem Schnitt). |
| KI-Functions (Einwilligung, Tageslimit, Tool-Schema, Bereinigung der Antwort) | Gut; S1 behebt die Lücke bei der Bon-Erkennung, gemeinsames Modul (A4) und atomares Limit (S9) umgesetzt. |
| Haushalt und Einladungen (Selbstbedienung über `accept-invite`) | Stark (Code-Entropie, E-Mail-Bindung, Sperre, nur `service_role`); S8 als Härtung umgesetzt. |
| Konto löschen | Mit S3 und S6 jetzt vollständig und fehlertolerant. |
| Ablauf-Erinnerungen (lokal, ADR-007) | Funktional; jetzt beim Abmelden storniert. Kein Neustart-Receiver (bewusst). |
| Online-Preise (signierte Abschnitte, Plausibilitätsprüfung vor dem Löschen) | Gut; Auslöser ohne Schutz bewusst belassen (S11). |
| Mindestversion (`app_config`, fail-open) | Gut, passt zum Offline-Ansatz. |

---

## 5. UI und Layout

Material 3 mit Seed-Farbe und Dark Mode, durchgängige Leer- und Fehlerzustände, Schlüssel (`Key`) an allen wichtigen
Elementen. Neue automatisierte Prüfungen: `test/ui_accessibility_test.dart` und `test/ui_layout_test.dart` für
Anmeldung, Einladung, Einstellungen, Inventar und Einkaufsliste, seit dem 2026-10-17 auch für die Hauptnavigation
(Übersicht und Tagebuch) und zusätzlich auf einem Handy quer (800 × 360, auch bei 200 % Schrift). Liste in
`test/support/ui_pages.dart`, neue Seiten dort ergänzen.

### U1 ✅ IconButtons ohne Beschriftung (Mittel)
9 Stück (Senden im Koch-Chat, Menge +/- und Datum entfernen im Inventar, Zeitraum vor/zurück bei den Nährstoffen, Anzahl
+/- und Hinzufügen in der Einkaufsliste). TalkBack las nur „Schaltfläche“. **Behoben**, und `architecture_test.dart`
verlangt jetzt für jeden `IconButton` einen `tooltip`.

### U2 ✅ Zu geringer Kontrast der Sekundärtexte (Mittel)
41 Texte nutzten `colorScheme.outline` als Textfarbe. Diese Farbe ist in Material 3 für Rahmen gedacht und erreicht nur
4,33 : 1 (WCAG AA verlangt 4,5 : 1 für normalen Text). **Behoben:** `colorScheme.onSurfaceVariant`; Icons, Rahmen und
der Fortschrittsbalken behalten `outline` (dort genügen 3 : 1).

### U3 ✅ Listen-Chips der Einkaufsliste nur 36 dp hoch (Niedrig–Mittel)
Die feste Zeilenhöhe von 52 dp mit 8 dp Rand stauchte die Chips unter das Android-Minimum von 48 dp. **Behoben** (56 dp,
4 dp Rand).

### U4 ✅ Namenlose Long-Press-Aktionen (Mittel)
Liste bearbeiten (Long-Press auf einen Listen-Chip) und Eintrag verschieben (Long-Press auf einen Eintrag) waren für
Screenreader eine Aktion ohne Namen; Löschen per Wischen war gar nicht benannt. **Behoben:** benannte Aktionen „Liste
bearbeiten“, „In andere Liste verschieben“, „Löschen“.

### U5 ✅ Layout auf großen Bildschirmen (Niedrig)
Kein Überlauf bis 320 × 568 bei 200 % Schrift und auf dem Tablet (jetzt getestet). Auf Tablet/Desktop-Web läuft der
Inhalt aber über die volle Breite, die Navigation bleibt unten. Empfehlung: `NavigationRail` ab 600 dp und eine maximale
Inhaltsbreite (wie bei Anmeldung und Einladung schon umgesetzt, 420 dp).

**Umgesetzt (2026-10-17):** ab 600 dp `NavigationRail` mit allen Beschriftungen und dem Scan-Knopf oben (scrollt, wenn
die Höhe nicht reicht, z.B. Handy quer), Inhalt höchstens 840 dp breit und mittig.

### U6 ✅ Leeres Tagebuch läuft bei großer Schrift über (Niedrig)
Gefunden 2026-10-17 durch die um die Hauptnavigation erweiterten Layouttests: der Hinweis „Noch keine Mahlzeit“ passte
auf 320 × 568 bei 200 % Schrift nicht in die Höhe (Überlauf 112 px). **Behoben:** der Hinweis scrollt.

---

## 6. Benutzerfreundlichkeit

### X1 ✅ Navigation mit sechs Zielen, nur das aktive beschriftet (Mittel)
`home_shell.dart:150`. Material empfiehlt 3 bis 5 Ziele; ohne Beschriftung sind die Icons schwer zu unterscheiden. Die
Aktion „Rezeptvorschläge“ im Inventar nutzt dasselbe Icon wie der Tab „Tagebuch“ (`restaurant_menu`, :57 und :73).
Empfehlung: „Scan“ als Floating Action Button statt als Tab, alle Beschriftungen zeigen, eigenes Icon für die
Rezeptvorschläge.

**Umgesetzt (2026-10-17):** fünf immer beschriftete Tabs; „Scannen“ ist eine eigene Seite (`/scan`), erreichbar über den
Knopf in der Kopfzeile jedes Tabs, als FAB auf der Übersicht (Inventar und Tagebuch haben schon ihren eigenen FAB) und
oben in der Seitenleiste. Die Rezeptvorschläge haben ein eigenes Icon (`soup_kitchen`).

### X2 ✅ Löschen per Wischen ohne Rückgängig (Mittel)
`shopping_list_page.dart:531` löscht sofort. Empfehlung: SnackBar mit „Rückgängig“ (Soft-Delete zurücknehmen).

**Umgesetzt (2026-10-17)** wie empfohlen, auch für die Screenreader-Aktion „Löschen“ (`ShoppingListRepository.restore`).

### X3 ✅ Abmelde-Dialog stellt eine Frage, die er nicht anbietet (Niedrig)
`settings_page.dart:132`: „… gehen beim Abmelden verloren. Erst mit dem Netz verbinden und synchronisieren?“, die Knöpfe
sind aber nur „Abbrechen“ und „Abmelden“. Empfehlung: „Jetzt synchronisieren“ anbieten und „Trotzdem abmelden“ in der
Fehlerfarbe.

**Umgesetzt (2026-10-17)** wie empfohlen; nach „Jetzt synchronisieren“ meldet die App, ob alles übertragen ist oder wie
viele Änderungen noch offen sind. Abgemeldet wird danach nur auf Wunsch.

### X4 ✅ Versteckte Gesten (Niedrig)
Listen bearbeiten und Einträge verschieben gehen nur per Long-Press (für Screenreader jetzt benannt, für Sehende aber
nicht auffindbar). Empfehlung: sichtbares Menü (⋮) bzw. Hinweis beim ersten Mal.

**Umgesetzt (2026-10-17):** Knopf „Liste bearbeiten“ neben den Listen-Chips für die gewählte Liste und ein Hinweis auf
Wischen und langes Drücken, bis er einmal weggeklickt wird (auf dem Gerät gemerkt).

### X5 ✅ Kleinigkeiten
* Anmeldung ohne `AutofillGroup`: Passwortmanager bieten das Speichern nicht zuverlässig an. **Umgesetzt (2026-10-17)**
  bei Anmeldung und Einladung; gespeichert wird erst nach Erfolg (`TextInput.finishAutofillContext`).
* Einstellungen brauchen Netz („Für dieses Fenster wird Netz gebraucht“), obwohl die App sonst offline arbeitet.
  Empfehlung: zuletzt geladene Werte zwischenspeichern (wie bei „Originalbelege speichern“ schon gemacht).
  **Umgesetzt (2026-10-17):** ohne Netz gelten die zuletzt geladenen Werte, mit Hinweis; Ändern geht erst wieder mit Netz.
* Technische Fehlertexte (B8, umgesetzt).

---

## Tests und CI

### Neue und geänderte Tests

| Bereich | Datei | Prüft |
|---|---|---|
| Architektur | `app/test/architecture_test.dart` | Schichtregeln mit Sperrklinke, keine Schlüssel/Tokens/`http://`/`print` im App-Code, Projekt-URL nur aus `--dart-define`, `tooltip` an jedem `IconButton` |
| Barrierefreiheit | `app/test/ui_accessibility_test.dart` | `labeledTapTargetGuideline`, `androidTapTargetGuideline` (48 dp), `textContrastGuideline` (WCAG AA) für die Hauptseiten |
| Layout | `app/test/ui_layout_test.dart` | kein Überlauf: 320 × 568 (100/130/200 % Schrift), 412 × 915 bei 200 %, Tablet 1280 × 800; mit echter Roboto statt Testschrift |
| Sync | `app/test/sync_test.dart` | B2: Gleichstand von 1 200 Zeilen, Folgeänderungen, Seitengrenze |
| Abmelden | `app/test/settings_page_test.dart`, `receipt_file_service_test.dart`, `meal_photo_service_test.dart` | S6: Erinnerungen storniert, lokale Belege und Fotos gelöscht |
| Cloud-Fehler | `app/test/cloud_receipt_errors_test.dart` | B7: Abbildung der `parse-receipt`-Antworten |
| Edge Functions | `parse-receipt/validate_test.ts`, `suggest-recipes/validate_test.ts`, `cooking-chat/validate_test.ts`, `delete-account/plan_test.ts` | S1, S3, S4, S5 |
| Datenbank | `supabase/tests/run_schema_tests.py`, Abschnitt „Sicherheits-Invarianten“ | für **alle** Tabellen/Funktionen/Views: RLS an, Mitgliedschafts-Policy auch beim Schreiben, `search_path` bei SECURITY DEFINER, Einladungsfunktionen nur für `service_role`, `security_invoker`, private Buckets, Storage nur für Angemeldete, nichts für `anon` sichtbar |
| Repo-Hygiene | `tools/check_repo_hygiene.py` + `tools/test_check_repo_hygiene.py` | verbotene Dateien (Keystores, `key.properties`, `.env`, `dart_defines.local.json`, Bon-Fotos, Backups) und Geheimnisse (Anthropic-/Supabase-Keys, JWTs, private Schlüssel, Tokens) |
| Abdeckung | `tools/check_coverage.py` + `tools/test_check_coverage.py` | Zeilenabdeckung je Schicht, Untergrenze als Sperrklinke |

Gegenproben: Die Sync-Tests schlagen ohne den Fix fehl, die Tooltip-Regel meldet einen entfernten Tooltip, und eine
absichtlich unsichere Probe-Migration (Tabelle ohne RLS, SECURITY DEFINER ohne `search_path`, View ohne
`security_invoker`) lässt vier Invarianten fehlschlagen.

Dazu kamen am 2026-10-17:

| Bereich | Datei | Prüft |
|---|---|---|
| Inventar | `app/test/meal_repository_test.dart` | B4: Rückbuchung versiegelt wieder (auch die Gegenfälle), B5: gerundete Bewegungen |
| Einstellungen | `app/test/csv_share_test.dart`, `settings_page_test.dart`, `sync_controller_test.dart` | B6, X3 („Jetzt synchronisieren“), X5 (Einstellungen offline), B8 (fester Text, Detail im Fehlerbericht) |
| Sync | `app/test/remote_store_test.dart`, `sync_test.dart`, `sync_status_banner_test.dart` | A5: Einstufung der Fehlercodes, Ablehnung nach drei Versuchen, Anzeige; A6: spät sichtbare Zeile |
| Datenbank | `supabase/tests/run_schema_tests.py` | S7: Verweis in fremden Haushalt abgelehnt, **jeder** Fremdschlüssel zwischen Haushaltstabellen hat den Trigger; S8: Server setzt die Einladungsfelder; S9: `reserve_llm_call` mit parallelen Verbindungen |
| Edge Functions | `supabase/functions/_shared/llm_test.ts` | A4/S9: Kosten, Modell-Prüfung, Reservierung, Protokollierung, Freigabe |
| Navigation | `app/test/home_shell_test.dart` | A3/X1/U5: fünf beschriftete Tabs, URLs und Deep-Links, Zustand beim Tabwechsel, Scannen von jedem Tab, Seitenleiste und Inhaltsbreite auf dem Tablet, Barrierefreiheit auch dort, kein Hero-Konflikt |
| Einkaufsliste | `app/test/shopping_lists_test.dart` | X2: Rückgängig, X4: Knopf „Liste bearbeiten“ und Gesten-Hinweis |
| Anmeldung | `app/test/login_page_test.dart`, `accept_invite_page_test.dart` | X5: Autofill-Gruppe, Speichern erst nach Erfolg |
| Architektur | `app/test/architecture_test.dart` | keine Ausnahmen mehr bei den Schichten (A1), keine Zeit an `appClock` vorbei (B1) |
| Zeitreise | `app/test/flutter_test_config.dart` | B1: ganze Suite mit verstellter Uhr (`--dart-define=TEST_CLOCK_OFFSET_DAYS=N`) |

Gegenproben auch hier: ohne die jeweilige Korrektur schlagen die Tests für B4, B5, A6, S7 (Invariante) und den
Hero-Konflikt der Navigation fehl.

### CI (`.github/workflows/ci.yml`)

| Job | Neu |
|---|---|
| App (analyze und test) | `flutter test --coverage`, Abdeckungs-Untergrenze, `lcov.info` als Artefakt, Tabelle in der Job-Zusammenfassung |
| Web-Build (PWA) | neu: `flutter build web --release`, damit Web-Inkompatibilitäten vor dem Deploy auffallen |
| Datenbank | enthält jetzt die Sicherheits-Invarianten |
| Edge Function | zusätzlich `deno lint`; die neuen `*_test.ts` laufen automatisch mit |
| Repo-Hygiene und Werkzeuge | neu: Geheimnis-/Dateiprüfung und Tests der Python-Werkzeuge (inkl. des bisher nicht ausgeführten `test_import_bls_foods.py`) |
| App-Tests in der Zukunft (+200 / +400 Tage) | neu am 2026-10-17 (B1): dieselbe Suite mit verstellter Uhr |
| Android-Build (Debug-APK) | neu am 2026-10-17 (S10): Manifest, Ressourcen und Gradle-Skript |
| Edge Function | seit dem 2026-10-17 mit dem gemeinsamen Modul `_shared` (A4): der ganze Ordner wird kopiert, geprüft werden Ordner mit `index.ts` |

Außerdem: `permissions: contents: read` für den ganzen Workflow und `timeout-minutes` je Job.

### Lokal ausführen

```bash
cd app && flutter analyze && flutter test --coverage && python ../tools/check_coverage.py coverage/lcov.info --min 86 --min-domain 97
python supabase/tests/run_schema_tests.py
python tools/check_repo_hygiene.py
python tools/test_check_repo_hygiene.py && python tools/test_check_coverage.py
# Edge Functions: wie im CI-Job "function" je Function in einen leeren Ordner kopieren (das package.json im Repo stoert
# Deno), dort `deno check index.ts`, `deno test` und zum Schluss `deno lint` ueber alle
```

### Ergebnis der Läufe für diesen Branch

Lokal unter Linux mit denselben Versionen wie die CI (Flutter 3.47.5, Deno 2, Python 3.12):

| Suite | vorher (`main`) | jetzt |
|---|---|---|
| `flutter analyze` | keine Funde | keine Funde |
| `flutter test` | 1 767 bestanden, **1 fehlgeschlagen** (B1) | **1 818 bestanden** |
| Testabdeckung App (Zeilen, ohne generierten Code) | – | 88,0 % gesamt, `domain` 98,7 %, `features` 93,6 %, `data` 74,5 %, `app` 62,5 % |
| Schema- und RLS-Tests | 304 bestanden | **314 bestanden** |
| Deno (`deno check` aller 7 Functions, `deno test`) | 70 bestanden | **95 bestanden** |
| `deno lint` | 3 Funde (`any`, `prefer-const`) | keine Funde |
| Werkzeuge (`tools/test_*.py`) | – (nicht in der CI) | 57 bestanden |
| Repo-Hygiene | – | 561 Dateien, 0 Funde |
| `flutter build web --release` | – (nicht in der CI) | erfolgreich |

Stand 2026-10-17, nach der Umsetzung der offenen Empfehlungen (gleiche Umgebung):

| Suite | Ergebnis |
|---|---|
| `flutter analyze` | keine Funde |
| `flutter test` | **1 881 bestanden** |
| Zeitreise (`--dart-define=TEST_CLOCK_OFFSET_DAYS=…`) | +60, +200, +400 und +1 200 Tage: je 1 881 bestanden (vor dem Fix in `product_price_page_test.dart` bei +200: 3 fehlgeschlagen) |
| Testabdeckung App | 88,6 % gesamt, `domain` 98,7 %, `features` 94,1 %, `data` 75,3 %, `app` 69,0 %, `core` 100 % |
| Schema- und RLS-Tests | **332 bestanden** |
| Deno (`deno check` aller 7 Functions, `deno test`) | **103 bestanden** |
| `deno lint` | keine Funde |
| Werkzeuge (`tools/test_*.py`) | 57 bestanden |
| Repo-Hygiene | 593 Dateien, 0 Funde |
| `flutter build web --release` | erfolgreich |
| Android-Build | lokal nicht möglich (kein Android-SDK in der Umgebung), läuft im neuen CI-Job |

Hinweis zur Abdeckung: `flutter test --coverage` erfasst nur Dateien, die mindestens ein Test lädt; reine
Plattform-Adapter ohne Test (z.B. ML-Kit, Benachrichtigungs-Plugin) fehlen in der Rechnung ganz.

### Hinweise zum Ausrollen

Für den Stand vom 2026-10-17 (in dieser Reihenfolge):

1. **Migrationen 0028 bis 0030 einspielen** (`npx supabase db push --dry-run`, dann `npx supabase db push`). Sie ändern
   keine bestehenden Daten. 0028 prüft nur neue und geänderte Verweise, 0029 betrifft nur neue Einladungen.
2. **Danach alle Edge Functions deployen**: alle sieben nutzen jetzt `_shared`, und die KI-Functions rufen
   `reserve_llm_call` aus 0030 auf. In umgekehrter Reihenfolge scheitern die KI-Aufrufe, bis die Migration da ist.
   `refresh-online-prices` hat jetzt `verify_jwt = false` in `config.toml`, `--no-verify-jwt` ist nicht mehr nötig.
3. **Neue App-Version** für Navigation, Rückgängig, Autofill, Einstellungen offline, Sync-Fehlerbehandlung und die
   Android-Backup-Regeln. Ältere Apps funktionieren mit dem neuen Server weiter; sie zeigen abgelehnte Änderungen nur
   nicht an. Keine Änderung am lokalen Drift-Schema.
4. Den Android-Build prüft die CI nur bei Pull Requests und auf `main`, er läuft also erst mit dem Pull Request.

Für den Stand vom 2026-10-16:

* Die geänderten Edge Functions (`parse-receipt`, `suggest-recipes`, `cooking-chat`, `delete-account`) sind rückwärts-
  kompatibel zu installierten App-Versionen und müssen per `supabase functions deploy` eingespielt werden. Ältere Apps
  zeigen beim neuen Tageslimit der Bon-Erkennung „Fehler 429“ statt des neuen Textes.
* Keine neue Migration, keine Änderung am lokalen Drift-Schema.
* Das Tageslimit gilt jetzt auch für die Bon-Erkennung (v3 kann bis zu zwei Aufrufe je Bon zählen). Wer viele Bons am
  Stück nachträgt, erreicht die 40 schneller; der Wert steht in jeder Function als `DAILY_CALL_LIMIT`.
