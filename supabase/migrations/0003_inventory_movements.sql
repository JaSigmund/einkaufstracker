-- Inventarbewegungen (Ledger) und Naehrwert-Vorbereitung am Produkt.
-- Grund: Die Verbrauchsbilanz (siehe Doku 15 Essenstagebuch und Naehrwerte, §4) braucht die
-- Historie aller Bestandsaenderungen. Wer erst spaeter mit dem Protokollieren beginnt, hat fuer
-- die Vergangenheit keine Daten. Deshalb gehoert das Ledger schon in den MVP (Phase 3).

create type public.movement_type as enum (
  'purchase',   -- Zugang durch Einkauf (+)
  'consumed',   -- manuell als aufgebraucht markiert (-)
  'meal',       -- durch Essenstagebuch verbraucht (-), ab Phase 7
  'discarded',  -- weggeworfen (-)
  'adjustment'  -- Korrektur/Inventur (+/-)
);

create table public.inventory_movements (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references public.households(id) on delete cascade,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  product_id        uuid not null references public.products(id) on delete restrict,
  occurred_at       timestamptz not null default now(),
  type              public.movement_type not null,
  quantity_delta    numeric(10,3) not null,             -- Vorzeichen: Zugang +, Abgang -
  unit              public.base_unit not null,          -- Einheit von quantity_delta
  meal_id           uuid,                               -- FK auf meals kommt mit Phase 7
  note              text,
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check (
    (type = 'purchase' and quantity_delta > 0)
    or (type in ('consumed', 'meal', 'discarded') and quantity_delta < 0)
    or type = 'adjustment'
  )
);
create index on public.inventory_movements (household_id, occurred_at desc);
create index on public.inventory_movements (household_id, product_id, occurred_at);
create index on public.inventory_movements (inventory_item_id);

alter table public.inventory_movements enable row level security;
create policy inventory_movements_all on public.inventory_movements
  for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_inventory_movements before update on public.inventory_movements
  for each row execute function public.touch_updated_at();

-- Naehrwert- und Umrechnungsdaten am Produkt. Werden schon im MVP beim Barcode-Scan aus
-- Open Food Facts mitgespeichert (kostet nichts), genutzt erst ab Phase 7.
alter table public.products
  add column nutrients_per_100 jsonb,       -- je 100 g bzw. 100 ml: {kcal, protein_g, fat_g, sat_fat_g, carbs_g, sugar_g, fiber_g, salt_g}
  add column nutrients_basis   text check (nutrients_basis in ('g', 'ml')),
  add column nutrients_source  text,        -- 'off', 'usda', 'manual', 'llm_estimate'
  add column unit_weight_g     numeric(8,2),-- Gewicht eines Stuecks in g (Paprika ~ 150), fuer Stk <-> g
  add check (nutrients_per_100 is null or nutrients_basis is not null);

-- Bestandsbilanz je Woche und Produkt (Grundlage der Verbrauchsbilanz, Doku 15 §4)
create or replace view public.v_weekly_stock_flow
with (security_invoker = true) as
select
  m.household_id,
  date_trunc('week', m.occurred_at at time zone 'Europe/Vienna')::date as week,
  m.product_id,
  m.unit,
  sum(m.quantity_delta) filter (where m.type = 'purchase')   as purchased,
  -sum(m.quantity_delta) filter (where m.type = 'meal')       as eaten,
  -sum(m.quantity_delta) filter (where m.type = 'consumed')   as consumed_manual,
  -sum(m.quantity_delta) filter (where m.type = 'discarded')  as discarded,
  sum(m.quantity_delta) filter (where m.type = 'adjustment')  as adjusted,
  sum(m.quantity_delta)                                       as net_change
from public.inventory_movements m
where m.deleted_at is null
group by 1, 2, 3, 4;
