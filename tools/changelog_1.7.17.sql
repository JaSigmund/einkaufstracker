insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.17', 'Rechnungen teilen, Rezeptvorschlaege, Web-App',
   '[
     "Neu: Bon-Positionen als \"von jemand anderem bezahlt\" ausschliessen -- sie zaehlen nicht zu Auswertung, Budget und Trend, bleiben aber auf dem Bon sichtbar",
     "Neu: Rezeptvorschlaege aus dem Inventar (dringlichste Zutaten zuerst), Koch-Chat und gespeicherte Rezepte, fehlende Zutaten gehen auf die Einkaufsliste",
     "Neu: Web-Version der App (auch fuer das iPhone ueber den Browser)"
   ]'::jsonb,
   now());
