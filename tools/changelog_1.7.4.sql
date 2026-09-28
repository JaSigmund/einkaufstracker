insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.4', 'Foto-Scan stürzt nicht mehr ab',
   '[
     "Der Foto-Scan eines Bons stürzt nicht mehr ab, wenn die Cloud-Vorbereitung oder die lokale Texterkennung an einem ungewohnten Foto scheitert"
   ]'::jsonb,
   now());
