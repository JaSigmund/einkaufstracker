insert into app_changelog (version, title, highlights, released_at) values
  ('1.9.1', 'Mehrere Online-Artikel je Produkt',
   '[
     "Neu: Bei einem Produkt lassen sich mehrere Online-Artikel desselben Haendlers zuordnen, zum Beispiel Bio-Paprika und normale Paprika bei Billa",
     "Die Suche erlaubt Mehrfachauswahl, schon zugeordnete Artikel sind markiert",
     "Der Artikel mit dem niedrigsten Grundpreis hat einen Stern und steht in einer Zeile darunter"
   ]'::jsonb,
   now());
