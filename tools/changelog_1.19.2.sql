insert into app_changelog (version, title, highlights, released_at) values
  ('1.19.2', 'Stueckgewicht eingeben und genauere Naehrwerte',
   '[
     "Das Gewicht von 1 Stueck laesst sich jetzt auch mehrstellig eingeben, der Cursor springt nicht mehr auf die Menge",
     "Foto-Analyse: Gekochte Zutaten aus dem Bestand rechnen mit den Werten fuer Gekochtes. 200 g gekochter Reis zaehlten vorher wie 200 g roher",
     "Beim Bearbeiten einer Mahlzeit gehen die Naehrwerte von Produkten ohne eigenes Profil nicht mehr verloren",
     "Ein eingetipptes Stueckgewicht gilt nur noch fuer Stueck, nicht mehr fuer Scheibe oder Essloeffel"
   ]'::jsonb,
   now());
