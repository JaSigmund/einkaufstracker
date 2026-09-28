-- Feature-Vorschlaege (Jakobs Wunsch 2026-09-28): dieselbe Tabelle wie Fehlerberichte, unterschieden per
-- "kind" - Status/Severity/Resolution-Maschinerie ist fuer beide Arten sinnvoll wiederverwendbar. Der
-- bestehende Status-Enum passt fuer Features fast 1:1: 'confirmed' = angenommen (Gate vor der Umsetzung),
-- 'in_progress' = aktiv in Bearbeitung, 'fixed' = umgesetzt. Die "Planungsliste" ist keine eigene Tabelle,
-- sondern die Abfrage kind='feature' AND status='confirmed', sortiert nach created_at.
create type public.feedback_kind as enum ('bug', 'feature');

alter table public.bug_reports
  add column kind public.feedback_kind not null default 'bug';
