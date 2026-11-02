-- Haushaltseinheit einer Zutat (Phase N2, ADR-033): "2 Scheiben" statt "2 Stk".
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md, ADR-033
--
--   meal_ingredients.unit_key   Einheit einer Stueckmenge, Werte wie food_units.unit_key. Scheibe, EL und Co. zaehlen Teile eines Stuecks:
--                               Der Bestandsabzug von Stueckware rechnet dann ueber das Stueckgewicht des Produkts. Ohne die Spalte kam beim
--                               Bearbeiten "2 Stk" zurueck, und das Speichern buchte 2 ganze Stueck ab. Leer = ganze Stueck, keine Stueckmenge
--                               oder Zeile aus einer aelteren Version.
alter table public.meal_ingredients
  add column unit_key text check (unit_key is null or unit_key in ('piece', 'slice', 'tbsp', 'tsp', 'clove', 'head', 'stalk'));
