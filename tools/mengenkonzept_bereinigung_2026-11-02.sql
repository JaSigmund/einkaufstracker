-- Einmalige Bereinigung zum Mengenkonzept (ADR-045), nach Migration 0035 und vor dem Release von Hand einspielen.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md
--
-- Stand 2026-11-02, gemessen an den echten Daten:
--   1. Yakult Drink und die Cookies haben einen Inhalt in unklarer Einheit (base_unit piece, pack_size 0,39 bzw. 0,225).
--   2. Bestand in Stueck auf Produkten in kg oder l: 4 Bon-Vorschlaege (Packungen), dazu Yakult (6 Flaeschchen) und die Cookies (1 Packung).
-- Die Buchungen wandern mit, statt Korrekturen anzulegen: es ist dieselbe Ware, Bilanz und Vorhersage sollen keinen Zu- oder Abgang sehen.
-- Abgeschlossene Eintraege bleiben, wie sie sind. Mehrfach ausfuehrbar: was schon stimmt, trifft die Bedingungen nicht mehr.

begin;

-- 1. Produkte: Yakult ist eine Mehrfachpackung 6 x 65 ml, die Cookies eine Packung mit 225 g
update public.products
   set base_unit = 'l', pack_size = 0.39, pieces_per_pack = 6, piece_label = 'Fläschchen', unit_weight_g = 65
 where name = 'Yakult Drink' and base_unit = 'piece' and pack_size = 0.39 and deleted_at is null;

update public.products
   set base_unit = 'kg', pack_size = 0.225
 where name = 'clever chocolate chip cookies' and base_unit = 'piece' and pack_size = 0.225 and deleted_at is null;

-- 2. Bestand und Buchungen: Bon-Vorschlaege zaehlen Packungen, bestaetigter Bestand einer Mehrfachpackung zaehlt Stuecke
create temporary table _umrechnung on commit drop as
select i.id as item_id, p.base_unit,
       case when not i.is_suggestion and p.pieces_per_pack is not null then p.pack_size / p.pieces_per_pack else p.pack_size end as faktor
  from public.inventory_items i
  join public.products p on p.id = i.product_id
 where i.deleted_at is null
   and i.status in ('sealed', 'opened')
   and i.unit = 'piece'
   and p.base_unit in ('kg', 'l')
   and p.pack_size is not null;

update public.inventory_movements m
   set quantity_delta = round(m.quantity_delta * u.faktor, 3), unit = u.base_unit
  from _umrechnung u
 where m.inventory_item_id = u.item_id and m.unit = 'piece' and m.deleted_at is null;

update public.inventory_items i
   set quantity = round(i.quantity * u.faktor, 3), unit = u.base_unit
  from _umrechnung u
 where i.id = u.item_id;

commit;

-- Kontrolle: das Ergebnis der letzten Abfrage zeigt, was jetzt im Bestand steht und ob noch etwas abweicht
select p.name, i.quantity, i.unit, p.base_unit, p.pack_size, p.pieces_per_pack, i.is_suggestion
  from public.inventory_items i
  join public.products p on p.id = i.product_id
 where i.deleted_at is null and i.status in ('sealed', 'opened')
   and (p.name in ('Yakult Drink', 'clever chocolate chip cookies') or i.unit <> p.base_unit);
