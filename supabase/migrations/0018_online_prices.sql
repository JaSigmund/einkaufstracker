-- Online-Preise fuer den Haendlervergleich (ADR-019, Umsetzung 2026-10-02).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md (ADR-019), 07 Auswertung und Preisvergleich.md
--
-- Quelle ist der oeffentliche Feed von heisse-preise.io (Projekt badlogic/heissepreise, MIT-Lizenz). Die Edge Function
-- `refresh-online-prices` liest ihn taeglich abschnittsweise und schreibt nur Billa und Spar (die einzigen aktuell
-- gepflegten Haendler) in `online_prices`. Die App liest nie den Feed, nur diese Tabelle. Zuordnung zu eigenen
-- Produkten: `product_online_links`, vom Nutzer bestaetigt (kein automatisches Matching, der Feed hat keine EAN).

-- ---------------------------------------------------------------------------------------------------------------
-- online_prices: globale, schreibgeschuetzte Preis-Snapshots (kein Haushaltsbezug, wie bls_foods)
-- ---------------------------------------------------------------------------------------------------------------
create table public.online_prices (
  store                 text not null,                 -- 'billa' | 'spar' (Schluessel im Feed)
  external_id           text not null,                 -- haendlereigene Artikel-ID (Billa "00-600283", Spar "2020002600662")
  name                  text not null,
  price_cents           integer not null check (price_cents >= 0),
  quantity              numeric(12,3),                 -- Menge zur Einheit, null wenn der Feed keine liefert
  unit                  text,                          -- Feed-Einheit roh (g, kg, ml, l, stk, ...)
  base_unit             text check (base_unit in ('kg', 'l', 'stk')),  -- null bei unbekannter Einheit (z.B. Waschgaenge)
  unit_price_norm_cents integer,                       -- Cent je Basiseinheit, null wenn nicht berechenbar
  is_weighted           boolean not null default false,
  bio                   boolean not null default false,
  seen_at               timestamptz not null,          -- Lauf, in dem der Artikel zuletzt im Feed verfuegbar war
  primary key (store, external_id)
);
create index online_prices_name_fts on public.online_prices using gin (to_tsvector('simple', name));
create index online_prices_store_seen on public.online_prices (store, seen_at);

alter table public.online_prices enable row level security;
create policy online_prices_read on public.online_prices
  for select using (auth.role() = 'authenticated');

-- ---------------------------------------------------------------------------------------------------------------
-- online_feed_status: wie frisch ist der Feed, ging der letzte Lauf gut (eine Zeile je Quelle)
-- ---------------------------------------------------------------------------------------------------------------
create table public.online_feed_status (
  source             text primary key,                 -- 'heisse_preise'
  feed_etag          text,
  feed_last_modified timestamptz,                      -- Stand des Feeds selbst (Last-Modified), Basis von "Stand vom ..."
  last_attempt_at    timestamptz,
  last_success_at    timestamptz,
  running_since      timestamptz,                      -- gesetzt, solange ein Lauf laeuft (verhindert Doppelstart)
  last_error         text,
  row_counts         jsonb not null default '{}'
);

alter table public.online_feed_status enable row level security;
create policy online_feed_status_read on public.online_feed_status
  for select using (auth.role() = 'authenticated');

-- ---------------------------------------------------------------------------------------------------------------
-- product_online_links: "dieses Produkt entspricht diesem Online-Artikel" (je Haushalt, vom Nutzer bestaetigt)
-- ---------------------------------------------------------------------------------------------------------------
create table public.product_online_links (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  product_id   uuid not null references public.products(id) on delete cascade,
  store        text not null,
  external_id  text not null,
  linked_name  text not null,                          -- Name des Online-Artikels bei der Bestaetigung (Anzeige, falls er aus dem Feed verschwindet)
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
-- Ein Produkt hat je Haendler hoechstens einen aktiven Online-Artikel.
create unique index product_online_links_active on public.product_online_links (household_id, product_id, store) where deleted_at is null;
create index on public.product_online_links (product_id);

alter table public.product_online_links enable row level security;
create policy product_online_links_all on public.product_online_links for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_product_online_links before update on public.product_online_links
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------------------------------------------
-- Suche: aehnliche Online-Artikel zu einem Produktnamen (Volltextsuche, ohne Erweiterungen)
-- ---------------------------------------------------------------------------------------------------------------
-- Jedes Wort der Anfrage wird als Wortanfang gesucht (ODER), die Treffer nach ts_rank mit Laengennormalisierung
-- gereiht, je Haendler die besten [per_store]. Kuerzere Namen vor laengeren bei gleicher Wertung. Gesucht wird bewusst
-- weit, das Bestaetigen macht der Nutzer.
create or replace function public.search_online_prices(
  q text,
  wanted_stores text[] default array['billa', 'spar'],
  per_store integer default 8
)
returns table (
  store text, external_id text, name text, price_cents integer, quantity numeric, unit text,
  base_unit text, unit_price_norm_cents integer, seen_at timestamptz
)
language sql stable security invoker
set search_path = public
as $$
  with tokens as (
    select t from unnest(regexp_split_to_array(lower(coalesce(q, '')), '[^a-z0-9äöüß]+')) as t where length(t) >= 2
  ),
  query as (
    select to_tsquery('simple', string_agg(t || ':*', ' | ')) as tsq from tokens
  ),
  ranked as (
    select p.*,
           row_number() over (
             partition by p.store
             order by ts_rank(to_tsvector('simple', p.name), query.tsq, 2) desc, length(p.name), p.name
           ) as rn
    from public.online_prices p, query
    where p.store = any(wanted_stores)
      and query.tsq is not null
      and to_tsvector('simple', p.name) @@ query.tsq
  )
  select r.store, r.external_id, r.name, r.price_cents, r.quantity, r.unit, r.base_unit, r.unit_price_norm_cents, r.seen_at
  from ranked r
  where r.rn <= least(greatest(per_store, 1), 20)
  order by r.store, r.rn;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Taeglicher Abruf per pg_cron + pg_net (nur wo die Erweiterungen existieren, damit die Schema-Tests ohne sie laufen)
-- ---------------------------------------------------------------------------------------------------------------
-- Die Function braucht keine Anmeldung (verify_jwt aus): ein Aufruf macht hoechstens einen HEAD-Request, solange der Feed
-- unveraendert ist oder ein Lauf laeuft. Der Feed wird gegen 05:05 UTC aktualisiert, der zweite Termin faengt einen
-- fehlgeschlagenen ersten Lauf ab (bei Erfolg antwortet er nur "up_to_date").
do $cron$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_cron with schema pg_catalog;
    create extension if not exists pg_net with schema extensions;
    perform cron.schedule(
      'refresh-online-prices-morning', '0 6 * * *',
      $job$select net.http_post(
        url := 'https://azavqfegusaugygxdgdx.supabase.co/functions/v1/refresh-online-prices',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{}'::jsonb,
        timeout_milliseconds := 10000)$job$);
    perform cron.schedule(
      'refresh-online-prices-midday', '0 12 * * *',
      $job$select net.http_post(
        url := 'https://azavqfegusaugygxdgdx.supabase.co/functions/v1/refresh-online-prices',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{}'::jsonb,
        timeout_milliseconds := 10000)$job$);
  end if;
end
$cron$;
