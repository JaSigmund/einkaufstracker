-- Essenstagebuch, Rezepte, Naehrwerte (Phase 7a Fundament).
-- Vormals supabase/planned/meal_diary_draft.sql (seit Phase 3 als Entwurf getestet, unveraendert
-- eingespielt), jetzt ergaenzt um die globale BLS-Referenztabelle (bls_foods).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/15 Essenstagebuch und Naehrwerte.md

create type public.meal_type   as enum ('breakfast', 'lunch', 'dinner', 'snack', 'drink');
create type public.meal_source as enum ('manual', 'photo_ai', 'recipe');
create type public.ingredient_source as enum ('inventory', 'photo_ai', 'recipe', 'manual', 'estimate');

-- Rezepte (wiederverwendbare Gerichte)
create table public.recipes (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name         text not null,
  servings     numeric(6,2) not null default 1 check (servings > 0),  -- Ergiebigkeit in Portionen
  photo_path   text,
  note         text,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on public.recipes (household_id);

create table public.recipe_ingredients (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  recipe_id    uuid not null references public.recipes(id) on delete cascade,
  product_id   uuid references public.products(id) on delete set null,
  free_text    text,
  quantity     numeric(10,3) not null,
  unit         public.base_unit not null,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  check (product_id is not null or free_text is not null)
);
create index on public.recipe_ingredients (recipe_id);

-- Mahlzeiten (Tagebucheintraege)
create table public.meals (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  eaten_at      timestamptz not null,
  meal_type     public.meal_type not null default 'lunch',
  title         text not null,
  note          text,
  photo_path    text,                                   -- Storage: meals/{household_id}/{meal_id}.jpg
  recipe_id     uuid references public.recipes(id) on delete set null,
  servings_eaten numeric(6,2) not null default 1 check (servings_eaten > 0),  -- Anteil, der von DIR gegessen wurde
  servings_made  numeric(6,2) not null default 1 check (servings_made > 0),   -- insgesamt zubereitete Portionen
  source        public.meal_source not null default 'manual',
  is_estimate   boolean not null default false,         -- Zutaten nur geschaetzt (z.B. Restaurant)
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.meals (household_id, eaten_at desc);

-- Zutaten je Mahlzeit; Naehrwerte sind ein Snapshot zum Erfassungszeitpunkt (Produktdaten aendern sich)
create table public.meal_ingredients (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references public.households(id) on delete cascade,
  meal_id           uuid not null references public.meals(id) on delete cascade,
  product_id        uuid references public.products(id) on delete set null,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  free_text         text,
  quantity          numeric(10,3) not null,
  unit              public.base_unit not null,
  amount_g          numeric(10,2),                      -- normalisiert in g bzw. ml (Basis der Naehrwertrechnung)
  source            public.ingredient_source not null default 'manual',
  confidence        numeric(4,3),
  kcal              numeric(8,2),
  protein_g         numeric(8,2),
  fat_g             numeric(8,2),
  carbs_g           numeric(8,2),
  sugar_g           numeric(8,2),
  fiber_g           numeric(8,2),
  salt_g            numeric(8,3),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check (product_id is not null or free_text is not null)
);
create index on public.meal_ingredients (meal_id);
create index on public.meal_ingredients (household_id, product_id);

-- Tagesziele (Richtwerte, keine medizinische Empfehlung)
create table public.nutrition_targets (
  household_id uuid primary key references public.households(id) on delete cascade,
  targets      jsonb not null default '{}',             -- {kcal:{min,max}, protein_g:{min}, ...}
  updated_at   timestamptz not null default now()
);

-- Bewegungen duerfen jetzt auf Mahlzeiten zeigen
alter table public.inventory_movements
  add constraint inventory_movements_meal_fk foreign key (meal_id) references public.meals(id) on delete set null;

-- RLS und updated_at
do $$
declare t text;
begin
  foreach t in array array['recipes','recipe_ingredients','meals','meal_ingredients','nutrition_targets'] loop
    execute format('alter table public.%1$s enable row level security', t);
    execute format(
      'create policy %1$s_all on public.%1$s for all
         using (public.is_household_member(household_id))
         with check (public.is_household_member(household_id))', t);
    execute format(
      'create trigger trg_touch_%1$s before update on public.%1$s
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- Storage-Bucket fuer Essensfotos
insert into storage.buckets (id, name, public) values ('meals', 'meals', false) on conflict (id) do nothing;
create policy meals_storage_rw on storage.objects
  for all to authenticated
  using (bucket_id = 'meals' and public.is_household_member(((storage.foldername(name))[1])::uuid))
  with check (bucket_id = 'meals' and public.is_household_member(((storage.foldername(name))[1])::uuid));

-- Tages-Naehrwerte: Summe der Zutaten, gewichtet mit dem Anteil, den der Nutzer gegessen hat
create or replace view public.v_daily_nutrition
with (security_invoker = true) as
select
  m.household_id,
  (m.eaten_at at time zone 'Europe/Vienna')::date as day,
  round(sum(i.kcal      * m.servings_eaten / m.servings_made), 1) as kcal,
  round(sum(i.protein_g * m.servings_eaten / m.servings_made), 1) as protein_g,
  round(sum(i.fat_g     * m.servings_eaten / m.servings_made), 1) as fat_g,
  round(sum(i.carbs_g   * m.servings_eaten / m.servings_made), 1) as carbs_g,
  round(sum(i.sugar_g   * m.servings_eaten / m.servings_made), 1) as sugar_g,
  round(sum(i.fiber_g   * m.servings_eaten / m.servings_made), 1) as fiber_g,
  round(sum(i.salt_g    * m.servings_eaten / m.servings_made), 2) as salt_g,
  count(distinct m.id)                                             as meals,
  bool_or(m.is_estimate)                                           as has_estimates
from public.meals m
join public.meal_ingredients i on i.meal_id = m.id and i.deleted_at is null
where m.deleted_at is null
group by 1, 2;

create or replace view public.v_weekly_nutrition
with (security_invoker = true) as
select
  household_id,
  date_trunc('week', day)::date as week,
  round(avg(kcal), 0)      as avg_kcal_per_day,
  round(avg(protein_g), 1) as avg_protein_g,
  round(avg(fat_g), 1)     as avg_fat_g,
  round(avg(carbs_g), 1)   as avg_carbs_g,
  round(avg(fiber_g), 1)   as avg_fiber_g,
  round(avg(salt_g), 2)    as avg_salt_g,
  count(*)                 as days_logged
from public.v_daily_nutrition
group by 1, 2;

-- ---------------------------------------------------------------------------
-- Bundeslebensmittelschluessel (BLS) 4.0: globale, schreibgeschuetzte Referenztabelle fuer
-- generische Lebensmittel ohne Barcode (Paprika, Reis roh, ...), je 100 g/ml wie im Original.
-- Lizenz CC BY 4.0, Pflicht-Namensnennung: "Max Rubner-Institut (2025): Bundeslebensmittelschluessel
-- (BLS), Version 4.0 -- Deutsche Naehrstoffdatenbank". bls_code ist der stabile externe Schluessel
-- (siehe tools/import_bls_foods.py), bewusst keine surrogate uuid, damit ein spaeterer Re-Import
-- (neue BLS-Version) dieselben Zeilen per on conflict aktualisiert statt zu duplizieren.
-- Gleiches Zugriffsmuster wie default_categories/app_config: lesbar fuer alle angemeldeten Nutzer,
-- kein Insert/Update/Delete fuer Clients -- Pflege ausschliesslich von Hand ueber tools/bls_foods_import.sql.
-- ---------------------------------------------------------------------------
create table public.bls_foods (
  bls_code    text primary key,
  name_de     text not null,
  name_en     text,
  kcal        numeric(8,2),
  protein_g   numeric(8,2),
  fat_g       numeric(8,2),
  sat_fat_g   numeric(8,2),
  carbs_g     numeric(8,2),
  sugar_g     numeric(8,2),
  fiber_g     numeric(8,2),
  salt_g      numeric(8,3),
  imported_at timestamptz not null default now()
);
create index on public.bls_foods (lower(name_de));

alter table public.bls_foods enable row level security;
create policy bls_foods_read on public.bls_foods
  for select using (auth.role() = 'authenticated');
