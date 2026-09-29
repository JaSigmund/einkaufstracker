-- ENTWURF, NICHT EINGESPIELT (Phase 6, Option A aus ADR-017 "Haushalts-Einladungen fuer Multi-User").
-- Liegt bewusst NICHT in migrations/, damit `supabase db push` es nicht einspielt.
-- Nur relevant, falls Jakob sich gegen die leichtgewichtige Option B (manuelles Anlegen) entscheidet.
-- Doku: ClaudeBrain/02 Projekte/Einkaufstracker/12 Entscheidungen (ADR).md, ADR-017

create table public.household_invites (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  invited_by   uuid not null references auth.users(id) on delete cascade,
  email        text not null,
  token        text not null unique,               -- zufaellig, Teil des Einladungslinks
  role         public.member_role not null default 'member',
  expires_at   timestamptz not null default (now() + interval '7 days'),
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index on public.household_invites (household_id);
create unique index on public.household_invites (email, household_id) where accepted_at is null;

alter table public.household_invites enable row level security;

-- Nur Haushaltsmitglieder duerfen Einladungen fuer ihren Haushalt sehen/anlegen (nicht loeschen,
-- das macht die Edge Function mit dem Service-Role-Key nach erfolgreicher Annahme).
create policy household_invites_select on public.household_invites
  for select using (public.is_household_member(household_id));
create policy household_invites_insert on public.household_invites
  for insert with check (public.is_household_member(household_id) and invited_by = auth.uid());

-- Die eigentliche Annahme (Auth-Nutzer per Admin-API anlegen, household_members-Zeile einfuegen,
-- diese Zeile loeschen/markieren) laeuft ueber eine noch zu bauende Edge Function `accept-invite`
-- mit dem Service-Role-Key, nicht direkt per RLS -- ein frisch eingeladener Mensch hat ja noch
-- keinen Account und damit kein JWT, mit dem RLS etwas pruefen koennte.
