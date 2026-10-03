insert into app_changelog (version, title, highlights, released_at) values
  ('1.10.1', 'Stueck, Scheibe, EL: 1 Banane hat jetzt Naehrwerte',
   '[
     "Der Mengen-Dialog kennt Haushaltsmasse: Stueck (klein, mittel, gross), Scheibe, EL, TL, Zehe, Kopf und Stange, und rechnet sofort um (1 Stk ca. 118 g, 97 kcal)",
     "Gibt es fuer ein Lebensmittel kein bekanntes Gewicht, fragt die App einmal danach und merkt sich deine Antwort fuer alle kuenftigen Eintraege",
     "Die Foto-Erkennung zaehlt jetzt (2 Eier, 3 Scheiben Brot) und rechnet mit dem Gewicht aus der Tabelle statt mit geratenen Gramm",
     "Bruchteile als Schnellwahl (1/4, 1/2, 1 1/2), ohne Mengenschaetzung wird 1 Einheit vorbelegt",
     "Die Gewichte stammen fuer 109 Lebensmittel aus der USDA-Datenbank (essbarer Anteil, ohne Schale), sie sind Richtwerte und mit deinem eigenen Gewicht ueberschreibbar"
   ]'::jsonb,
   now());
