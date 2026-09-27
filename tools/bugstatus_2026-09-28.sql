-- Status-Update nach dem Release 1.1.0 (Fehlerverfolgung + Loesungen fuer die 9 gemeldeten Fehler).
-- Wird einmalig nach der Migration 0011 ausgefuehrt, nicht Teil der Migrationen selbst.

update bug_reports set status='fixed', severity='high', fixed_in_version='1.0.1', status_updated_at=now(),
  resolution='Ursache: product_aliases hatte auf dem Server keine deleted_at-Spalte, jeder Sync-Versuch gelernter Zuordnungen scheiterte seither mit PGRST204. Spalte per Migration ergaenzt (0010).'
  where title='Synchronisierung';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.0.1', status_updated_at=now(),
  resolution='Bestandserfassung hat jetzt eine Einheiten-Auswahl (Stueck/kg/l) mit "Fuer dieses Produkt merken". Neue Bon-Produkte uebernehmen ausserdem gleich die Einheit aus dem Bon (kg bleibt kg). In 1.1.0 zusaetzlich: automatische Vorbelegung der Suche und eine Liste "zuletzt aus Bons, noch ohne Barcode".'
  where title='Bonartikel bearbeiten';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.0.1', status_updated_at=now(),
  resolution='Die Detailseite eines Inventar-Eintrags hat ein Loeschen-Symbol mit Rueckfrage: entfernt den Eintrag und seine Kaufbewegung, als waere er nie erfasst worden.'
  where title='Rückgängig machen';

update bug_reports set status='fixed', severity='low', fixed_in_version='1.1.0', status_updated_at=now(),
  resolution='Die App zeigt die Versionsnummer jetzt unten in den Einstellungen an.'
  where title='Versionsnummer';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.1.0', status_updated_at=now(),
  resolution='Zwei Verbesserungen: 1) Landet ein Barcode auf einem falschen Produkt, laesst er sich ueber "Andere Zuordnung" (Symbol oben rechts auf der Bestandserfassung) jederzeit neu verknuepfen. 2) Die Produktsuche laeuft jetzt automatisch mit dem von Open Food Facts gelieferten Namen und zeigt zusaetzlich zuletzt aus Bons angelegte, noch nicht verknuepfte Produkte an, damit meist gar nicht mehr getippt werden muss.'
  where title='Keine Bonzuordnung';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.1.0', status_updated_at=now(),
  resolution='Die automatische Zuordnung ueber Open Food Facts trifft nur zu, wenn OFF denselben oder einen sehr aehnlichen Namen fuehrt wie der Bon - bei Handelsmarken (Clever, DKIH ...) ist das selten der Fall, daher blieb der Haken meist aus. Neu: die Suche laeuft automatisch beim Oeffnen mit, und zusaetzlich wird eine Liste "zuletzt aus Bons, noch ohne Barcode" angeboten, sodass in der Regel kein eigenes Tippen mehr noetig ist.'
  where title='Automatische Bonzuordnung';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.1.0', status_updated_at=now(),
  resolution='Nach einem Wisch (aufgebraucht/weggeworfen) erscheint sofort eine "Rueckgaengig"-Schaltflaeche, die den Eintrag wieder aktiv macht und die Abgangsbuchung entfernt.'
  where title='Rückgängigmachen von aufgebrauchten Artikel';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.1.0', status_updated_at=now(),
  resolution='Loeschen eines Inventar-Eintrags, der aus einem Bon stammt, macht ihn jetzt wieder zum Bon-Vorschlag (statt ihn ganz zu entfernen), die Kaufbewegung des Bons bleibt dabei erhalten.'
  where title='Rückgängigmachen Bonartikel';

insert into app_changelog (version, title, highlights, released_at) values
  ('1.0.1', 'Sync-Fehler und erste Korrekturen',
   '["Synchronisierung haengt nicht mehr an gelernten Produktzuordnungen fest", "Bestandsmenge: Einheit (Stueck/kg/l) waehlbar, fuer das Produkt merkbar", "Inventar-Eintrag loeschen (falsch erfasst)"]'::jsonb,
   '2026-09-27 16:00:00+00'),
  ('1.1.0', 'Fehlerverfolgung, Changelog und mehr Kontrolle im Inventar',
   '["Fehlerberichte haben jetzt einen Bearbeitungsstatus (Gemeldet/Bestaetigt/In Bearbeitung/Behoben/...) und eine Loesungsnotiz", "Aenderungsprotokoll der App unter Einstellungen", "Versionsnummer wird in den Einstellungen angezeigt", "Barcode laesst sich ueber \"Andere Zuordnung\" neu verknuepfen", "Produktsuche beim Scan laeuft automatisch, plus Vorschlagsliste unverknuepfter Bon-Produkte", "Rueckgaengig-Schaltflaeche direkt nach Aufgebraucht/Weggeworfen", "Geloeschter Bon-Artikel wird wieder zum Vorschlag statt zu verschwinden"]'::jsonb,
   now());
