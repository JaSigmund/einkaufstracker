-- Herkunft der Naehrwerte je Zutat und Produkt (Phase N1, ADR-031).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/22 Konzept Naehrwert-Abdeckung.md §3.6 und §3.7
--
--   products.bls_code            Mit welchem BLS-Eintrag ist das Produkt verknuepft (Naehrwerte stehen als Snapshot in
--                                nutrients_per_100, nutrients_source = 'bls')
--   meal_ingredients.bls_code    Aus welchem BLS-Eintrag stammen die Naehrwerte dieser Zutat (fuer die Anzeige und spaeteres
--                                Neuberechnen)
--   meal_ingredients.nutrient_basis  Wie sicher: product (Naehrwerte des Produkts, z.B. Open Food Facts), bls_exact (vom Nutzer
--                                bestaetigt oder ueber Gedaechtnis/Synonym sicher), bls_matched (automatisch zugeordnet, in der
--                                App mit ~ markiert), llm_estimate (reserviert), manual (von Hand), unknown
alter table public.products
  add column bls_code text references public.bls_foods(bls_code) on delete set null;

alter table public.meal_ingredients
  add column bls_code text references public.bls_foods(bls_code) on delete set null,
  add column nutrient_basis text check (nutrient_basis in ('product', 'bls_exact', 'bls_matched', 'llm_estimate', 'manual', 'unknown'));
