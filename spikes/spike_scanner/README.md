# Spike: Scanner, OCR, Barcode, Open Food Facts

Wegwerf-App für Phase 0. Sie beantwortet drei Fragen mit echten Daten statt Annahmen:

1. **Dokumentenscanner:** Wie gut sind Zuschnitt und Entzerrung von `google_mlkit_document_scanner` bei langen, knittrigen Thermopapier-Bons?
2. **OCR + Zeilenclustering:** Landen Artikelname (links) und Preis (rechts) nach `clusterRows()` in derselben Zeile? (Kern des Parsers, siehe Doku 05 §3.2)
3. **Open Food Facts:** Wie viele deiner echten Produkte kennt OFF per EAN?

## Bauen und installieren (Windows, PowerShell)

```powershell
. C:\Users\jakob\dev\env.ps1          # Flutter, JDK, Android SDK in den PATH
cd C:\Users\jakob\Documents\Einkaufstracker\spikes\spike_scanner
flutter build apk --release --target-platform android-arm64   # 62 MB
adb install -r build\app\outputs\flutter-apk\app-release.apk   # Handy per USB, USB-Debugging an
```

Ohne Kabel: `app-release.apk` aufs Handy kopieren (Drive, Mail, USB-Dateiübertragung) und dort öffnen, „Unbekannte Apps installieren“ für die Quelle erlauben.

## Benutzen

**Tab Bon**
1. „Bon scannen“, Bon flach hinlegen, gute Beleuchtung. Bei langen Bons mehrere Seiten (max. 4) in Lesereihenfolge.
2. Die App zeigt „Bildzeilen“ (nach dem Clustering) und den rohen OCR-Text. Prüfe: Stehen Name und Preis in einer Zeile? Sind Mengenzeilen (`2 x 1,29`) erkannt?
3. Pro Scan werden gespeichert: Foto(s) `bon-<zeit>-pN.jpg`, `bon-<zeit>.ocr.json` (Zeilen mit Bounding Boxes) und `bon-<zeit>.rows.txt`.

**Tab Barcode**
1. Barcodes von Produkten scannen, die du wirklich kaufst (mindestens 30, gemischt Billa/Hofer, Eigenmarken und Markenartikel).
2. Die App fragt Open Food Facts ab und zählt die Trefferquote. Ergebnisse landen in `off_results.csv`.

## Dateien vom Handy holen

Ordner: `/sdcard/Android/data/at.jakob.spike_scanner/files/spike/`

```powershell
adb pull /sdcard/Android/data/at.jakob.spike_scanner/files/spike C:\Users\jakob\Documents\Einkaufstracker\testdata\receipts\raw
```

Alternativ das Teilen-Symbol in der App (z.B. an dich selbst per Mail/Drive). `testdata/receipts/` ist per `.gitignore` von Git ausgeschlossen, weil Bons persönliche Daten enthalten (Bonus-Nummer, Kartenendziffern).

## Auswertung

Was zurückkommt, wird in `11 Roadmap und Meilensteine.md` (Phase 0) abgehakt und fließt in die Parser-Spezifikation in `05 Bon-Erkennung.md` ein. Bewertungsfragen:

- Scanner: In wie vielen von 10 Bons ist der Zuschnitt sofort brauchbar?
- OCR: Anteil der Positionszeilen, bei denen Name und Preis korrekt in einer Bildzeile stehen
- Typische Fehler: Ziffern (0/O, 1/l, 5/S), Komma/Punkt, Umlaute, abgeschnittene Zeilen
- OFF: Trefferquote in Prozent, typische Lücken (Eigenmarken? frische Ware ohne EAN?)

## Bekannte Grenzen des Spikes

- Nur Android (`google_mlkit_document_scanner` unterstützt kein iOS). Für iOS ist `cunning_document_scanner` der Ersatzkandidat, wird erst in Phase 6 getestet.
- Keine Anmeldung, keine Datenbank, keine Cloud-KI. Reine Messwerkzeuge.

## Hinweis Release-Build

Ohne `android/app/proguard-rules.pro` bricht R8 im Release-Build ab (ML Kit verweist auf optionale Schrifterkenner). Die Regeln muessen in die produktive App uebernommen werden.
