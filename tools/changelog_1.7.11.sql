insert into app_changelog (version, title, highlights, released_at) values
  ('1.7.11', 'Produkt-Duplikate vermeiden',
   '[
     "Fehler behoben: ein einzelnes OCR-Leerzeichen oder ein Tippfehler bei einer Bon-Position legte bisher ein doppeltes Produkt an, statt dem bestehenden zugeordnet zu werden",
     "Neu: \"Meine Produkte\" zeigt moegliche Duplikate als Vorschlag mit direkter Zusammenfuehren-Option"
   ]'::jsonb,
   now());
