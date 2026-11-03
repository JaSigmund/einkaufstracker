insert into app_changelog (version, title, highlights, released_at) values
  ('1.23.0', 'Produktseite und Produktliste',
   '[
     "Neu: Jedes Produkt hat eine eigene Seite mit Bestand, Barcodes, Bon-Texten, Naehrwerten, Preisen, Kategorie und Lagerung. Du erreichst sie aus dem Inventar, der Auswertung, der Einkaufsliste (lange druecken) und von einer Zutat",
     "Neu: Im Inventar gibt es den Reiter Produkte mit den Ansichten Naehrwerte, Barcode, Bon-Text, Online, Kategorie und Duplikate. Mit Nur offene siehst du, was noch fehlt",
     "Naehrwerte lassen sich jetzt fuer alle Produkte ansehen und aendern, bisherige Mahlzeiten behalten ihre Werte",
     "Nicht noetig ersetzt Ueberspringen und gilt jetzt auf allen Geraeten, zuruecknehmen geht auch",
     "Sichere und automatische Vorschlaege uebernimmst du getrennt, gemerkt werden nur sichere oder bestaetigte"
   ]'::jsonb,
   now());
