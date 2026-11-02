-- Mehrfachpackungen (ADR-045): eine Packung Yakult ist eine Bon-Position, aber 6 Flaeschchen zu je 65 ml, die einzeln verbraucht werden.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md
--
-- pack_size bleibt der Gesamtinhalt einer Packung in base_unit (hier 0,39 l), Grundpreis und Naehrwerte rechnen also weiter richtig.
-- pieces_per_pack sagt nur, in wie viele Stuecke er sich teilt, und gilt fuer base_unit kg und l. Bei base_unit piece ist pack_size selbst
-- die Stueckzahl. piece_label ist der Name der Stuecke in der Mehrzahl, ohne Angabe zeigt die App "Stk".

alter table public.products
  add column pieces_per_pack integer check (pieces_per_pack >= 2),
  add column piece_label text check (length(trim(piece_label)) between 1 and 30);
