insert into app_changelog (version, title, highlights, released_at) values
  ('1.8.2', 'Einkaufsliste mit Preisschaetzung',
   '[
     "Neu: Die Einkaufsliste zeigt oben, was der Einkauf voraussichtlich kostet (nach dem zuletzt bezahlten Preis); Artikel ohne bekannten Preis werden genannt",
     "Neu: Auf dem Bon steht, was die abgehakten Listenartikel vor dem Einkauf gekostet haetten und was du bezahlt hast"
   ]'::jsonb,
   now());
