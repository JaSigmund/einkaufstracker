-- Lernende Kategorisierung (Phase 2): Der Nutzer ordnet einen Bon-Artikel einer Kategorie zu, die App merkt
-- sich den normalisierten Namen und ordnet gleiche Artikel kuenftig automatisch zu (Doku 05 §3.7, Stufe 1).
-- Die Zuordnung ist bewusst am Namen und nicht an einem Produkt: Produkte (mit EAN, Marke, Haltbarkeit)
-- kommen in Phase 3, dort ersetzt product_aliases diese Tabelle fuer den Zweck.

create table public.category_aliases (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  alias_text   text not null,                                   -- normalisierter Artikelname, z.B. "dkih paprika tricolore"
  category_id  uuid not null references public.categories(id) on delete cascade,
  hits         int  not null default 1,                         -- wie oft der Nutzer diese Zuordnung bestaetigt hat
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (household_id, alias_text)
);
create index on public.category_aliases (household_id);
create index on public.category_aliases (category_id);

alter table public.category_aliases enable row level security;
create policy category_aliases_all on public.category_aliases
  for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_category_aliases before update on public.category_aliases
  for each row execute function public.touch_updated_at();
