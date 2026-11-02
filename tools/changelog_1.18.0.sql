insert into app_changelog (version, title, highlights, released_at) values
  ('1.18.0', 'Einkauf abschliessen und Rezepte gezielt suchen',
   '[
     "Einkauf abschliessen: ein Tipp nimmt alles Abgehakte von der Liste und legt es ins Archiv, Offenes bleibt stehen. Das Archiv erreichst du ueber das Kisten-Symbol auf der Liste, von dort laesst sich ein Einkauf auch zurueckholen",
     "Rezepte: Gerichte gezielt suchen, zum Beispiel Lasagne. Du bekommst passende Varianten und siehst, was noch fehlt, und kannst sie speichern, einplanen oder auf die Einkaufsliste setzen",
     "Meine Rezepte: eigene Rezepte mit Zutaten und Zubereitung anlegen, gespeicherte Rezepte bearbeiten",
     "Fehlende Zutaten eines gespeicherten Rezepts: frei getippte Zutaten werden jetzt ueber den Namen im Inventar gefunden und nicht mehr doppelt auf die Liste gesetzt"
   ]'::jsonb,
   now());
