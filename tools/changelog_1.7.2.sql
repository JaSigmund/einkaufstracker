insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.2', 'Sync-Hänger wirklich behoben',
   '[
     "Sync bleibt nicht mehr haengen, wenn der Upload eines Bon-Fotos oder einer Bon-PDF ins Stocken kommt",
     "Bon-Vorschlaege werden nie mehr doppelt angelegt, auch wenn ein Bon geloescht und danach erneut importiert wird"
   ]'::jsonb,
   now());
