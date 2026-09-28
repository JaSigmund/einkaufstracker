insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.8', 'Eigentliche Ursache des Foto-Scan-Absturzes behoben',
   '[
     "Ein Geometrie-Sonderfall beim Zuschneiden des Zahlungsblocks (nicht der Hofer-Parser selbst) war der eigentliche Grund für den Fehler \"invalid argument(s): 0\" — jetzt behoben, statt nur abgefangen"
   ]'::jsonb,
   now());
