-- Verweise zwischen Haushaltstabellen nur innerhalb desselben Haushalts (Codereview 2026-10-16, Fund S7)
--
-- RLS prueft nur das household_id der eigenen Zeile, ein Fremdschluessel nur, dass die Zielzeile existiert. Ein Mitglied
-- von Haushalt A, das eine UUID aus Haushalt B kennt, konnte so eine eigene Zeile auf B's Objekt zeigen lassen (lesen
-- liess sich dabei nichts, aber z.B. das Loeschen eines Produkts in B blockieren, inventory_items.product_id ist
-- `on delete restrict`). Ab hier verlangt ein Trigger, dass die Zielzeile zum selben Haushalt gehoert.
--
-- Fehlercode 23503 (foreign_key_violation) wie bei einem fehlenden Verweis: die App stuft das als Datenfehler ein und
-- blockiert damit die Outbox nicht (remote_store.dart, isRemoteDataError). Bestehende Zeilen werden nicht geprueft, nur
-- neue und geaenderte Verweise. supabase/tests/run_schema_tests.py prueft, dass jeder solche Fremdschluessel den
-- Trigger hat, auch in kuenftigen Migrationen.

create or replace function public.ensure_same_household()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  i int := 0;
  ref_id uuid;
  ok boolean;
begin
  -- Argumente paarweise: Spalte mit dem Verweis, Zieltabelle (Primaerschluessel id)
  while i < tg_nargs loop
    execute format('select ($1).%I', tg_argv[i]) using new into ref_id;
    if ref_id is not null then
      execute format('select exists (select 1 from public.%I t where t.id = $1 and t.household_id = $2)', tg_argv[i + 1])
        using ref_id, new.household_id into ok;
      if not ok then
        raise exception '%.% verweist auf eine Zeile aus einem anderen Haushalt (%.id = %)', tg_table_name, tg_argv[i], tg_argv[i + 1], ref_id
          using errcode = '23503';
      end if;
    end if;
    i := i + 2;
  end loop;
  return new;
end;
$$;

create trigger trg_same_household before insert or update of household_id, parent_id on public.categories
  for each row execute function public.ensure_same_household('parent_id', 'categories');
create trigger trg_same_household before insert or update of household_id, category_id on public.category_aliases
  for each row execute function public.ensure_same_household('category_id', 'categories');
create trigger trg_same_household before insert or update of household_id, product_id, receipt_item_id on public.inventory_items
  for each row execute function public.ensure_same_household('product_id', 'products', 'receipt_item_id', 'receipt_items');
create trigger trg_same_household before insert or update of household_id, inventory_item_id, meal_id, product_id on public.inventory_movements
  for each row execute function public.ensure_same_household('inventory_item_id', 'inventory_items', 'meal_id', 'meals', 'product_id', 'products');
create trigger trg_same_household before insert or update of household_id, receipt_id on public.llm_usage
  for each row execute function public.ensure_same_household('receipt_id', 'receipts');
create trigger trg_same_household before insert or update of household_id, inventory_item_id, meal_id, product_id on public.meal_ingredients
  for each row execute function public.ensure_same_household('inventory_item_id', 'inventory_items', 'meal_id', 'meals', 'product_id', 'products');
create trigger trg_same_household before insert or update of household_id, recipe_id on public.meals
  for each row execute function public.ensure_same_household('recipe_id', 'recipes');
create trigger trg_same_household before insert or update of household_id, product_id, store_id on public.product_aliases
  for each row execute function public.ensure_same_household('product_id', 'products', 'store_id', 'stores');
create trigger trg_same_household before insert or update of household_id, product_id on public.product_barcodes
  for each row execute function public.ensure_same_household('product_id', 'products');
create trigger trg_same_household before insert or update of household_id, product_id on public.product_online_links
  for each row execute function public.ensure_same_household('product_id', 'products');
create trigger trg_same_household before insert or update of household_id, category_id on public.products
  for each row execute function public.ensure_same_household('category_id', 'categories');
create trigger trg_same_household before insert or update of household_id, receipt_id on public.receipt_files
  for each row execute function public.ensure_same_household('receipt_id', 'receipts');
create trigger trg_same_household before insert or update of household_id, category_id, product_id, receipt_id on public.receipt_items
  for each row execute function public.ensure_same_household('category_id', 'categories', 'product_id', 'products', 'receipt_id', 'receipts');
create trigger trg_same_household before insert or update of household_id, store_id on public.receipts
  for each row execute function public.ensure_same_household('store_id', 'stores');
create trigger trg_same_household before insert or update of household_id, product_id, recipe_id on public.recipe_ingredients
  for each row execute function public.ensure_same_household('product_id', 'products', 'recipe_id', 'recipes');
create trigger trg_same_household before insert or update of household_id, list_id, product_id on public.shopping_list_items
  for each row execute function public.ensure_same_household('list_id', 'shopping_lists', 'product_id', 'products');
create trigger trg_same_household before insert or update of household_id, supplement_id on public.supplement_intakes
  for each row execute function public.ensure_same_household('supplement_id', 'supplements');
