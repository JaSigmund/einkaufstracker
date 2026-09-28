insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.3', 'Bonzuordnung zu gelöschtem Bon korrigiert',
   '[
     "Die Bonzuordnung eines Inventar-Eintrags zeigt einen geloeschten Bon nicht mehr faelschlich als gueltig an"
   ]'::jsonb,
   now());
