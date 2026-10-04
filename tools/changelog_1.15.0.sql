insert into app_changelog (version, title, highlights, released_at) values
  ('1.15.0', 'Garverluste bei Vitaminen und Mineralstoffen',
   '[
     "Garverluste: Bei einer rohen Zutat aus der Lebensmitteldatenbank waehlst du die Zubereitung (gekocht, gedaempft, gebraten, gebacken, gegrillt). Die Menge gilt dann als Rohgewicht, Vitamine und Mineralstoffe werden um die typischen Verluste gemindert, zum Beispiel Vitamin C und Folat beim Kochen von Gemuese",
     "Die Faktoren stammen aus der USDA-Tabelle der Naehrstoffverluste (Release 6, gemeinfrei) und sind Durchschnittswerte fuer 20 Lebensmittelgruppen, fuer 15 Naehrstoffe. Energie und Makros bleiben unveraendert, die Zeile nennt die staerksten Verluste",
     "Beim Bearbeiten einer Mahlzeit wird nicht ein zweites Mal gemindert: die Zubereitung wird mitgespeichert",
     "Noch nicht dabei: Schale-Schalter (es fehlt eine Quelle fuer Abfallanteile)"
   ]'::jsonb,
   now());
