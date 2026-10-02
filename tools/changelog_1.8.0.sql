insert into app_changelog (version, title, highlights, released_at) values
  ('1.8.0', 'Essenstagebuch und Haushalt mit mehreren Personen',
   '[
     "Neu: Tab \"Tagebuch\" -- Mahlzeiten erfassen mit Zutaten aus dem Inventar, der Lebensmitteldatenbank (BLS) oder als Freitext; der Bestand wird abgezogen, beim Loeschen oder Aendern wieder zurueckgebucht; Naehrwerte pro Tag und Woche",
     "Neu: Foto zur Mahlzeit und Zutaten-Vorschlag per KI (nur mit Cloud-Einwilligung, immer zum Pruefen und Aendern, Schaetzungen sind gekennzeichnet)",
     "Neu: eigene Richtwerte fuer Naehrwerte, Verbrauchsbilanz mit Deckungsgrad und Schnelleintraege (nochmal essen, Reste ohne Abzug, Naehrwerte von Hand fuer Restaurantessen)",
     "Neu: weitere Personen per Einladungscode in den Haushalt einladen (Einstellungen -> Haushalt, auf der Anmeldeseite: Einladung annehmen); zu mehreren wird alle 30 Sekunden synchronisiert, ueberschriebene Aenderungen anderer werden angezeigt",
     "Fix: Konto loeschen entfernt jetzt auch die Essensfotos"
   ]'::jsonb,
   now());
