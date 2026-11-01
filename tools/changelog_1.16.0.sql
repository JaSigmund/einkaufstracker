insert into app_changelog (version, title, highlights, released_at) values
  ('1.16.0', 'Foto-KI kennt jetzt deinen Titel und rechnet verlaesslicher',
   '[
     "Titel, Notiz, Portionen und schon eingetragene Zutaten gehen mit zur Foto-Analyse. Trag ein, was du weisst, dann wird der Vorschlag genauer",
     "Die KI nennt auch Zutaten, die man nicht sieht, aber meist dabei sind (Bratoel, Dressing). Sie stehen als vermutet in der Zeile und werden nicht vom Bestand abgezogen",
     "Naehrwerte: Gekochte Linsen oder Bohnen zaehlen nicht mehr als trockene Ware, und unbekannte Namen wie Rote Beete werden unter anderen Namen gesucht",
     "Ein zweiter Vorschlag ersetzt den ersten, statt ihn zu verdoppeln",
     "Auswertung: Beim Aufklappen einer Kategorie steht je Artikel jetzt auch Packungsgroesse und Gesamtmenge, zum Beispiel 4x je 500 g, 2 kg gesamt. Ist die Groesse nur teilweise bekannt, steht die Gesamtmenge als Mindestwert da"
   ]'::jsonb,
   now());
