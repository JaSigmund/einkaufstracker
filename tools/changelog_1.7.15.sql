insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.15', 'Ablauf-Erinnerungen: fehlende Systemkomponente ergaenzt',
   '[
     "Fehler behoben: dem Benachrichtigungs-System fehlte eine zwingend noetige Systemkomponente, ohne die eine geplante Ablauf-Erinnerung beim Ausloesen stillschweigend verworfen wurde, statt zu erscheinen"
   ]'::jsonb,
   now());
