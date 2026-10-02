insert into app_changelog (version, title, highlights, released_at) values
  ('1.8.1', 'Journal und Portionen umrechnen',
   '[
     "Neu: Journal (Symbol im Tab Tagebuch) -- Monatsraster mit den Fotos deiner Tage, dazu ein Rueckblick auf die Woche mit erfassten Tagen, Durchschnitt und haeufigsten Gerichten",
     "Neu: Portionen umrechnen -- alle Mengen eines Gerichts auf eine andere Portionenzahl skalieren",
     "Klarer: der Hinweis vor der Foto-Analyse sagt jetzt genau, was gesendet wird und dass die Aufbewahrung bei Anthropic deren Bedingungen folgt",
     "Fix: in der Web-Version werden keine Mahlzeitenfotos mehr angeboten (dort nicht moeglich)"
   ]'::jsonb,
   now());
