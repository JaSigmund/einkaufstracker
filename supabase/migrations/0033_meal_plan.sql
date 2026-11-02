-- Wochenplan (ADR-042): welches Gericht an welchem Tag geplant ist. Eine Zeile je Gericht, mehrere am Tag sind normal.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md
--
-- ingredients ist eine Kopie der Zutaten als jsonb ([{productId, name, unit}]), keine Verknuepfung: gespeicherte Rezepte liegen bisher nur
-- auf dem Geraet, und ein geplantes Gericht soll sich nicht aendern, wenn das Rezept spaeter geloescht wird. Mengen gibt es bewusst nicht,
-- wie bei den Rezepten (ADR-021): die App kennt nur "vorhanden" oder "fehlt".

create table public.meal_plan_entries (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  planned_on   date not null,
  slot         text not null default 'dinner' check (slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  title        text not null check (length(trim(title)) between 1 and 200),
  ingredients  jsonb not null default '[]' check (jsonb_typeof(ingredients) = 'array'),
  source_url   text,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on public.meal_plan_entries (household_id, planned_on) where deleted_at is null;

alter table public.meal_plan_entries enable row level security;
create policy meal_plan_entries_all on public.meal_plan_entries for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_meal_plan_entries before update on public.meal_plan_entries
  for each row execute function public.touch_updated_at();
