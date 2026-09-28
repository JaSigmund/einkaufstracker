insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.5', 'Featurevorschlag und einheitliche Rückmeldungen',
   '[
     "Neue Option in den Einstellungen: Feature vorschlagen, neben dem bisherigen Fehler melden",
     "Meine Rückmeldungen (vorher Meine Fehlerberichte) zeigt Fehlerberichte und Featurevorschläge zusammen mit eigenem Symbol und eigenen Status-Bezeichnungen"
   ]'::jsonb,
   now());
