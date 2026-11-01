insert into app_changelog (version, title, highlights, released_at) values
  ('1.15.2', 'Grundpreis aus dem Bon und ehrlicher Stand der Online-Preise',
   '[
     "Grundpreis: Steht die Packungsgroesse im Bon-Text (3kg, 150 G, 4x40g, 0,5l), rechnet die App damit. Zwiebeln 3 kg ergaben bisher einen dreimal zu hohen Grundpreis. Das gilt fuer neue Bons",
     "Produkte zusammenfuehren nimmt jetzt auch Bestandsbewegungen, Mahlzeiten-Zutaten und Online-Verknuepfungen mit",
     "Online-Preise: Der Stand wird je Artikel angezeigt. Spar liefert die Quelle derzeit nicht mehr, Spar-Preise erscheinen deshalb mit ihrem alten Stand und nach einer Woche als zuletzt bekannt, Billa laeuft normal weiter"
   ]'::jsonb,
   now());
