-- Korrektur zu 0001: Beim Anmelden wurde zwar Haushalt, Mitgliedschaft und Kategorien angelegt,
-- aber keine Zeile in household_settings. Die Edge Function parse-receipt liest dort die
-- Einwilligung zur Cloud-Auswertung (allow_cloud_ocr) und haette ohne Zeile immer "forbidden" geliefert.
-- 0001 bleibt unveraendert (bereits eingespielt), die Korrektur kommt als neue Migration.

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  hid uuid;
begin
  insert into public.households (name) values ('Mein Haushalt') returning id into hid;
  insert into public.household_members (household_id, user_id, role) values (hid, new.id, 'owner');
  insert into public.household_settings (household_id) values (hid);   -- Standardwerte, allow_cloud_ocr = false
  insert into public.categories (household_id, name, icon, sort_order, is_storable, parent_id)
    select hid, c.name, c.icon, c.sort_order, c.is_storable, null
    from public.default_categories c;
  return new;
end;
$$;

-- Bestehende Haushalte ohne Einstellungen nachziehen
insert into public.household_settings (household_id)
select h.id from public.households h
where not exists (select 1 from public.household_settings s where s.household_id = h.id);
