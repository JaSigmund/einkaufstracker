-- Nahrungsergaenzung und gemeinsame Einstellungen des Haushalts (Phase N4, ADR-035).
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/23 Konzept Ausbau 1.12 bis 1.14.md
--
--   supplements         Was der Haushalt an Nahrungsergaenzung nimmt: Name, was eine Einheit ist (Tablette, Kapsel, Messloeffel) und
--                       die Mikronaehrstoffe je Einheit (absolute Mengen laut Packung, Schluessel wie nutrient_registry.json)
--   supplement_intakes  Jede Einnahme als Snapshot (Name und absolute Mengen fuer die genommenen Einheiten), damit eine spaetere
--                       Aenderung oder Loeschung der Ergaenzung die Vergangenheit nicht veraendert (wie meal_ingredients)
--   household_prefs     Gemeinsame Einstellungen als Schluessel-Wert-Zeilen (heute: eigene Referenzmengen der Seite Naehrstoffe).
--                       Je Schluessel eine Zeile, damit zwei Geraete verschiedene Einstellungen aendern koennen, ohne sich zu
--                       ueberschreiben.

create table public.supplements (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  name          text not null check (length(trim(name)) > 0),
  serving_label text not null default 'Tablette' check (length(trim(serving_label)) > 0),
  micros        jsonb not null default '{}',
  note          text,
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.supplements (household_id) where deleted_at is null;

create table public.supplement_intakes (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  supplement_id uuid references public.supplements(id) on delete set null,
  name          text not null check (length(trim(name)) > 0),
  taken_at      timestamptz not null,
  servings      numeric(8,3) not null default 1 check (servings > 0),
  micros        jsonb not null default '{}',
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.supplement_intakes (household_id, taken_at desc) where deleted_at is null;

create table public.household_prefs (
  household_id uuid not null references public.households(id) on delete cascade,
  key          text not null check (length(key) between 1 and 64),
  value        jsonb not null,
  updated_at   timestamptz not null default now(),
  primary key (household_id, key)
);

do $$
declare t text;
begin
  foreach t in array array['supplements','supplement_intakes','household_prefs'] loop
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
