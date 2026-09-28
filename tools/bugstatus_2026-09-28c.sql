update bug_reports set status='fixed', severity='low', fixed_in_version='1.5.0', status_updated_at=now(),
  resolution='"Meine Produkte" hat jetzt eine Wischen-zum-Loeschen-Aktion mit Rueckfrage. Bereits erfasste Bons, Inventar-Eintraege und Einkaufslisten-Positionen behalten ihre Zuordnung und zeigen den Namen weiter an; nur Suche, Autovervollstaendigung und Barcode-Zuordnung ignorieren das geloeschte Produkt danach.'
  where title='Produkt löschen';
