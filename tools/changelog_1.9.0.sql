insert into app_changelog (version, title, highlights, released_at) values
  ('1.9.0', 'Online-Preise von Billa und Spar',
   '[
     "Neu: Auf der Preisseite eines Produkts stehen Online-Preise von Billa und Spar, getrennt von deinen Kaeufen (Quelle: heisse-preise.io, taeglich aktualisiert)",
     "Du ordnest je Haendler einen Online-Artikel per Suche zu und bestaetigst ihn selbst",
     "Zu jedem Preis steht der Stand vom Tag; ist der Stand aelter als eine Woche oder der Artikel nicht mehr im Sortiment, steht der Preis als zuletzt bekannt da"
   ]'::jsonb,
   now());
