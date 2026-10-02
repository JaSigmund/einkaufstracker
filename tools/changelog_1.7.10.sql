insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.10', 'Ablauf-Erinnerungen nachgeholt',
   '[
     "Fehler behoben: eine verpasste Ablauf-Erinnerung ging bisher fuer immer verloren, statt nachgeholt zu werden"
   ]'::jsonb,
   now());
