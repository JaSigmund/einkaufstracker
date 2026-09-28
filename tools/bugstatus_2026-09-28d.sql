update bug_reports set status='fixed', severity='medium', fixed_in_version='1.7.1', status_updated_at=now(),
  resolution='computeUnitPriceNormCents wendet packSize jetzt auch an, wenn die Basiseinheit selbst "piece" ist. Eine 4er-Packung wird auf den Preis je einzelnem Stueck heruntergerechnet statt auf den Packungspreis.'
  where id='878e673d-64e0-45c7-a87d-a1e86914e105';

update bug_reports set status='fixed', severity='medium', fixed_in_version='1.7.1', status_updated_at=now(),
  resolution='Bon loeschen verwirft jetzt auch die noch unbestaetigten Inventar-Vorschlaege der geloeschten Positionen. Ein erneuter Import erzeugt dadurch keinen doppelten Vorschlag mehr; bereits bestaetigte Inventar-Eintraege bleiben unangetastet.'
  where id='5b9812f2-9ad7-455d-894e-c3205cb3ebb0';

update bug_reports set status='fixed', severity='low', fixed_in_version='1.7.1', status_updated_at=now(),
  resolution='Die Monatsauswertung zeigt jetzt den Produktnamen statt des rohen Bon-Texts und gruppiert nach der Produkt-Zuordnung statt nach normalisiertem Bon-Text, damit unterschiedlich geschriebene Positionen desselben Produkts (z.B. je Haendler) zusammengefasst werden.'
  where id='debe71c9-95bc-42e4-8fe6-1957bfac3f01';
