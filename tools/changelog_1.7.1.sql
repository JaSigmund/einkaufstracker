insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.1', 'Drei Praxistest-Fehler behoben',
   '[
     "Grundpreis bei Mehrfach-Packungen (z.B. 4er-Packung) wird auf den Preis je Einzelstueck heruntergerechnet",
     "Bon loeschen verwirft auch die dazugehoerigen Inventar-Vorschlaege, kein doppelter Vorschlag mehr beim erneuten Import",
     "Monatsauswertung zeigt den Produktnamen statt des rohen Bon-Texts und fasst denselben Artikel ueber Haendler hinweg zusammen",
     "Sync haengt nicht mehr dauerhaft, wenn eine Verbindung abreisst"
   ]'::jsonb,
   now());
