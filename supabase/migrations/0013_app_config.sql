-- App-weite Mindestversion ("Update erforderlich"): wird von Hand (SQL/Dashboard, nicht automatisiert)
-- erhoeht, wenn eine Server-Aenderung (Schema, Edge-Function-Vertrag) nicht mehr rueckwaertskompatibel
-- zu aelteren Client-Versionen ist -- dieses Projekt hat keine formale API-Versionierung, der Server
-- wird unabhaengig vom Client weiterentwickelt. Einzeilige Konfigurationstabelle, kein Haushaltsbezug.
--
-- Startwert 1: bewusst weit unterhalb jeder bisherigen Build-Nummer, damit das Einspielen dieser
-- Migration fuer sich genommen keinen bestehenden Client sperrt. Jakob hebt den Wert gezielt an,
-- sobald eine Breaking Change ausgeliefert wird.
create table public.app_config (
  id boolean primary key default true,
  min_supported_build_number integer not null default 1,
  message text,
  updated_at timestamptz not null default now(),
  constraint app_config_singleton check (id)
);

insert into public.app_config (id, min_supported_build_number) values (true, 1);

alter table public.app_config enable row level security;

-- Lesen fuer alle angemeldeten Nutzer (gleiches Muster wie default_categories), kein Insert/Update/
-- Delete fuer Clients -- wird ausschliesslich von Hand gepflegt.
create policy app_config_read on public.app_config
  for select using (auth.role() = 'authenticated');
