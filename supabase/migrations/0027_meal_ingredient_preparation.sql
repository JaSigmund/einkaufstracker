-- Garfaktoren (Phase N4, ADR-037): wie eine Zutat zubereitet wurde.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md, ADR-037
--
--   meal_ingredients.preparation   'kategorie:zubereitung', z.B. 'veg_other:boiled' (gekochtes Gemuese) oder 'beef:grilled'. Leer = roh oder
--                                  nicht angegeben. Ist es gesetzt, sind die Mikronaehrstoffe der Zeile (micros) schon um die typischen
--                                  Garverluste gemindert (USDA Table of Nutrient Retention Factors); die Faktoren stehen als Konstanten in
--                                  der App, nicht in der Datenbank. Die Spalte haelt fest, WAS gemindert wurde, damit eine spaetere
--                                  Bearbeitung nicht ein zweites Mal mindert.
alter table public.meal_ingredients
  add column preparation text check (preparation is null or preparation ~ '^[a-z_]+:(boiled|steamed|fried|baked|grilled)$');
