-- Mikronaehrstoffe (Phase N3, ADR-032).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/22 Konzept Naehrwert-Abdeckung.md §4
--
--   bls_foods.nutrients          die 38 Werte je 100 g als jsonb mit festen Schluesseln (Register: tools/nutrient_registry.json),
--                                Einheit steht im Schluessel (vit_c_mg, iodine_ug ...). Ein FEHLENDER Schluessel heisst unbekannt,
--                                0 ist eine echte Null (die BLS trennt beides selbst). Gefuellt aus tools/bls_nutrients_import.sql.
--   meal_ingredients.micros      dieselben Schluessel als ABSOLUTE Mengen fuer die verzehrte Menge (Snapshot wie die acht
--                                Makrospalten); null = Zutat ohne Mikronaehrstoffdaten
--   search_bls_foods             liefert zusaetzlich `nutrients`, damit die App und die Edge Function die Werte gleich
--                                mitbekommen. Die Suche selbst (Wertung, Gedaechtnis, Synonyme) ist unveraendert: die alte Fassung
--                                bleibt als search_bls_foods_base bestehen, die neue haengt nur die Spalte an.
--   products.nutrients_per_100   ist schon jsonb und nimmt die zusaetzlichen Schluessel ohne Migration auf.
alter table public.bls_foods
  add column nutrients jsonb check (nutrients is null or jsonb_typeof(nutrients) = 'object');

alter table public.meal_ingredients
  add column micros jsonb check (micros is null or jsonb_typeof(micros) = 'object');

alter function public.search_bls_foods(text, integer, uuid, boolean) rename to search_bls_foods_base;

create function public.search_bls_foods(
  q text,
  n integer default 8,
  p_household uuid default null,
  p_loose boolean default false
)
returns table (
  bls_code text, name_de text, score numeric, method text, rank integer, confidence text, coverage numeric,
  kcal numeric, protein_g numeric, fat_g numeric, sat_fat_g numeric, carbs_g numeric, sugar_g numeric, fiber_g numeric, salt_g numeric,
  nutrients jsonb
)
language sql stable security invoker
set search_path = public
as $$
  select s.bls_code, s.name_de, s.score, s.method, s.rank, s.confidence, s.coverage,
         s.kcal, s.protein_g, s.fat_g, s.sat_fat_g, s.carbs_g, s.sugar_g, s.fiber_g, s.salt_g,
         b.nutrients
  from public.search_bls_foods_base(q, n, p_household, p_loose) s
  join public.bls_foods b on b.bls_code = s.bls_code
  order by s.rank;
$$;
