insert into app_changelog (version, title, highlights, released_at) values
  ('1.24.0', 'Inventar nach Kategorien, Naehrstoff-Quellen mit Namen',
   '[
     "Inventar: Der Bestand ist jetzt nach Produktkategorien geordnet. Abschnitte klappst du per Tippen auf und zu, die App merkt sich, welche offen sind. Abgelaufenes und bald Faelliges siehst du auch im zugeklappten Abschnitt als farbigen Punkt",
     "Inventar: Oben zeigt Zuerst verbrauchen, wie viel abgelaufen ist oder bald ablaeuft, und fuehrt zur bisherigen Ansicht nach Ablauf. Zwischen Kategorien und Ablauf wechselst du jederzeit oben",
     "Inventar: Neues Suchfeld fuer Name, Marke und Kategorie, auch ohne Umlaute (kase findet Kaese)",
     "Naehrstoffe: Woher kommt das? nennt jetzt das Produkt statt nur Zutat, zeigt alle Beitraege mit ihrem Anteil und listet die Zutaten, fuer die es keinen Wert gibt",
     "Naehrstoffe: In der Wochenansicht sind die Beitraege Durchschnitte je Tag und ergeben zusammen den Wochenwert"
   ]'::jsonb,
   now());
