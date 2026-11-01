-- Gedaechtnis: eine neue Zuordnung ersetzt die alte, statt am Eindeutigkeits-Index zu scheitern
--
-- Die App vergleicht beim Merken nur den Namen, den sie kennt (FoodLinkRepository.learn, ohne Gross- und Kleinschreibung),
-- den Schluessel bildet erst der Server (food_key). Heisst ein Produkt "Zwiebeln gelb" und lokal steht schon "gelb zwiebel",
-- legt die App eine zweite Zeile mit neuer id an. Der Normalisierungs-Trigger macht daraus denselben Schluessel, der Index
-- household_food_links_active lehnt mit 23505 ab, und die Aenderung bleibt fuer immer in der Outbox haengen.
--
-- Die Regel gehoert hierher und nicht in die App: food_key gibt es bewusst nur einmal (0022), und so gehen auch Aenderungen
-- durch, die schon in einer Outbox warten, ohne neue App-Version. Es gilt Last-write-wins wie beim uebrigen Sync (Doku 03 §2.3).
-- Die alte Zeile wird weich geloescht, damit der naechste Sync sie von den Geraeten nimmt.

create function public.retire_other_food_links()
returns trigger
language plpgsql
as $$
declare
  old_code text;
  old_weight numeric;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  update public.household_food_links l
    set deleted_at = now()
    where l.household_id = new.household_id and l.name_norm = new.name_norm and l.deleted_at is null and l.id <> new.id
    returning l.bls_code, l.unit_weight_g into old_code, old_weight;
  -- Das Stueckgewicht gilt dem Lebensmittel: bei gleichem Eintrag bleibt es erhalten
  if new.unit_weight_g is null and old_code = new.bls_code then
    new.unit_weight_g := old_weight;
  end if;
  return new;
end;
$$;

-- Der Name sorgt fuer die Reihenfolge: Trigger laufen alphabetisch, trg_normalize_food_links muss vorher den Schluessel bilden
create trigger trg_retire_other_food_links before insert or update of name_norm, deleted_at on public.household_food_links
  for each row execute function public.retire_other_food_links();
