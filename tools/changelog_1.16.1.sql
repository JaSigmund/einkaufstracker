insert into app_changelog (version, title, highlights, released_at) values
  ('1.16.1', 'Haengende Aenderungen und Naehrwerte',
   '[
     "Merkt sich die App eine Zuordnung unter einem anders geschriebenen Namen, ersetzt sie jetzt die alte, statt beim Synchronisieren dauerhaft abgelehnt zu werden",
     "Lehnt der Server eine Aenderung ab, steht der Grund jetzt im Fehlerbericht",
     "Fast alle Produkte haben jetzt Naehrwerte und zaehlen damit im Tagebuch mit. Bei Markenprodukten sind es Naeherungen aus der Lebensmitteldatenbank"
   ]'::jsonb,
   now());
