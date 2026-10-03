-- Stueckgewichte und Haushaltsmasse (Phase N2, ADR-033).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/22 Konzept Naehrwert-Abdeckung.md §5
--
--   food_units                        Referenztabelle (global, nur lesbar fuer angemeldete Nutzer wie bls_foods): wie viel wiegt
--                                     "1 Stueck", "1 Scheibe", "1 EL" eines BLS-Lebensmittels. Die BLS kennt nur Werte je 100 g.
--                                     Gewichte gelten fuer den ESSBAREN Anteil (Banane ohne Schale), genau worauf sich die
--                                     Naehrwerte beziehen. Gefuellt aus tools/food_units_import.sql.
--   household_food_links.unit_weight_g  Das eigene Gewicht von 1 Stueck, wenn der Haushalt es einmal angegeben hat. Es geht
--                                     jedem Tabellenwert vor.
--
-- unit_key: piece (Stueck), slice (Scheibe), tbsp (EL), tsp (TL), clove (Zehe), head (Kopf), stalk (Stange)
-- size:     '' (ohne Groessenangabe) oder small / medium / large, nur bei piece, head und stalk
-- source:   usda (Gewicht unveraendert aus USDA FoodData Central), off (Packungsangabe), curated (umgerechnet, z.B.
--           Schaelverlust), llm_estimate (KI-Schaetzung, in der App erkennbar)
create table public.food_units (
  bls_code     text not null references public.bls_foods(bls_code) on delete cascade,
  unit_key     text not null check (unit_key in ('piece', 'slice', 'tbsp', 'tsp', 'clove', 'head', 'stalk')),
  size         text not null default '' check (size in ('', 'small', 'medium', 'large')),
  grams_edible numeric(8, 2) not null check (grams_edible > 0 and grams_edible <= 5000),
  grams_gross  numeric(8, 2) check (grams_gross is null or (grams_gross > 0 and grams_gross <= 5000)),
  source       text not null check (source in ('usda', 'off', 'curated', 'llm_estimate')),
  note         text,
  primary key (bls_code, unit_key, size)
);
alter table public.food_units enable row level security;
create policy food_units_read on public.food_units for select using (auth.role() = 'authenticated');

alter table public.household_food_links
  add column unit_weight_g numeric(8, 2) check (unit_weight_g is null or (unit_weight_g > 0 and unit_weight_g <= 5000));
