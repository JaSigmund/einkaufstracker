insert into app_changelog (version, title, highlights, released_at) values
  ('1.14.0', 'Mehrere Listen, Erinnerungsstufen und MHD-Foto',
   '[
     "Mehrere Einkaufslisten: neben der Standardliste weitere anlegen (zum Beispiel Drogerie oder Baumarkt), Eintraege per langem Druck verschieben. Wird eine Liste geloescht, wandern ihre Eintraege auf die Standardliste",
     "Regal-Reihenfolge je Markt: die Kategorien so ziehen, wie der Markt sie fuehrt, und die Einkaufsliste danach sortieren",
     "Mehrstufige Erinnerungen: mehrere Zeitpunkte vor dem Ablauf (bis zu sieben Tage vorher und am Tag selbst), fuer alle Produkte oder fuer einzelne",
     "MHD fotografieren: die Texterkennung liest das Datum auf dem Geraet, du bestaetigst den Fund. Das Foto verlaesst das Telefon nicht",
     "Verbrauchsvorhersage: die Bestandsliste zeigt, wie lange ein Artikel nach deinem bisherigen Verbrauch noch reicht, und auf der Einkaufsliste steht, was bald aufgebraucht ist",
     "Noch nicht dabei: Push-Nachrichten von ausserhalb der App, weitere Haendler beim Bon-Import"
   ]'::jsonb,
   now());
