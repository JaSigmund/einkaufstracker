# Changelog

Spiegelt die Tabelle `app_changelog` (angezeigt in der App unter Einstellungen → „Änderungsprotokoll“). Wird von Hand nach jedem Release aktualisiert, wenn ein neuer Eintrag per SQL angelegt wird. Fehlerberichte und ihr Bearbeitungsstatus stehen ausführlicher im Vault unter „17 Fehlerprotokoll“.

## 1.7.9 — 2026-09-30

Konto löschen

- Neue Option in den Einstellungen: Konto löschen (mit Sicherheitsabfrage) — löscht das Konto und alle Daten unwiderruflich

## 1.7.8 — 2026-09-28

Eigentliche Ursache des Foto-Scan-Absturzes behoben

- Ein Geometrie-Sonderfall beim Zuschneiden des Zahlungsblocks (nicht der Hofer-Parser selbst) war der eigentliche Grund für den Fehler "invalid argument(s): 0" — jetzt behoben, statt nur abgefangen

## 1.7.7 — 2026-09-28

Erste Hofer-Bon-Erkennung beim Foto-Scan

- Ein fotografierter Hofer-Bon wird jetzt direkt auf dem Handy erkannt, ohne Umweg über die Cloud
- Erste Version, gebaut anhand eines einzelnen echten Bons (noch kein so breiter Datensatz wie bei Billa) — wird mit weiteren echten Hofer-Bons weiter geschärft

## 1.7.6 — 2026-09-28

Drei gemeldete Fehler behoben

- Bon löschen fragt jetzt nach, ob eine bestehende Zuordnung zu einem Inventar-Eintrag mit entfernt werden soll
- Ein erneut gescannter, zuvor gelöschter Foto-Bon wird korrekt wiedererkannt: keine doppelten Vorschläge mehr, Zuordnungen heilen sich von selbst
- Ablauf-Erinnerungen berücksichtigen jetzt auch noch unbestätigte Bon-Vorschläge, nicht nur bereits eingescannten Bestand

## 1.7.5 — 2026-09-28

Featurevorschlag und einheitliche Rückmeldungen

- Neue Option in den Einstellungen: Feature vorschlagen, neben dem bisherigen Fehler melden
- Meine Rückmeldungen (vorher Meine Fehlerberichte) zeigt Fehlerberichte und Featurevorschläge zusammen mit eigenem Symbol und eigenen Status-Bezeichnungen

## 1.7.4 — 2026-09-28

Foto-Scan stürzt nicht mehr ab

- Der Foto-Scan eines Bons stürzt nicht mehr ab, wenn die Cloud-Vorbereitung oder die lokale Texterkennung an einem ungewohnten Foto scheitert (live entdeckt an einem Hofer-Bon)

## 1.7.3 — 2026-09-28

Bonzuordnung zu gelöschtem Bon korrigiert

- Die Bonzuordnung eines Inventar-Eintrags zeigt einen gelöschten Bon nicht mehr fälschlich als gültig an

## 1.7.2 — 2026-09-28

Sync-Hänger wirklich behoben

- Sync bleibt nicht mehr hängen, wenn der Upload eines Bon-Fotos oder einer Bon-PDF ins Stocken kommt (der vorige Fix deckte nur die Tabellen-Synchronisierung ab)
- Bon-Vorschläge werden nie mehr doppelt angelegt, auch wenn ein Bon gelöscht und danach erneut importiert wird — strukturell abgesichert, nicht nur beim Löschen aufgeräumt

## 1.7.1 — 2026-09-28

Drei Praxistest-Fehler behoben

- Grundpreis bei Mehrfach-Packungen (z.B. 4er-Packung) wird auf den Preis je Einzelstück heruntergerechnet
- Bon löschen verwirft auch die dazugehörigen Inventar-Vorschläge, kein doppelter Vorschlag mehr beim erneuten Import
- Monatsauswertung zeigt den Produktnamen statt des rohen Bon-Texts und fasst denselben Artikel über Händler hinweg zusammen
- Sync hängt nicht mehr dauerhaft, wenn eine Verbindung abreißt

## 1.7.0 — 2026-09-28

Grundpreis, Preisvergleich und Trends (Phase 4 komplett)

- Jeder Bon-Artikel bekommt eine Produkt-Zuordnung und einen Grundpreis (€/kg, €/l, €/Stk)
- Duplikate zusammenführen: zwei versehentlich getrennte Produkte lassen sich unter „Meine Produkte“ vereinen
- Artikel-Detail mit Preisverlauf und Händlervergleich (Tippen auf einen Artikel in der Auswertung)
- Neuer Trend-Tab: Ausgaben der letzten 6 oder 12 Monate auf einen Blick
- Monatsbudget mit Fortschrittsbalken
- Bon-Daten als CSV exportieren und teilen

## 1.6.0 — 2026-09-28

Einkaufsliste hakt sich jetzt selbst ab (Phase 3 komplett)

- Ein gekaufter Artikel hakt passende, offene Einträge auf der Einkaufsliste automatisch ab — der Kreis Liste → Einkauf → Bon schließt sich

## 1.5.0 — 2026-09-28

Menge und Inhalt in der Einkaufsliste, Produkt löschen

- Anzahl beim Hinzufügen zur Einkaufsliste direkt einstellbar, danach jederzeit über die Liste änderbar
- Neues Feld „Inhalt je Packung“ am Produkt (z.B. 4 Stück, 150 g); die Einkaufsliste zeigt dann zusätzlich die Gesamtmenge — nützlich, falls mal ein anderes Packungsformat gekauft wird
- Produkte lassen sich jetzt aus „Meine Produkte“ löschen (Wischen, mit Rückfrage)

## 1.4.0 — 2026-09-28

Lokale Ablauf-Erinnerungen und Stückgewicht (Phase 3 jetzt vollständig)

- Lokale Benachrichtigung, wenn Produkte bald ablaufen, mit den Aktionen „Auf Liste setzen“ und „Ignorieren“ direkt in der Benachrichtigung
- Die Einkaufsliste bekommt jetzt auch beim Ausloeser „Ablauf“ automatische Vorschläge (bisher nur bei „Leer“)
- Neue Produkte übernehmen das Stückgewicht von Open Food Facts, wo bekannt (Vorbereitung fürs spätere Essenstagebuch)

## 1.3.0 — 2026-09-28

Einkaufsliste, intuitivere Produktverwaltung, Haltbarkeits-Vorbelegung (Phase 3 abgeschlossen)

- Neuer Tab „Liste“: Einkaufsliste offline nutzbar, nach Kategorie gruppiert, abgehakte Artikel wandern nach unten, automatischer Vorschlag wenn ein Nachkaufprodukt komplett aufgebraucht ist
- Produktname direkt auf der Inventar-Detailseite umbenennbar, weitere Produktdetails über ein Bearbeiten-Icon erreichbar (statt Umweg über Einstellungen)
- Bonzuordnung eines Inventar-Eintrags lässt sich direkt dort lösen oder auf eine passende Bon-Position ändern
- Neue Produkte bekommen Haltbarkeit-nach-Öffnen, Lagerort und MHD/Verbrauchsdatum automatisch vorbelegt, je nach erkanntem Produkttyp (z.B. Milch, Fleisch, Honig)

## 1.2.0 — 2026-09-28

Bon-Menge, Bon-Herkunft und Produktverwaltung

- Beim Scan eingegebene Menge/Einheit überschreibt nicht mehr die Menge des Bon-Vorschlags
- Inventar-Detailseite zeigt den zugeordneten Bon (Händler, Datum, Preis)
- Neue Produktliste (Einstellungen → Meine Produkte), gelernte Bon-Zuordnungen lassen sich dort lösen

## 1.1.0 — 2026-09-27

Fehlerverfolgung, Changelog und mehr Kontrolle im Inventar

- Fehlerberichte haben jetzt einen Bearbeitungsstatus (Gemeldet/Bestätigt/In Bearbeitung/Behoben/...) und eine Lösungsnotiz
- Änderungsprotokoll der App unter Einstellungen
- Versionsnummer wird in den Einstellungen angezeigt
- Barcode lässt sich über „Andere Zuordnung“ neu verknüpfen
- Produktsuche beim Scan läuft automatisch, plus Vorschlagsliste unverknüpfter Bon-Produkte
- Rückgängig-Schaltfläche direkt nach Aufgebraucht/Weggeworfen
- Gelöschter Bon-Artikel wird wieder zum Vorschlag statt zu verschwinden

## 1.0.1 — 2026-09-27

Sync-Fehler und erste Korrekturen

- Synchronisierung hängt nicht mehr an gelernten Produktzuordnungen fest
- Bestandsmenge: Einheit (Stück/kg/l) wählbar, für das Produkt merkbar
- Inventar-Eintrag löschen (falsch erfasst)
