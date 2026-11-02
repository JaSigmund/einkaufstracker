insert into app_changelog (version, title, highlights, released_at) values
  ('1.18.0', 'Klare Mengen, Einkauf abschliessen und Rezepte gezielt suchen',
   '[
     "Mengen neu gedacht: Packung, Stueck und Menge passen ueberall zusammen. Eine Packung Yakult steht einmal auf dem Bon und im Bestand als 6 Flaeschchen mit 390 ml",
     "Produkte: beim Anlegen waehlst du, wie sie gekauft werden, zum Beispiel als Mehrfachpackung 6 x 65 ml. Der Bestand rechnet sich dann selbst um",
     "Inventar: Minus bucht ein Stueck oder eine Packung als verbraucht, statt immer 1 kg abzuziehen, und zaehlt damit fuer Vorhersage und Bilanz. Der letzte Rest macht den Eintrag zu Aufgebraucht, mit Rueckgaengig",
     "Bon-Vorschlaege stehen jetzt in der richtigen Menge im Bestand und werden beim Kochen mit abgezogen",
     "Einkauf abschliessen: ein Tipp nimmt alles Abgehakte von der Liste und legt es ins Archiv, Offenes bleibt stehen. Das Archiv erreichst du ueber das Kisten-Symbol auf der Liste, von dort laesst sich ein Einkauf auch zurueckholen",
     "Rezepte: Gerichte gezielt suchen, zum Beispiel Lasagne. Du bekommst passende Varianten und siehst, was noch fehlt, und kannst sie speichern, einplanen oder auf die Einkaufsliste setzen",
     "Meine Rezepte: eigene Rezepte mit Zutaten und Zubereitung anlegen, gespeicherte Rezepte bearbeiten",
     "Fehlende Zutaten eines gespeicherten Rezepts: frei getippte Zutaten werden jetzt ueber den Namen im Inventar gefunden und nicht mehr doppelt auf die Liste gesetzt"
   ]'::jsonb,
   now());
