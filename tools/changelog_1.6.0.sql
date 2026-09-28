insert into app_changelog (version, title, highlights, released_at) values
  ('1.6.0', 'Einkaufsliste hakt sich jetzt selbst ab',
   '["Ein gekaufter Artikel hakt passende, offene Eintraege auf der Einkaufsliste automatisch ab"]'::jsonb,
   now());
