-- Ausgeschlossene Bon-Positionen (ADR-020 "Rechnungen teilen", Feature-Request bestaetigt 2026-10-01).
-- Vormals Entwurf supabase/planned/receipt_item_excluded_draft.sql.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md, ADR-020

alter table public.receipt_items
  add column excluded boolean not null default false;

comment on column public.receipt_items.excluded is
  'Position wurde von jemand anderem bezahlt (ADR-020): zaehlt nicht zur eigenen Monatsauswertung/'
  'Budget/Trend (siehe lib/domain/receipt/excluded_items.dart, splitExcludedItems), bleibt aber auf '
  'dem Bon sichtbar und wandert normal ins Inventar.';

-- Kein RLS-Eingriff noetig: dieselbe Spalte wie jede andere an receipt_items, bestehende Policies
-- (Haushaltsmitglieder lesen/schreiben eigene Haushaltsdaten) decken sie automatisch mit ab.
-- Sync (ADR-004): neues Feld, gleiches Outbox-Muster wie jede andere Spalte -- kein Sonderfall.
