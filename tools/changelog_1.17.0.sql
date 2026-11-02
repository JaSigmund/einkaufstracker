insert into app_changelog (version, title, highlights, released_at) values
  ('1.17.0', 'Schnell eintragen, Wochenplan und klarere Mengen',
   '[
     "Schnell eintragen: ein Glas Wasser oder Nahrungsergaenzung mit einem Tipp, ueber den Tropfen in der Titelleiste, als Widget auf dem Startbildschirm oder durch langes Druecken auf das App-Symbol",
     "Wochenplan: Gerichte je Tag vorplanen und mit einem Tipp auf die Einkaufsliste setzen, was dafuer fehlt. Zu finden auf der Liste",
     "Rezeptvorschlaege koennen jetzt auch Zutaten enthalten, die noch fehlen, und direkt in den Wochenplan wandern",
     "Einkaufsliste: die Menge steht jetzt verstaendlich da (zum Beispiel 1 x 290 ml statt 1 l) und laesst sich als Packungen oder genau in g, kg, ml, l oder Stueck angeben",
     "Die Meldung mit Rueckgaengig verschwindet bei Nahrungsergaenzung und Inventar wieder von selbst",
     "Sehr kleine Mengen beim Tagebuch-Abzug bleiben nicht mehr als abgelehnte Aenderung beim Synchronisieren haengen"
   ]'::jsonb,
   now());
