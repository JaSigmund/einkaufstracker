# Changelog

Spiegelt die Tabelle `app_changelog` (angezeigt in der App unter Einstellungen → „Änderungsprotokoll“). Wird von Hand nach jedem Release aktualisiert, wenn ein neuer Eintrag per SQL angelegt wird. Fehlerberichte und ihr Bearbeitungsstatus stehen ausführlicher im Vault unter „17 Fehlerprotokoll“.

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
