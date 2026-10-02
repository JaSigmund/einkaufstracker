insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.14', 'Ablauf-Erinnerungen kommen jetzt wirklich an',
   '[
     "Fehler behoben: im Release-Build fehlten ProGuard-Regeln fuer die Benachrichtigungs-Komponente -- Erinnerungen wurden korrekt geplant, aber beim Ausloesen stillschweigend verworfen"
   ]'::jsonb,
   now());
