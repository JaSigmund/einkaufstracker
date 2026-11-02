insert into app_changelog (version, title, highlights, released_at) values
  ('1.19.1', 'Ohne Barcode erfassen, Bon-Zuordnung und Synchronisierung',
   '[
     "Ohne Barcode: Lose Ware wie Bananen kommt jetzt direkt ins Inventar, ueber den neuen Knopf im Inventar oder die Seite Scannen",
     "Bon-Vorschlaege lassen sich durch Antippen uebernehmen, die Menge vom Bon ist schon eingetragen",
     "Bon zuordnen zeigt jetzt auch Positionen, die beim Import bei einem anderen Produkt gelandet sind, mit Suche. Die Position wandert zum gewaehlten Produkt, und der naechste Bon erkennt sie richtig",
     "Synchronisierung: Aenderungen waehrend eines laufenden Abgleichs bleiben nicht mehr liegen, und bei hakender Verbindung wird schneller gesendet",
     "Fehlerberichte enthalten jetzt den letzten Sync-Fehler, auch wenn gerade ein neuer Versuch laeuft"
   ]'::jsonb,
   now());
