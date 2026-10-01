-- ENTWURF, NICHT EINGESPIELT (ADR-021 "Rezeptvorschläge aus Inventar + Koch-Chatbot", Phase 7f).
-- Liegt bewusst NICHT in migrations/, da Edge Function, Chatbot und UI noch nicht entschieden/gebaut
-- sind (offene Fragen Q-21 bis Q-24). Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen
-- (ADR).md, ADR-021.
--
-- WICHTIG (Urheberrecht): gespeichert wird nur eine REFERENZ -- Titel, die eigene (von Claude
-- generierte) Zutatenliste und der Link zur echten Rezeptseite. KEINE kopierte Kochanleitung, kein
-- Spiegeln fremder Bilder. Faellt die externe Seite offline, ist die Anleitung weg -- bewusste
-- Konsequenz, siehe ADR-021.

create table public.recipes (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  created_by    uuid not null references auth.users(id) on delete cascade,
  title         text not null,
  -- Suchlink zur externen Rezeptseite (recipe_search_url.dart), nicht die Kochanleitung selbst.
  source_url    text,
  -- Eigene Zutatenliste (aus dem KI-Vorschlag oder manuell eingegeben), nicht von der externen
  -- Seite kopiert. [{productId, productName, quantity, unit}, ...], productId optional (freitextlich
  -- erfasste Zutaten ohne Produkt-Zuordnung sind moeglich, siehe recipe_shopping_gap.dart).
  ingredients   jsonb not null default '[]'::jsonb,
  servings      integer not null default 1,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.recipes (household_id) where deleted_at is null;

alter table public.recipes enable row level security;

create policy recipes_select on public.recipes
  for select using (public.is_household_member(household_id));
create policy recipes_insert on public.recipes
  for insert with check (public.is_household_member(household_id) and created_by = auth.uid());
create policy recipes_update on public.recipes
  for update using (public.is_household_member(household_id));

-- Sync (ADR-004): gleiches Outbox-Muster wie jede andere Haushaltstabelle, Soft-Delete ueber
-- deleted_at statt echtem DELETE (gleiches Prinzip wie receipts/products).
