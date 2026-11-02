-- Ledger: eine Bewegung, die auf 0 rundet, ist erlaubt
--
-- quantity_delta ist numeric(10,3). Bis 1.16 buchte die App auch Mahlzeit-Abzuege unter einem halben Gramm oder Milliliter
-- (InventoryRepository, _round3): lokal -0.0, am Server 0. Der Check verlangte fuer 'meal', 'consumed' und 'discarded' echt < 0 und
-- fuer 'purchase' echt > 0, die Zeile scheiterte mit 23514 und blieb fuer immer in der Outbox (Fehlerbericht vom 2026-11-02: zwei
-- Zeilen, je rund 1.500 Versuche).
--
-- Die App legt solche Zeilen ab 1.17 nicht mehr an. Die Regel wird trotzdem hier gelockert: so gehen auch die Zeilen durch, die schon in
-- einer Outbox warten. Eine Bewegung mit 0 aendert keine Summe, das falsche Vorzeichen bleibt verboten.

alter table public.inventory_movements drop constraint inventory_movements_check;
alter table public.inventory_movements add constraint inventory_movements_check check (
  (type = 'purchase' and quantity_delta >= 0)
  or (type in ('consumed', 'meal', 'discarded') and quantity_delta <= 0)
  or type = 'adjustment'
);
