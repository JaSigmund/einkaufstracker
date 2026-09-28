insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.7', 'Erste Hofer-Bon-Erkennung beim Foto-Scan',
   '[
     "Ein fotografierter Hofer-Bon wird jetzt direkt auf dem Handy erkannt, ohne Umweg über die Cloud",
     "Erste Version, gebaut anhand eines einzelnen echten Bons (noch kein so breiter Datensatz wie bei Billa) — wird mit weiteren echten Hofer-Bons weiter geschärft"
   ]'::jsonb,
   now());
