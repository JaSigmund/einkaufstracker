-- Fehlerberichte aus der App (Jakobs Wunsch 2026-09-27): Ein Bericht haelt fest, was passiert ist, was
-- erwartet wurde, und den technischen Stand zum Zeitpunkt des Auftretens (Plattform, aktuelle Seite, ob
-- Aenderungen noch nicht synchronisiert waren), optional dazu ein Ausschnitt der lokalen Daten (juengste
-- Zeilen einiger Tabellen), damit ein Fehler moeglichst ohne Rueckfragen nachvollzogen werden kann.

create table public.bug_reports (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  created_by    uuid references auth.users(id) on delete set null,
  title         text not null,
  description   text,
  app_info      jsonb not null,   -- Plattform, OS-Version, Route, ausstehende Aenderungen, letzter Sync-Fehler, Zeitstempel
  data_snapshot jsonb,            -- optionaler Auszug juengster Zeilen lokaler Tabellen
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.bug_reports (household_id, created_at desc);

alter table public.bug_reports enable row level security;
create policy bug_reports_all on public.bug_reports
  for all
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));
create trigger trg_touch_bug_reports before update on public.bug_reports
  for each row execute function public.touch_updated_at();
