insert into app_changelog (version, title, highlights, released_at) values
  ('1.15.1', 'Code-Review: Fehlerkorrekturen und Barrierefreiheit',
   '[
     "Synchronisation: Haben mehr als 500 Zeilen denselben Zeitstempel, kam das Holen fuer diese Tabelle nie weiter. Der Sync sortiert jetzt stabil und laeuft durch",
     "Bon-Erkennung, Rezeptvorschlaege und Kochassistent pruefen ihre Eingaben, das Tageslimit von 40 KI-Aufrufen je Haushalt und Tag gilt jetzt auch fuer die Bon-Erkennung, die App zeigt dazu eine verstaendliche Meldung",
     "Konto loeschen entfernt bei einem Lesefehler nicht mehr den gemeinsamen Haushalt aller Mitglieder",
     "Abmelden und Konto loeschen entfernen auch lokale Beleg- und Essensfotos und stornieren geplante Erinnerungen",
     "Bedienung: Tooltips an Symbolschaltern, besserer Kontrast bei Sekundaertexten, Listen-Chips wieder 48 dp hoch, benannte Aktionen fuer Screenreader"
   ]'::jsonb,
   now());
