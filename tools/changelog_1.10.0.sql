insert into app_changelog (version, title, highlights, released_at) values
  ('1.10.0', 'Naehrwerte werden deutlich haeufiger gefunden',
   '[
     "Die Foto-Erkennung ordnet jede Zutat jetzt einem Eintrag der Lebensmitteldatenbank zu, auch wenn der Name nicht genau passt (Paprika, Quark, Milch ...)",
     "Marken je Zutat: Haken = sicher, Tilde = automatisch zugeordnet (antippen bestaetigt), Fragezeichen = unbekannt",
     "Die App merkt sich deine Zuordnungen im Haushalt, beim naechsten Foto heisst Quark dasselbe",
     "Neu im Tagebuch: Produkte vom Bon bekommen Naehrwerte, die App schlaegt je Produkt einen Eintrag vor",
     "Getraenke stehen in ml, gekochter Reis zieht nichts vom Reisbestand ab"
   ]'::jsonb,
   now());
