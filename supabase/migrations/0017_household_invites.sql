-- Haushalts-Einladungen (Phase 6, ADR-017 Option A "Selbstbedienung")
--
-- Ein Mitglied laedt per E-Mail-Adresse ein und bekommt einen Einladungscode (12 Zeichen, ohne verwechselbare
-- Zeichen). Wer eingeladen wurde, hat noch kein Konto und damit kein JWT, mit dem RLS etwas pruefen koennte: die
-- Annahme laeuft deshalb ueber die Edge Function `accept-invite` mit dem Service-Role-Key. Sie legt den Auth-Nutzer
-- per Admin-API an und ruft die beiden Funktionen unten auf, die die Pruefung und die Mitgliedschaft in je einer
-- Transaktion erledigen. Selbstregistrierung bleibt im Projekt ausgeschaltet.
--
-- Sicherheitsmodell:
--   * Code = 12 Zeichen aus 31 Symbolen (rund 59 Bit), nur 7 Tage gueltig, einmal verwendbar, an eine E-Mail-Adresse
--     gebunden. Eine falsche E-Mail-Adresse zu einem gueltigen Code zaehlt als Fehlversuch, nach 5 ist der Code gesperrt.
--   * Clients duerfen Einladungen nur ansehen, anlegen (nur Rolle `member`) und zurueckziehen, solange sie offen sind.
--     Annehmen, Sperren und Mitgliedschaft schreiben nur die service_role-Funktionen.
--   * Der Signup-Trigger legt fuer eingeladene Nutzer KEINEN eigenen Haushalt an. Erkannt wird das an
--     `raw_app_meta_data.invited_to`, das nur die Admin-API setzen kann (anders als `raw_user_meta_data`, das ein
--     Client beim Registrieren selbst mitgeben koennte).

-- ---------------------------------------------------------------------------
-- Code-Erzeugung: 12 Zeichen aus A-Z ohne I, L, O sowie 2-9 (keine 0 und 1), zufaellig aus gen_random_uuid()
-- ---------------------------------------------------------------------------
create or replace function public.new_invite_code()
returns text
language sql
volatile
as $$
  with raw as (
    select substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)
        || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12) as hex  -- erste 12 Hexstellen einer UUIDv4 sind zufaellig
  )
  select string_agg(
           substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (('x' || substr(hex, i * 2 + 1, 2))::bit(8)::int % 31) + 1, 1),
           '' order by i)
  from raw, generate_series(0, 11) as i
$$;

-- ---------------------------------------------------------------------------
-- Tabelle
-- ---------------------------------------------------------------------------
create table public.household_invites (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references public.households(id) on delete cascade,
  invited_by      uuid not null references auth.users(id) on delete cascade,
  email           text not null check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  token           text not null unique default public.new_invite_code() check (token ~ '^[A-Z0-9]{12}$'),
  role            public.member_role not null default 'member' check (role = 'member'),
  expires_at      timestamptz not null default (now() + interval '7 days'),
  accepted_at     timestamptz,
  accepted_by     uuid references auth.users(id) on delete set null,
  failed_attempts int not null default 0,
  created_at      timestamptz not null default now()
);
create index on public.household_invites (household_id);
-- hoechstens eine offene Einladung je E-Mail-Adresse und Haushalt
create unique index household_invites_open_email on public.household_invites (email, household_id) where accepted_at is null;

alter table public.household_invites enable row level security;

create policy household_invites_select on public.household_invites
  for select using (public.is_household_member(household_id));
create policy household_invites_insert on public.household_invites
  for insert with check (public.is_household_member(household_id) and invited_by = auth.uid());
-- Zurueckziehen: nur offene Einladungen (eine angenommene bleibt als Nachweis stehen)
create policy household_invites_delete on public.household_invites
  for delete using (public.is_household_member(household_id) and accepted_at is null);

-- Missbrauchsschutz: hoechstens 20 offene Einladungen je Haushalt auf einmal
create or replace function public.household_invites_limits()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if (select count(*) from public.household_invites i where i.household_id = new.household_id and i.accepted_at is null and i.expires_at > now()) >= 20 then
    raise exception 'too_many_open_invites' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger household_invites_limits before insert on public.household_invites
  for each row execute function public.household_invites_limits();

-- ---------------------------------------------------------------------------
-- Signup-Trigger: eingeladene Nutzer bekommen keinen eigenen Haushalt (Rest unveraendert zu 0004)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  hid uuid;
begin
  if new.raw_app_meta_data ? 'invited_to' then
    return new;   -- Mitgliedschaft legt redeem_invite() an
  end if;
  insert into public.households (name) values ('Mein Haushalt') returning id into hid;
  insert into public.household_members (household_id, user_id, role) values (hid, new.id, 'owner');
  insert into public.household_settings (household_id) values (hid);   -- Standardwerte, allow_cloud_ocr = false
  insert into public.categories (household_id, name, icon, sort_order, is_storable, parent_id)
    select hid, c.name, c.icon, c.sort_order, c.is_storable, null
    from public.default_categories c;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Einladung pruefen (VOR dem Anlegen des Auth-Nutzers)
--
-- Gibt einen Status zurueck statt eine Ausnahme zu werfen: eine Ausnahme wuerde die Fehlversuchs-Zaehlung mit
-- zurueckrollen. Status: ok | not_found | email_mismatch | expired | used | locked | full
-- ---------------------------------------------------------------------------
create or replace function public.peek_invite(p_token text, p_email text)
returns table (status text, household_id uuid)
language plpgsql
security definer set search_path = public
as $$
declare
  inv public.household_invites%rowtype;
begin
  select * into inv from public.household_invites i where i.token = upper(btrim(p_token)) for update;
  if not found then
    return query select 'not_found'::text, null::uuid;
    return;
  end if;
  if inv.accepted_at is not null then
    return query select 'used'::text, null::uuid;
    return;
  end if;
  if inv.failed_attempts >= 5 then
    return query select 'locked'::text, null::uuid;
    return;
  end if;
  if inv.expires_at <= now() then
    return query select 'expired'::text, null::uuid;
    return;
  end if;
  if inv.email <> lower(btrim(p_email)) then
    update public.household_invites set failed_attempts = failed_attempts + 1 where id = inv.id;
    return query select 'email_mismatch'::text, null::uuid;
    return;
  end if;
  if (select count(*) from public.household_members m where m.household_id = inv.household_id) >= 10 then
    return query select 'full'::text, null::uuid;
    return;
  end if;
  return query select 'ok'::text, inv.household_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Einladung einloesen (NACH dem Anlegen des Auth-Nutzers): Mitgliedschaft + Einladung als angenommen markieren,
-- atomar. Wirft eine Ausnahme, wenn die Einladung inzwischen nicht mehr gueltig ist (z.B. zwei gleichzeitige Annahmen).
-- ---------------------------------------------------------------------------
create or replace function public.redeem_invite(p_token text, p_user_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  inv public.household_invites%rowtype;
begin
  select * into inv from public.household_invites i where i.token = upper(btrim(p_token)) for update;
  if not found or inv.accepted_at is not null or inv.expires_at <= now() or inv.failed_attempts >= 5 then
    raise exception 'invite_not_redeemable' using errcode = 'P0001';
  end if;
  if (select count(*) from public.household_members m where m.household_id = inv.household_id) >= 10 then
    raise exception 'household_full' using errcode = 'P0001';
  end if;
  insert into public.household_members (household_id, user_id, role) values (inv.household_id, p_user_id, inv.role);
  update public.household_invites set accepted_at = now(), accepted_by = p_user_id where id = inv.id;
  return inv.household_id;
end;
$$;

-- Nur die Edge Function (service_role) darf pruefen und einloesen: ein Client duerfte sonst Codes durchprobieren
-- oder sich selbst zu Mitgliedern machen.
revoke all on function public.peek_invite(text, text) from public, anon, authenticated;
revoke all on function public.redeem_invite(text, uuid) from public, anon, authenticated;
grant execute on function public.peek_invite(text, text) to service_role;
grant execute on function public.redeem_invite(text, uuid) to service_role;
