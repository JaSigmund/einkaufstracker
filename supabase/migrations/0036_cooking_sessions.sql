-- Kochzeiten (ADR-046): wie lange ein Gericht tatsaechlich gedauert hat, ohne Pausen. Grundlage fuer spaetere Statistiken.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md
--
-- recipe_title statt einer Verknuepfung: gespeicherte Rezepte liegen bisher nur auf dem Geraet, Vorschlaege und Wochenplan kennen gar keine
-- Rezept-Kennung. Was gerade laeuft, bleibt auf dem Geraet, hier landet nur der Abschluss.

create table public.cooking_sessions (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  recipe_title   text not null check (length(trim(recipe_title)) between 1 and 200),
  started_at     timestamptz not null,
  ended_at       timestamptz not null,
  active_seconds integer not null check (active_seconds > 0),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  check (ended_at >= started_at)
);
create index on public.cooking_sessions (household_id, started_at desc) where deleted_at is null;

alter table public.cooking_sessions enable row level security;
create policy cooking_sessions_all on public.cooking_sessions for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_cooking_sessions before update on public.cooking_sessions
  for each row execute function public.touch_updated_at();
