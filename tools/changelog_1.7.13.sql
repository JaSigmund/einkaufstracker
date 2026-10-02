insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.13', 'Ablauf-Erinnerung: haengenbleibende Erinnerung behoben',
   '[
     "Fehler behoben: eine ueberfaellige Ablauf-Erinnerung wurde bei haeufigen Neuplanungen (z.B. durch den Hintergrund-Sync) immer wieder um 5 Sekunden verschoben und konnte dadurch nie auslösen"
   ]'::jsonb,
   now());
