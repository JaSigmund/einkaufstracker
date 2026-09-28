-- Status-Update nach dem Release 1.2.0 (die 3 am 27.09. nachgereichten Bugs).
-- Wird einmalig ausgefuehrt, nicht Teil der Migrationen selbst.

update bug_reports set status='fixed', severity='high', fixed_in_version='1.2.0', status_updated_at=now(),
  resolution='Beim Verfeinern eines Bon-Vorschlags per Scan wurde die eingegebene Menge verworfen und durch die (oft falsche) Menge des Bon-Vorschlags ersetzt. Jetzt gewinnt immer die beim Scan eingegebene Menge/Einheit; eine Abweichung zur urspruenglichen Bon-Menge wird als Korrekturbuchung im Bestandsverlauf sichtbar.'
  where title='Bonartikel-Erkennung';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.2.0', status_updated_at=now(),
  resolution='Die Detailseite eines Inventar-Eintrags zeigt jetzt den zugeordneten Bon (Haendler, Datum, Bon-Text, Preis), sofern der Eintrag aus einem Bon-Vorschlag entstanden ist. Das nachtraegliche Verknuepfen eines rein per Scan erfassten Eintrags mit einem Bon sowie eine uebersichtliche Darstellung mehrerer Kaeufe desselben Produkts ueber mehrere Bons folgen in einem spaeteren Schritt.'
  where title='Bonzuordnung anzeigen';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.2.0', status_updated_at=now(),
  resolution='Neu: "Meine Produkte" in den Einstellungen listet alle Produkte durchsuchbar auf und oeffnet sie zum Bearbeiten. Im Bearbeitungsformular werden die gelernten Bon-Zuordnungen (Aliase) angezeigt und lassen sich einzeln loesen, falls ein Bon-Text faelschlich einem Produkt zugeordnet wurde.'
  where title='Alias ändern';

insert into app_changelog (version, title, highlights, released_at) values
  ('1.2.0', 'Bon-Menge, Bon-Herkunft und Produktverwaltung',
   '["Beim Scan eingegebene Menge/Einheit ueberschreibt nicht mehr die Menge des Bon-Vorschlags", "Inventar-Detailseite zeigt den zugeordneten Bon (Haendler, Datum, Preis)", "Neue Produktliste (Einstellungen -> Meine Produkte), gelernte Bon-Zuordnungen lassen sich dort loesen"]'::jsonb,
   now());
