insert into app_changelog (version, title, highlights, released_at) values
  ('1.11.0', 'Vitamine, Mineralstoffe und Fettsaeuren',
   '[
     "Neue Seite Naehrstoffe im Tagebuch: 38 Werte pro Tag und Woche, darunter Vitamin C, D und B12, Eisen, Calcium, Jod, Omega-3 und Folat",
     "Ehrlich bei Luecken: jede Summe sagt, aus wie vielen Zutaten sie stammt, und steht als mindestens da, wenn Werte fehlen. Unbekannt wird nie als 0 gezaehlt",
     "Woher kommt das? Antippen zeigt die groessten Beitraege nach Zutat und Mahlzeit",
     "Auf Wunsch Referenzmengen laut Lebensmittelkennzeichnung (keine Empfehlung, ohne Bewertung), eigene Werte sind moeglich",
     "Mehr Naehrwerte einer Mahlzeit: langer Druck auf die Mahlzeit im Tagebuch",
     "Die Werte stammen aus dem Bundeslebensmittelschluessel. Garverluste und Nahrungsergaenzung sind nicht beruecksichtigt, Selen und Koffein fehlen in der Quelle"
   ]'::jsonb,
   now());
