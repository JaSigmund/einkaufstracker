insert into app_changelog (version, title, highlights, released_at) values
  ('1.5.0', 'Menge und Inhalt in der Einkaufsliste, Produkt löschen',
   '["Anzahl beim Hinzufuegen zur Einkaufsliste direkt einstellbar, danach jederzeit aenderbar", "Neues Feld \"Inhalt je Packung\" am Produkt (z.B. 4 Stueck, 150 g); die Einkaufsliste zeigt dann zusaetzlich die Gesamtmenge", "Produkte lassen sich jetzt aus \"Meine Produkte\" loeschen"]'::jsonb,
   now());
