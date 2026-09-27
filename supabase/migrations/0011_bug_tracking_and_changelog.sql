-- Genauere Fehlerverfolgung (Jakobs Wunsch 2026-09-28, "aehnlich wie in MS Azure"): ein Bericht bekommt einen
-- Bearbeitungsstatus, eine Einschaetzung der Dringlichkeit, eine Loesungsnotiz und die Version, in der er
-- behoben wurde. Status/Schweregrad/Loesung werden von der Entwicklung gesetzt (also von mir per SQL), nicht
-- vom meldenden Haushaltsmitglied ueber die App - die RLS-Policy bleibt trotzdem haushaltsweit, wie bei allen
-- anderen Tabellen, weil es in dieser App keine gesonderte Entwicklerrolle gibt.
create type public.bug_status as enum ('new', 'confirmed', 'in_progress', 'fixed', 'verified', 'wont_fix', 'duplicate');
create type public.bug_severity as enum ('low', 'medium', 'high', 'critical');

alter table public.bug_reports
  add column status            public.bug_status not null default 'new',
  add column severity          public.bug_severity,
  add column resolution        text,
  add column fixed_in_version  text,
  add column status_updated_at timestamptz not null default now();

-- Aenderungsprotokoll der App (Doku-Wunsch "Changelog der Versionen"). Anders als die Fachtabellen nicht
-- haushaltsbezogen (die Versionshistorie ist fuer alle Nutzer der App gleich) und nur lesend fuer den Client:
-- geschrieben wird sie von mir per SQL bei jedem Release, nicht ueber die App.
create table public.app_changelog (
  id          uuid primary key default gen_random_uuid(),
  version     text not null,
  title       text not null,
  highlights  jsonb not null default '[]'::jsonb,  -- Liste kurzer Stichpunkte, was sich geaendert hat
  fixed_bug_report_ids uuid[],                       -- Verweise auf bug_reports.id, fuer die Rueckverfolgung
  released_at timestamptz not null default now()
);
create index on public.app_changelog (released_at desc);
alter table public.app_changelog enable row level security;
create policy app_changelog_select on public.app_changelog
  for select using (auth.role() = 'authenticated');
