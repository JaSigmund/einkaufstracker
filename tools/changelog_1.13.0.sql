insert into app_changelog (version, title, highlights, released_at) values
  ('1.13.0', 'Nahrungsergaenzung und Naehrstoffe fuer alle Mahlzeiten',
   '[
     "Nahrungsergaenzung: Tabletten, Kapseln oder Pulver mit dem Inhalt laut Packung anlegen und mit einem Tipp als genommen eintragen. Die Werte stehen auf der Seite Naehrstoffe als eigene Quelle, getrennt von den Mahlzeiten, und die App bewertet nicht, ob die Menge passt",
     "Aeltere Mahlzeiten ergaenzen: Vitamine und Mineralstoffe fuer Mahlzeiten aus der Zeit vor 1.11 werden auf Wunsch nachgerechnet. Vorhandene Werte bleiben unveraendert, nichts wird geraten",
     "Referenzmengen und eigene Referenzwerte gelten jetzt fuer den ganzen Haushalt und sind auf allen Geraeten gleich. Lokale Werte werden einmal uebernommen",
     "Neue Produkte aus Open Food Facts bringen Vitamine und Mineralstoffe mit, soweit dort angegeben und plausibel",
     "Noch nicht dabei: Garverluste und ein Schale-Schalter (dafuer fehlt eine belastbare Datenquelle)"
   ]'::jsonb,
   now());
