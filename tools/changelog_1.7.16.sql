insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.16', 'Bon zuordnen findet jetzt auch Bon-Vorschlaege',
   '[
     "Fehler behoben: Bei einem bereits vorhandenen Inventar-Artikel meldete \"Bon zuordnen\" faelschlich \"keine passende Bon-Position\", obwohl der passende Bon als Vorschlag vorlag. Die Position ist jetzt waehlbar, der Vorschlag wird dabei aufgenommen und nichts doppelt gezaehlt"
   ]'::jsonb,
   now());
