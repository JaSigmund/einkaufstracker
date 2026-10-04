insert into app_changelog (version, title, highlights, released_at) values
  ('1.12.0', 'Journal mit Ring, PDF und Vorschlaegen',
   '[
     "Im Journal zeigt jeder Tag einen Ring gegen deinen Energie-Richtwert, ohne Richtwert einen Balken. Tage ohne bekannte Werte bleiben leer, unbekannt ist nicht 0",
     "Nicht Erfasstes schaetzen: auf Wunsch rechnet das Journal Zutaten ohne Naehrwerte, aber mit Menge, grob dazu, getrennt ausgewiesen und als Schaetzung gekennzeichnet",
     "Monat als PDF teilen: Zusammenfassung, Kalenderraster und Tag fuer Tag alle Mahlzeiten mit kcal, auf Wunsch mit Foto",
     "Fehlt etwas? Nach der Foto-Analyse schlaegt die App Oel, Butter oder Gewuerze vor, die in aehnlichen frueheren Mahlzeiten dabei waren. Nichts wird ohne Antippen uebernommen",
     "Einkaufsliste aus einer Mahlzeit: Was fuer ein Gericht fehlt oder zu knapp ist, landet mit einem Tipp auf der Einkaufsliste (Langer Druck auf die Mahlzeit)"
   ]'::jsonb,
   now());
