insert into app_changelog (version, title, highlights, released_at) values
  ('1.20.0', 'Getraenke mit einem Tipp eintragen',
   '[
     "Schnell eintragen hat jetzt einen Abschnitt Getraenke: Der Plus-Knopf bucht, was du in dieser Zeile zuletzt getrunken hast, mit Rueckgaengig. Kalorien und Bestand zaehlen automatisch mit",
     "Gespritzt und gemischt: Ein Tipp auf die Zeile oeffnet Menge und Verhaeltnis mit Wasser (Pur, 1:1, 1:2, 1:3, 1:6, 1:8) und weitere Zutaten. Jede Mischung wird zur eigenen Zeile, vom Bestand geht nur ab, was dort liegt",
     "Andere Getraenke findest du ueber die Suche oder den Scanner",
     "Bei Flaschen in Stueck fragt die App einmal nach den ml und merkt sie sich",
     "Produkte haben jetzt einen Schalter Trinkbar. Die App belegt ihn selbst vor, korrigieren kannst du ihn jederzeit"
   ]'::jsonb,
   now());
