insert into app_changelog (version, title, highlights, released_at) values
  ('1.19.0', 'Koch-Timer und Rezepte im Tagebuch',
   '[
     "Koch-Timer: ueber der Kochanleitung gibt es jetzt neben dem Koch-Chat einen Timer. Er misst, wie lange ein Gericht wirklich dauert, Pausen zaehlen nicht mit",
     "Kurzzeitmesser fuer zwischendurch, zum Beispiel fuer den Ofen: auch ueber Schnell eintragen erreichbar, mit Alarm, wenn die Zeit um ist. Solange etwas laeuft, steht es oben in einer Leiste",
     "Bei Rezepten steht jetzt, wie oft du sie gekocht hast und wie lange es im Schnitt gedauert hat",
     "Tagebuch: Mit Aus Rezept uebernimmst du gespeicherte Rezepte und Gerichte aus dem Wochenplan. Die Mengen kommen vom letzten Mal, beim ersten Mal traegst du sie einmal ein",
     "Hinweis: Damit der Alarm auf die Sekunde genau kommt, musst du unter Android 14 oder neuer genaue Alarme erlauben. Der Timer zeigt dir den Weg dorthin"
   ]'::jsonb,
   now());
