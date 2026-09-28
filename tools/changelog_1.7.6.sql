insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.6', 'Drei gemeldete Fehler behoben',
   '[
     "Bon löschen fragt jetzt nach, ob eine bestehende Zuordnung zu einem Inventar-Eintrag mit entfernt werden soll",
     "Ein erneut gescannter, zuvor gelöschter Foto-Bon wird korrekt wiedererkannt: keine doppelten Vorschläge mehr, Zuordnungen heilen sich von selbst",
     "Ablauf-Erinnerungen berücksichtigen jetzt auch noch unbestätigte Bon-Vorschläge, nicht nur bereits eingescannten Bestand"
   ]'::jsonb,
   now());
