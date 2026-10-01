insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.12', 'Erinnerungszeit wirkt sofort',
   '[
     "Fehler behoben: Aendern der Erinnerungszeit in den Einstellungen hat eine bereits geplante Ablauf-Erinnerung nicht neu geplant -- erst ein Neustart der App oder eine Inventaraenderung taten das"
   ]'::jsonb,
   now());
