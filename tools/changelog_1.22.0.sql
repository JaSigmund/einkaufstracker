insert into app_changelog (version, title, highlights, released_at) values
  ('1.22.0', 'Neue Kategorien beim Bon-Import',
   '[
     "Neue Bon-Artikel landen jetzt auch in den Kategorien Nudeln, Reis & Getreide, Saucen & Pesto, Aufstriche & Dips, Chips & Nuesse und Snacks to go, sofern es sie in deinem Haushalt gibt",
     "Instant-Nudeln und Ramen zaehlen als Fertiggerichte, auch wenn Huhn oder Rind im Namen steht",
     "Mahlzeiten: Die Haushaltseinheit einer Zutat (Scheibe, EL und Co.) wird jetzt auch auf dem Server gespeichert"
   ]'::jsonb,
   now());
