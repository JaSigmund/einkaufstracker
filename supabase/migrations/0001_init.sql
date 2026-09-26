-- Einkaufstracker: Initiales Schema
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/04 Datenmodell.md
-- Konventionen: Geld in Cent (integer), Zeit in timestamptz (UTC), Datum ohne Zeit als date,
-- IDs als uuid (clientseitig erzeugbar), Soft-Delete ueber deleted_at, jede Fachtabelle hat household_id.


-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.member_role      as enum ('owner', 'member');
create type public.receipt_status   as enum ('pending', 'draft', 'confirmed');
create type public.ocr_source       as enum ('on_device', 'llm', 'manual');
create type public.item_kind        as enum ('article', 'deposit', 'discount');
create type public.inventory_status as enum ('sealed', 'opened', 'consumed', 'discarded');
create type public.date_kind        as enum ('best_before', 'use_by');
create type public.storage_location as enum ('fridge', 'freezer', 'pantry', 'other');
create type public.base_unit        as enum ('kg', 'l', 'piece');
create type public.list_source      as enum ('manual', 'expiring', 'depleted', 'recurring', 'scan');

-- ---------------------------------------------------------------------------
-- Haushalte und Mitglieder
-- ---------------------------------------------------------------------------
create table public.households (
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'Mein Haushalt',
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         public.member_role not null default 'member',
  created_at   timestamptz not null default now(),
  primary key (household_id, user_id)
);
create index on public.household_members (user_id);

-- Mitgliedschaftspruefung fuer RLS (security definer, damit keine Rekursion ueber RLS entsteht)
create or replace function public.is_household_member(hid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = hid and m.user_id = auth.uid()
  );
$$;

-- Bei Registrierung automatisch Haushalt + Mitgliedschaft anlegen
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  hid uuid;
begin
  insert into public.households (name) values ('Mein Haushalt') returning id into hid;
  insert into public.household_members (household_id, user_id, role) values (hid, new.id, 'owner');
  insert into public.categories (household_id, name, icon, sort_order, is_storable, parent_id)
    select hid, c.name, c.icon, c.sort_order, c.is_storable, null
    from public.default_categories c;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Kategorien (pro Haushalt kopiert, damit anpassbar; Vorlage in default_categories)
-- ---------------------------------------------------------------------------
create table public.default_categories (
  id          serial primary key,
  name        text not null unique,
  icon        text,
  sort_order  int  not null default 0,
  is_storable boolean not null default true
);

create table public.categories (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  parent_id    uuid references public.categories(id) on delete set null,
  name         text not null,
  icon         text,
  sort_order   int  not null default 0,
  is_storable  boolean not null default true,  -- erzeugt Inventarvorschlaege aus Bons (FR-09)
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (household_id, name)
);
create index on public.categories (household_id);

-- ---------------------------------------------------------------------------
-- Haendler
-- ---------------------------------------------------------------------------
create table public.stores (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  chain        text not null,               -- 'Billa', 'Billa Plus', 'Hofer', ...
  branch       text,                        -- Filiale, optional
  detect_hints text[] not null default '{}',-- Schluesselwoerter fuer Haendlererkennung im Bon-Kopf
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (household_id, chain, branch)
);
create index on public.stores (household_id);

-- ---------------------------------------------------------------------------
-- Produkte (kanonisch), Barcodes, Aliase
-- ---------------------------------------------------------------------------
create table public.products (
  id                       uuid primary key default gen_random_uuid(),
  household_id             uuid not null references public.households(id) on delete cascade,
  name                     text not null,                 -- kanonischer Name: "Paprika rot", "Vollmilch 3,5 %"
  brand                    text,
  category_id              uuid references public.categories(id) on delete set null,
  base_unit                public.base_unit not null default 'piece',
  pack_size                numeric(10,3),                 -- Packungsgroesse in base_unit (z.B. 1 fuer 1 l, 0.5 fuer 500 g)
  sealed_shelf_life_days   int,                           -- Standard ab Kauf, falls kein MHD bekannt
  opened_shelf_life_days   int,                           -- Standard nach dem Oeffnen
  default_date_kind        public.date_kind not null default 'best_before',
  default_location         public.storage_location not null default 'pantry',
  restock                  boolean not null default false,-- Nachkaufprodukt: Vorschlag auf Einkaufsliste
  off_code                 text,                          -- Open Food Facts Code
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz
);
create index on public.products (household_id);
create index on public.products (household_id, lower(name));

create table public.product_barcodes (
  household_id uuid not null references public.households(id) on delete cascade,
  ean          text not null check (ean ~ '^[0-9]{8,14}$'),
  product_id   uuid not null references public.products(id) on delete cascade,
  updated_at   timestamptz not null default now(),
  primary key (household_id, ean)
);
create index on public.product_barcodes (product_id);

-- Bon-Text (normalisiert) -> Produkt, je Haendler; Basis fuer Lernen (FR-08)
create table public.product_aliases (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  store_id     uuid references public.stores(id) on delete cascade,   -- null = haendlerunabhaengig
  alias_text   text not null,                                          -- normalisiert: lower, ohne Ziffernrauschen
  product_id   uuid not null references public.products(id) on delete cascade,
  hits         int not null default 1,
  updated_at   timestamptz not null default now(),
  unique (household_id, store_id, alias_text)
);
create index on public.product_aliases (product_id);

-- ---------------------------------------------------------------------------
-- Bons
-- ---------------------------------------------------------------------------
create table public.receipts (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  store_id      uuid references public.stores(id) on delete set null,
  purchased_at  timestamptz not null,
  total_cents   integer not null,
  status        public.receipt_status not null default 'draft',
  source        public.ocr_source not null default 'on_device',
  confidence    numeric(4,3),                     -- 0..1 Gesamtkonfidenz
  sum_mismatch  boolean not null default false,   -- Summe der Positionen != total_cents
  image_path    text,                             -- Storage-Pfad, optional
  raw_ocr_text  text,                             -- fuer Debugging/Golden Set, optional
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.receipts (household_id, purchased_at desc);
-- Duplikaterkennung (REC-08): gleicher Haendler, Zeitpunkt, Summe
create unique index receipts_dedupe on public.receipts (household_id, store_id, purchased_at, total_cents)
  where deleted_at is null and status = 'confirmed';

create table public.receipt_items (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references public.households(id) on delete cascade,
  receipt_id       uuid not null references public.receipts(id) on delete cascade,
  line_no          int  not null,
  kind             public.item_kind not null default 'article',
  raw_text         text not null,
  product_id       uuid references public.products(id) on delete set null,
  category_id      uuid references public.categories(id) on delete set null,
  brand            text,
  quantity         numeric(10,3) not null default 1,
  quantity_unit    public.base_unit not null default 'piece',   -- Einheit der Menge (kg bei Waage)
  unit_price_cents integer,                                      -- Preis je quantity_unit
  line_total_cents integer not null,                             -- negativ bei Rabatt
  unit_price_norm_cents integer,                                 -- Grundpreis je base_unit, berechnet (FR-06)
  confidence       numeric(4,3),
  needs_review     boolean not null default false,
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create index on public.receipt_items (receipt_id, line_no);
create index on public.receipt_items (household_id, product_id);
create index on public.receipt_items (household_id, category_id);

-- ---------------------------------------------------------------------------
-- Inventar
-- ---------------------------------------------------------------------------
create table public.inventory_items (
  id                     uuid primary key default gen_random_uuid(),
  household_id           uuid not null references public.households(id) on delete cascade,
  product_id             uuid not null references public.products(id) on delete restrict,
  receipt_item_id        uuid references public.receipt_items(id) on delete set null,
  ean                    text,
  quantity               numeric(10,3) not null default 1,
  unit                   public.base_unit not null default 'piece',
  location               public.storage_location not null default 'pantry',
  purchased_on           date,
  best_before            date,
  date_kind              public.date_kind not null default 'best_before',
  opened_on              date,
  open_shelf_life_days   int,
  status                 public.inventory_status not null default 'sealed',
  is_suggestion          boolean not null default false,   -- aus Bon vorgeschlagen, noch nicht per Scan bestaetigt (INV-08)
  closed_at              timestamptz,                      -- aufgebraucht/weggeworfen
  -- Ablaufdatum (FR-03): frueheres aus MHD und Oeffnungsfrist; least() ignoriert NULLs
  expires_on date generated always as (
    case
      when opened_on is not null and open_shelf_life_days is not null
        then least(best_before, opened_on + open_shelf_life_days)
      else best_before
    end
  ) stored,
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz
);
create index on public.inventory_items (household_id, status, expires_on);
create index on public.inventory_items (household_id, product_id);

-- ---------------------------------------------------------------------------
-- Einkaufsliste
-- ---------------------------------------------------------------------------
create table public.shopping_lists (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name         text not null default 'Einkaufsliste',
  is_default   boolean not null default true,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on public.shopping_lists (household_id);

create table public.shopping_list_items (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  list_id      uuid not null references public.shopping_lists(id) on delete cascade,
  product_id   uuid references public.products(id) on delete set null,
  free_text    text,
  quantity     numeric(10,3) not null default 1,
  unit         public.base_unit not null default 'piece',
  checked      boolean not null default false,
  source       public.list_source not null default 'manual',
  is_suggestion boolean not null default false,     -- wartet auf Bestaetigung (SHO-03)
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  check (product_id is not null or free_text is not null)
);
create index on public.shopping_list_items (list_id);

-- ---------------------------------------------------------------------------
-- Einstellungen und Nutzungsprotokoll
-- ---------------------------------------------------------------------------
create table public.household_settings (
  household_id           uuid primary key references public.households(id) on delete cascade,
  notify_time            time not null default '07:30',
  notify_lead_days       int  not null default 1,
  warn_yellow_days       int  not null default 2,
  allow_cloud_ocr        boolean not null default false,  -- Einwilligung (NF-07)
  keep_receipt_images    boolean not null default true,
  monthly_budget_cents   integer,
  updated_at             timestamptz not null default now()
);

create table public.llm_usage (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  receipt_id    uuid references public.receipts(id) on delete set null,
  model         text not null,
  input_tokens  int  not null,
  output_tokens int  not null,
  cost_micro_usd bigint,                 -- Kosten in Mikro-USD (Umrechnung in EUR bei Auswertung)
  duration_ms   int,
  created_at    timestamptz not null default now()
);
create index on public.llm_usage (household_id, created_at desc);

-- ---------------------------------------------------------------------------
-- updated_at automatisch pflegen
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'categories','stores','products','product_barcodes','product_aliases','receipts',
    'receipt_items','inventory_items','shopping_lists','shopping_list_items','household_settings'
  ] loop
    execute format(
      'create trigger trg_touch_%1$s before update on public.%1$s
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Row Level Security: alles nur fuer Mitglieder des jeweiligen Haushalts
-- ---------------------------------------------------------------------------
alter table public.households          enable row level security;
alter table public.household_members   enable row level security;
alter table public.categories          enable row level security;
alter table public.stores              enable row level security;
alter table public.products            enable row level security;
alter table public.product_barcodes    enable row level security;
alter table public.product_aliases     enable row level security;
alter table public.receipts            enable row level security;
alter table public.receipt_items       enable row level security;
alter table public.inventory_items     enable row level security;
alter table public.shopping_lists      enable row level security;
alter table public.shopping_list_items enable row level security;
alter table public.household_settings  enable row level security;
alter table public.llm_usage           enable row level security;
alter table public.default_categories  enable row level security;

create policy households_select on public.households
  for select using (public.is_household_member(id));
create policy households_update on public.households
  for update using (public.is_household_member(id));

create policy members_select on public.household_members
  for select using (user_id = auth.uid() or public.is_household_member(household_id));

create policy default_categories_read on public.default_categories
  for select using (auth.role() = 'authenticated');

-- Standard-Policy fuer alle Fachtabellen mit household_id
do $$
declare t text;
begin
  foreach t in array array[
    'categories','stores','products','product_barcodes','product_aliases','receipts',
    'receipt_items','inventory_items','shopping_lists','shopping_list_items','household_settings'
  ] loop
    execute format(
      'create policy %1$s_all on public.%1$s
         for all
         using (public.is_household_member(household_id))
         with check (public.is_household_member(household_id))', t);
  end loop;
end $$;

-- llm_usage: Mitglieder duerfen lesen, geschrieben wird nur von der Edge Function (service role)
create policy llm_usage_select on public.llm_usage
  for select using (public.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- Trigger auf auth.users (Signup -> Haushalt)
-- ---------------------------------------------------------------------------
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Storage: privater Bucket fuer Bon-Fotos, Pfad {household_id}/{receipt_id}.jpg
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('receipts', 'receipts', false)
on conflict (id) do nothing;

create policy receipts_storage_rw on storage.objects
  for all to authenticated
  using (
    bucket_id = 'receipts'
    and public.is_household_member(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'receipts'
    and public.is_household_member(((storage.foldername(name))[1])::uuid)
  );

-- ---------------------------------------------------------------------------
-- Auswertungs-Views (security_invoker: RLS des Aufrufers gilt)
-- Monatsgrenzen in Europe/Vienna (FR-07)
-- ---------------------------------------------------------------------------
create or replace view public.v_monthly_spend_by_category
with (security_invoker = true) as
select
  r.household_id,
  date_trunc('month', r.purchased_at at time zone 'Europe/Vienna')::date as month,
  coalesce(i.category_id, p.category_id)                                  as category_id,
  sum(i.line_total_cents)                                                 as spend_cents,
  count(*)                                                                as positions
from public.receipt_items i
join public.receipts r on r.id = i.receipt_id
left join public.products p on p.id = i.product_id
where r.status = 'confirmed' and r.deleted_at is null and i.deleted_at is null
group by 1, 2, 3;

create or replace view public.v_monthly_spend_by_product
with (security_invoker = true) as
select
  r.household_id,
  date_trunc('month', r.purchased_at at time zone 'Europe/Vienna')::date as month,
  i.product_id,
  sum(i.quantity)            as quantity,
  sum(i.line_total_cents)    as spend_cents,
  count(*)                   as purchases
from public.receipt_items i
join public.receipts r on r.id = i.receipt_id
where r.status = 'confirmed' and r.deleted_at is null and i.deleted_at is null
  and i.kind = 'article' and i.product_id is not null
group by 1, 2, 3;

-- Preisverlauf und Haendlervergleich: Grundpreis je Kauf
create or replace view public.v_price_history
with (security_invoker = true) as
select
  r.household_id,
  i.product_id,
  r.store_id,
  (r.purchased_at at time zone 'Europe/Vienna')::date as day,
  i.unit_price_norm_cents,
  i.quantity_unit,
  i.brand
from public.receipt_items i
join public.receipts r on r.id = i.receipt_id
where r.status = 'confirmed' and r.deleted_at is null and i.deleted_at is null
  and i.kind = 'article' and i.product_id is not null and i.unit_price_norm_cents is not null;

create or replace view public.v_store_price_comparison
with (security_invoker = true) as
select
  h.household_id,
  h.product_id,
  h.store_id,
  count(*)                                              as samples,
  round(avg(h.unit_price_norm_cents))::int              as avg_norm_cents,
  min(h.unit_price_norm_cents)                          as min_norm_cents,
  max(h.day)                                            as last_seen
from public.v_price_history h
where h.day >= (current_date - interval '180 days')
group by 1, 2, 3;

-- Bald ablaufende Inventarstuecke
create or replace view public.v_inventory_expiring
with (security_invoker = true) as
select
  i.*,
  (i.expires_on - current_date) as days_left
from public.inventory_items i
where i.deleted_at is null and i.status in ('sealed', 'opened') and i.expires_on is not null;
