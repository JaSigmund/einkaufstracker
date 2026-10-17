-- Einladungen: Code, Ablauf und Zaehler setzt beim Anlegen immer der Server (Codereview 2026-10-16, Fund S8)
--
-- Die Insert-Policy aus 0017 prueft Mitgliedschaft und invited_by, nicht aber die uebrigen Spalten. Ein Mitglied konnte so
-- einen selbst gewaehlten (schwachen) Code, einen Ablauf in ferner Zukunft oder einen negativen Fehlversuchszaehler
-- setzen, der die Sperre nach 5 Fehlversuchen aushebelt. Die App schickt diese Spalten nie mit (household_invites.dart),
-- fuer sie aendert sich nichts.

create or replace function public.household_invites_defaults()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.token := public.new_invite_code();
  new.expires_at := now() + interval '7 days';
  new.failed_attempts := 0;
  new.accepted_at := null;
  new.accepted_by := null;
  new.created_at := now();
  return new;
end;
$$;

-- vor household_invites_limits (Trigger laufen in alphabetischer Reihenfolge)
create trigger household_invites_defaults before insert on public.household_invites
  for each row execute function public.household_invites_defaults();
