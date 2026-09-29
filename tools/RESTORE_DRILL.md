# Backup-Wiederherstellung testen (Phase 5, Doku 09 Sicherheit §6/§7)

Prüft, dass ein `tools/backup.sh`-Dump sich tatsächlich wiederherstellen lässt — nicht nur, dass
die Datei existiert. **Bewusst ein manueller Vorgang, nicht automatisiert**: er legt vorübergehend
eine zweite Datenbank an, und das soll nie versehentlich gegen das Produktivprojekt laufen.

## Ablauf

1. **Backup erzeugen:** `tools/backup.sh` ausführen (siehe dort).
2. **Ziel für den Test waehlen** (eines von beiden, nie das Produktivprojekt selbst):
   - **Lokal (schneller, kein neues Cloud-Projekt noetig):** `npx supabase db start` (lokales
     Docker-Postgres) in einem Wegwerf-Ordner, dann Schema- und Daten-Dump per `psql` einspielen:
     ```bash
     psql "$(npx supabase status -o env | grep DB_URL | cut -d= -f2-)" -f backups/schema_<stamp>.sql
     psql "$(npx supabase status -o env | grep DB_URL | cut -d= -f2-)" -f backups/data_<stamp>.sql
     ```
   - **Cloud (realistischer, kostet ein zweites kleines Supabase-Projekt):** neues, separates
     Supabase-Projekt anlegen (Region egal, wird danach geloescht), verlinken, Dumps einspielen.
3. **Pruefen, nicht nur "es lief durch":**
   - Zeilenzahl je Kern-Tabelle vergleicht sich mit dem Original (`select count(*) from receipts`
     etc. vor dem Backup und nach der Wiederherstellung).
   - RLS greift auch in der wiederhergestellten Instanz (kurzer Test mit zwei Nutzern, wie in
     `supabase/tests/run_schema_tests.py`).
   - Eine App-Instanz (Debug-Build, andere `dart_defines`) gegen die wiederhergestellte Instanz
     zeigt echte Bons/Inventar korrekt an.
4. **Aufräumen:** Docker-Postgres stoppen (`npx supabase stop`) bzw. das Test-Cloud-Projekt löschen.
5. **Ergebnis eintragen** in [[09 Sicherheit und Datenschutz]] §7 (Haken setzen, Datum, was geprüft
   wurde, welche Abweichungen es gab).

## Was dieser Test NICHT ist

Kein Test der automatischen Backups von Supabase selbst (die sind im Free-Tier ohnehin
eingeschränkt, siehe §6) — das hier prüft nur, dass **unser eigener** `tools/backup.sh`-Dump im
Ernstfall tatsächlich brauchbar ist.
