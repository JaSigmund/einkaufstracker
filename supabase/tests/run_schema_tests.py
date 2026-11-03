"""Schema- und RLS-Tests gegen ein eingebettetes Postgres (pgserver), ohne Docker.

Supabase-spezifische Teile (auth, storage, Rollen) werden minimal nachgebaut, damit die
Migrationen unveraendert eingespielt werden koennen. Das ersetzt keinen Test gegen echtes
Supabase (`supabase start`), deckt aber Schema, Trigger, generierte Spalte, Views und
Row Level Security ab.

Voraussetzungen:  pip install pgserver "psycopg[binary]" tzdata
Hinweis Windows:  Das mitgelieferte Postgres von pgserver enthaelt keine Zeitzonendaten.
                  Das Skript kopiert sie beim ersten Lauf aus dem tzdata-Paket in die Installation.
Aufruf:           python supabase/tests/run_schema_tests.py
"""
import pathlib
import shutil
import sys
import tempfile

import pgserver
import psycopg

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATIONS = sorted((ROOT / "migrations").glob("*.sql"))
PLANNED = sorted((ROOT / "planned").glob("*.sql"))

SUPABASE_STUBS = """
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_app_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon') $$;
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
alter table storage.objects enable row level security;  -- wie in echtem Supabase
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select string_to_array(name, '/') $$;
grant usage on schema public, auth, storage to anon, authenticated, service_role;
"""

DEFAULT_PRIVILEGES = """
alter default privileges in schema public grant all on tables to authenticated, service_role;
alter default privileges in schema public grant execute on functions to authenticated, service_role;
"""

GRANTS = """
grant all on all tables in schema public to authenticated, service_role;
grant all on all tables in schema storage to authenticated, service_role;
grant select on all tables in schema auth to service_role;
grant execute on all functions in schema auth, storage to authenticated, service_role;
"""

A = "11111111-1111-1111-1111-111111111111"
B = "22222222-2222-2222-2222-222222222222"

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name + (f"   [{detail}]" if detail and not cond else ""))


def ensure_timezones():
    """pgserver-Postgres hat unter Windows keine tz-Daten: aus tzdata nachruesten."""
    inst = pathlib.Path(pgserver.__file__).parent / "pginstall" / "share" / "postgresql" / "timezone"
    if inst.exists():
        return
    import tzdata
    shutil.copytree(pathlib.Path(tzdata.__file__).parent / "zoneinfo", inst)


def main():
    ensure_timezones()
    srv = pgserver.get_server(tempfile.mkdtemp(prefix="pg_einkaufstracker_"))
    uri = srv.get_uri()

    def db(sql, params=None, user=None):
        """Fuehrt SQL aus (optional als authentifizierter Nutzer), gibt Zeilen zurueck, wirft bei Fehlern."""
        with psycopg.connect(uri, autocommit=True) as c:
            with c.cursor() as cur:
                if user:
                    cur.execute("set role authenticated")
                    cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (user,))
                    cur.execute("select set_config('request.jwt.claim.role', 'authenticated', false)")
                cur.execute(sql, params)
                rowcount = cur.rowcount
                rows = cur.fetchall() if cur.description else []
                return rows, rowcount

    def one(sql, params=None, user=None):
        return db(sql, params, user)[0][0][0]

    def raises(sql, params=None, user=None):
        try:
            db(sql, params, user)
            return False
        except psycopg.Error:
            return True

    # --- Aufbau ---------------------------------------------------------------
    db(SUPABASE_STUBS)
    db(DEFAULT_PRIVILEGES)
    for m in MIGRATIONS:
        db(m.read_text(encoding="utf-8"))
        print(f"Migration {m.name} eingespielt")
    db(GRANTS)

    # --- Signup-Trigger ---------------------------------------------------------
    db("insert into auth.users (id,email) values (%s,'a@test'),(%s,'b@test')", (A, B))
    check("Signup: 2 Haushalte", one("select count(*) from households") == 2)
    check("Signup: 2 Mitgliedschaften", one("select count(*) from household_members") == 2)
    n_def = one("select count(*) from default_categories")
    check("Signup: Kategorien pro Haushalt kopiert", one("select count(*) from categories") == n_def * 2)
    check("Signup: household_settings je Haushalt angelegt (0004)", one("select count(*) from household_settings") == 2)
    check("Signup: Cloud-Auswertung standardmaessig AUS", one("select count(*) from household_settings where allow_cloud_ocr") == 0)

    ha = one("select household_id from household_members where user_id=%s", (A,))
    hb = one("select household_id from household_members where user_id=%s", (B,))

    # --- Row Level Security -------------------------------------------------------
    db("insert into stores (household_id, chain) values (%s,'Billa'),(%s,'Hofer')", (ha, hb))
    db("insert into products (household_id, name, base_unit) values (%s,'Paprika rot','kg')", (ha,))
    pid = one("select id from products")

    check("RLS: A sieht nur eigene Stores", one("select count(*) from stores", user=A) == 1)
    check("RLS: A sieht nur eigene Kategorien", one("select count(*) from categories", user=A) == n_def)
    check("RLS: B sieht keine Produkte von A", one("select count(*) from products", user=B) == 0)
    check("RLS: A darf eigene Einstellung aendern (Einwilligung setzen)",
          db("update household_settings set allow_cloud_ocr = true where household_id=%s", (ha,), user=A)[1] == 1)
    check("RLS: B darf Einstellung von A nicht aendern",
          db("update household_settings set allow_cloud_ocr = false where household_id=%s", (ha,), user=B)[1] == 0)
    db("update household_settings set allow_cloud_ocr = false where household_id=%s", (ha,))
    check("RLS: B kann nicht in Haushalt A einfuegen",
          raises("insert into products (household_id,name) values (%s,'Fremd')", (ha,), user=B))
    _, n = db("update products set name='Gehackt' where household_id=%s", (ha,), user=B)
    check("RLS: B kann Produkte von A nicht aendern", n == 0)
    _, n = db("delete from products where household_id=%s", (ha,), user=B)
    check("RLS: B kann Produkte von A nicht loeschen", n == 0)
    check("RLS: Produkt von A unveraendert", one("select name from products") == "Paprika rot")
    check("RLS: A sieht nur den eigenen Haushalt", one("select count(*) from households", user=A) == 1)
    check("RLS: A sieht nur eigene Mitgliedschaft", one("select count(*) from household_members", user=A) == 1)
    check("RLS: llm_usage ist fuer Clients nicht schreibbar",
          raises("insert into llm_usage (household_id, model, input_tokens, output_tokens) values (%s,'m',1,1)",
                 (ha,), user=A))

    # --- Generierte Ablaufspalte (FR-03) --------------------------------------------
    cases = [
        ("nur MHD",                  "best_before",                        "'2026-10-15'",                  "2026-10-15"),
        ("MHD spaeter als Frist",    "best_before, opened_on, open_shelf_life_days", "'2026-10-15','2026-10-01',3", "2026-10-04"),
        ("ohne MHD, geoeffnet",      "opened_on, open_shelf_life_days",    "'2026-10-01',3",                "2026-10-04"),
        ("MHD vor Oeffnungsfrist",   "best_before, opened_on, open_shelf_life_days", "'2026-10-02','2026-10-01',7", "2026-10-02"),
        ("weder MHD noch Oeffnung",  "quantity",                           "1",                             None),
    ]
    for name, cols, vals, expected in cases:
        rid = one(f"insert into inventory_items (household_id, product_id, {cols}) "
                  f"values (%s,%s,{vals}) returning id", (ha, pid))
        got = one("select expires_on from inventory_items where id=%s", (rid,))
        check(f"expires_on: {name}", (str(got) if got else None) == expected, f"{got}")

    # --- Bon, Positionen, Views -----------------------------------------------------
    store = one("select id from stores where household_id=%s", (ha,))
    cat = one("select id from categories where household_id=%s and name='Gemüse'", (ha,))
    rec = one("insert into receipts (household_id, store_id, purchased_at, total_cents, status) "
              "values (%s,%s,'2026-09-30 23:30+00',1000,'confirmed') returning id", (ha, store))
    db("insert into receipt_items (household_id, receipt_id, line_no, raw_text, product_id, category_id, "
       "quantity, quantity_unit, line_total_cents, unit_price_norm_cents) values "
       "(%s,%s,1,'PAPRIKA',%s,%s,1.2,'kg',431,359),(%s,%s,2,'ZWIEBEL',null,%s,1,'piece',569,null)",
       (ha, rec, pid, cat, ha, rec, cat))
    check("View Kategorie-Summe", one("select sum(spend_cents) from v_monthly_spend_by_category") == 1000)
    check("View Produkt-Summe", one("select sum(spend_cents) from v_monthly_spend_by_product") == 431)
    check("View Preisverlauf enthaelt nur Positionen mit Grundpreis", one("select count(*) from v_price_history") == 1)
    # 30.09. 23:30 UTC = 01.10. 01:30 Wien -> Oktober (FR-07)
    check("Monatsgrenze Europe/Vienna (FR-07)",
          str(one("select min(month) from v_monthly_spend_by_category")) == "2026-10-01")
    check("View: A sieht eigene Summen", one("select count(*) from v_monthly_spend_by_category", user=A) >= 1)
    check("View: B sieht keine Summen von A (security_invoker)",
          one("select count(*) from v_monthly_spend_by_category", user=B) == 0)
    check("Duplikat-Bon wird abgelehnt",
          raises("insert into receipts (household_id, store_id, purchased_at, total_cents, status) "
                 "values (%s,%s,'2026-09-30 23:30+00',1000,'confirmed')", (ha, store)))
    check("Entwurf desselben Bons ist erlaubt (Dedupe nur fuer confirmed)",
          not raises("insert into receipts (household_id, store_id, purchased_at, total_cents, status) "
                     "values (%s,%s,'2026-09-30 23:30+00',1000,'draft')", (ha, store)))

    # --- Constraints ------------------------------------------------------------------
    db("insert into shopping_lists (household_id) values (%s)", (ha,))
    lid = one("select id from shopping_lists")
    check("Listen-Item ohne Produkt und Text wird abgelehnt",
          raises("insert into shopping_list_items (household_id, list_id) values (%s,%s)", (ha, lid)))
    check("EAN-Format wird geprueft",
          raises("insert into product_barcodes (household_id, ean, product_id) values (%s,'abc',%s)", (ha, pid)))
    db("insert into product_barcodes (household_id, ean, product_id) values (%s,'9001234567890',%s)", (ha, pid))
    check("Gueltige EAN wird akzeptiert", one("select count(*) from product_barcodes") == 1)

    # --- updated_at-Trigger ---------------------------------------------------------------
    before = one("select updated_at from products where id=%s", (pid,))
    db("update products set brand='X' where id=%s", (pid,))
    after = one("select updated_at from products where id=%s", (pid,))
    check("updated_at wird per Trigger gepflegt", after > before)

    # --- Storage-Policy ---------------------------------------------------------------------
    check("Storage: A darf in eigenen Haushaltsordner schreiben",
          not raises("insert into storage.objects (bucket_id, name) values ('receipts', %s)", (f"{ha}/x.jpg",), user=A))
    check("Storage: A darf nicht in fremden Haushaltsordner schreiben",
          raises("insert into storage.objects (bucket_id, name) values ('receipts', %s)", (f"{hb}/x.jpg",), user=A))

    # --- Bon-Import (0005) ----------------------------------------------------------------
    rec_sql = ("insert into receipts (household_id, store_id, purchased_at, total_cents, status, source, external_id) "
               "values (%s,%s,%s,100,'confirmed','pdf_text',%s)")
    db(rec_sql, (ha, store, "2026-07-02 17:51+00", "0643-20260702-03-4852"))
    check("Bon-Import: gleiche Re-Nr im selben Haushalt wird abgelehnt (Duplikat)",
          raises(rec_sql, (ha, store, "2026-07-02 17:51+00", "0643-20260702-03-4852")))
    check("Bon-Import: gleiche Re-Nr in anderem Haushalt ist erlaubt",
          not raises(rec_sql, (hb, None, "2026-07-02 17:51+00", "0643-20260702-03-4852")))
    check("Bon-Import: Bons ohne Re-Nr duerfen mehrfach vorkommen",
          not raises(rec_sql.replace("%s)", "null)", 1), (ha, store, "2026-07-03 10:00+00"))
          and not raises(rec_sql.replace("%s)", "null)", 1), (ha, store, "2026-07-04 10:00+00")))
    rid = one("select id from receipts where external_id='0643-20260702-03-4852' and household_id=%s", (ha,))
    check("Bon-Import: Position mit Steuerbuchstabe speicherbar",
          not raises("insert into receipt_items (household_id, receipt_id, line_no, raw_text, line_total_cents, tax_code) "
                     "values (%s,%s,1,'Clever Champignon',189,'H')", (ha, rid)))
    db("update receipts set deleted_at = now() where id=%s", (rid,))
    check("Bon-Import: nach dem Loeschen (Soft-Delete) darf die Re-Nr erneut importiert werden",
          not raises(rec_sql, (ha, store, "2026-07-02 17:51+00", "0643-20260702-03-4852")))

    # --- Bon-Rabatt als eigene Positionsart (0007) ------------------------------------------
    rid2 = one("select id from receipts where external_id='0643-20260702-03-4852' and household_id=%s and deleted_at is null", (ha,))
    check("Bon-Rabatt: Positionsart bill_discount ist speicherbar",
          not raises("insert into receipt_items (household_id, receipt_id, line_no, raw_text, kind, line_total_cents) "
                     "values (%s,%s,2,'jö Rabattsammler 20%%','bill_discount',-451)", (ha, rid2)))

    # --- Ausgeschlossene Bon-Positionen (0015, ADR-020) ---------------------------------------
    check("Ausschluss: neue Positionen sind standardmaessig nicht ausgeschlossen",
          one("select excluded from receipt_items where receipt_id=%s and line_no=2", (rid2,)) is False)
    db("update receipt_items set excluded = true where receipt_id=%s and line_no=2", (rid2,), user=A)
    check("Ausschluss: Haushaltsmitglied kann eine Position ausschliessen",
          one("select excluded from receipt_items where receipt_id=%s and line_no=2", (rid2,)) is True)
    _, other_rowcount = db("update receipt_items set excluded = false where receipt_id=%s and line_no=2", (rid2,), user=B)
    check("RLS: B kann den Ausschluss einer Position von A nicht aendern (RLS filtert, 0 betroffen)", other_rowcount == 0)

    # --- Originalbelege (0008) ----------------------------------------------------------------
    file_sql =("insert into receipt_files (household_id, receipt_id, kind, storage_path) values (%s,%s,%s,%s)")
    db(file_sql, (ha, rid2, "pdf", f"{ha}/{rid2}/x.pdf"))
    check("Beleg: unbekannte Art wird abgelehnt", raises(file_sql, (ha, rid2, "video", "x")))
    check("RLS: B sieht keine Belege von A", one("select count(*) from receipt_files", user=B) == 0)
    check("RLS: A sieht eigene Belege", one("select count(*) from receipt_files", user=A) == 1)
    check("RLS: B kann keinen Beleg in Haushalt A anlegen", raises(file_sql, (ha, rid2, "pdf", "fremd"), user=B))
    db("delete from receipts where id=%s", (rid2,))
    check("Beleg wird mit seinem Bon geloescht (Kaskade)", one("select count(*) from receipt_files") == 0)

    # --- Fehlerberichte (0009) --------------------------------------------------------------
    bug_sql = "insert into bug_reports (household_id, title, app_info) values (%s,%s,%s)"
    db(bug_sql, (ha, "Scan legt Duplikat an", '{"platform":"android"}'))
    check("RLS: B sieht keine Fehlerberichte von A", one("select count(*) from bug_reports", user=B) == 0)
    check("RLS: A sieht eigene Fehlerberichte", one("select count(*) from bug_reports", user=A) == 1)
    check("RLS: B kann keinen Fehlerbericht in Haushalt A anlegen", raises(bug_sql, (ha, "fremd", "{}"), user=B))
    check("Fehlerbericht ohne app_info wird abgelehnt", raises(
        "insert into bug_reports (household_id, title) values (%s,%s)", (ha, "x")))

    # --- Fehlerverfolgung und Changelog (0011) -----------------------------------------------
    bug_id = one("select id from bug_reports where household_id=%s limit 1", (ha,))
    db("update bug_reports set status='fixed', severity='medium', resolution='behoben', fixed_in_version='1.1.0' where id=%s", (bug_id,))
    check("Fehlerbericht: Status kann gesetzt werden", one("select status::text from bug_reports where id=%s", (bug_id,)) == "fixed")
    check("Fehlerbericht: unbekannter Status wird abgelehnt",
          raises("update bug_reports set status='erledigt' where id=%s", (bug_id,)))
    check("Fehlerbericht: status_updated_at hat einen Standardwert", one("select status_updated_at is not null from bug_reports where id=%s", (bug_id,)))

    changelog_sql = "insert into app_changelog (version, title, highlights) values (%s,%s,%s)"
    db(changelog_sql, ("1.1.0", "Fehlerverfolgung", '["Status je Fehlerbericht", "Changelog"]'))
    check("Changelog: von A lesbar (haushaltsunabhaengig)", one("select count(*) from app_changelog", user=A) == 1)
    check("Changelog: von B lesbar", one("select count(*) from app_changelog", user=B) == 1)

    # --- Lernende Kategorisierung (0006) ---------------------------------------------------
    cat_a = one("select id from categories where household_id=%s and name='Gemüse'", (ha,))
    alias_sql = "insert into category_aliases (household_id, alias_text, category_id) values (%s,%s,%s)"
    db(alias_sql, (ha, "dkih paprika tricolore", cat_a))
    check("Alias: gleicher normalisierter Name im selben Haushalt wird abgelehnt",
          raises(alias_sql, (ha, "dkih paprika tricolore", cat_a)))
    check("RLS: B sieht keine Aliase von A", one("select count(*) from category_aliases", user=B) == 0)
    check("RLS: A sieht eigene Aliase", one("select count(*) from category_aliases", user=A) == 1)
    check("RLS: B kann keinen Alias in Haushalt A anlegen",
          raises(alias_sql, (ha, "fremd", cat_a), user=B))
    db("delete from categories where id=%s", (cat_a,))
    check("Alias wird mit seiner Kategorie geloescht (Kaskade)", one("select count(*) from category_aliases") == 0)

    # --- Inventarbewegungen (0003) -------------------------------------------------------
    ins_mv = ("insert into inventory_movements (household_id, product_id, type, quantity_delta, unit, occurred_at) "
              "values (%s,%s,%s,%s,'kg',%s)")
    check("Bewegung: Einkauf mit negativer Menge wird abgelehnt", raises(ins_mv, (ha, pid, "purchase", -1, "2026-09-21 10:00+02")))
    check("Bewegung: Verbrauch mit positiver Menge wird abgelehnt", raises(ins_mv, (ha, pid, "meal", 1, "2026-09-21 10:00+02")))
    check("Bewegung: was auf 0 rundet, bleibt nicht in der Outbox haengen (0032)",
          not raises(ins_mv, (ha, pid, "meal", -0.0004, "2026-09-21 10:00+02")) and not raises(ins_mv, (ha, pid, "purchase", 0, "2026-09-21 10:00+02")))
    db(ins_mv, (ha, pid, "purchase", 2, "2026-09-21 10:00+02"))
    db(ins_mv, (ha, pid, "meal", -0.5, "2026-09-22 19:00+02"))
    db(ins_mv, (ha, pid, "discarded", -0.25, "2026-09-23 08:00+02"))
    row = db("select purchased, eaten, discarded, net_change from v_weekly_stock_flow")[0][0]
    check("Bilanz-View: Einkauf 2, gegessen 0,5, weggeworfen 0,25, netto +1,25",
          [float(x) for x in row] == [2.0, 0.5, 0.25, 1.25], str(row))
    check("RLS: B sieht keine Bewegungen von A", one("select count(*) from inventory_movements", user=B) == 0)
    check("RLS: B sieht Bilanz-View von A nicht", one("select count(*) from v_weekly_stock_flow", user=B) == 0)
    check("Produkt: Naehrwerte ohne Basis (g/ml) werden abgelehnt",
          raises("update products set nutrients_per_100 = '{\"kcal\": 30}' where id=%s", (pid,)))
    check("Produkt: Naehrwerte mit Basis werden akzeptiert",
          not raises("update products set nutrients_per_100 = '{\"kcal\": 30}', nutrients_basis='g' where id=%s", (pid,)))

    # --- Essenstagebuch (0014_meal_diary.sql, Phase 7a) ------------------------------------------
    # Kam bis Phase 7a aus planned/meal_diary_draft.sql und lief nur, wenn der Entwurf fehlerfrei
    # einspielbar war -- jetzt Teil der regulaeren Migrationen (oben in MIGRATIONS), also keine
    # Bedingung mehr noetig.
    meal = one("insert into meals (household_id, eaten_at, title, servings_made, servings_eaten) "
               "values (%s,'2026-09-22 19:00+02','Gemuesepfanne',4,1) returning id", (ha,))
    db("insert into meal_ingredients (household_id, meal_id, product_id, quantity, unit, amount_g, source, kcal, protein_g, fat_g, carbs_g, fiber_g, salt_g) "
       "values (%s,%s,%s,0.6,'kg',600,'inventory',800,20,40,60,12,2.0)", (ha, meal, pid))
    row = db("select kcal, protein_g, salt_g, meals from v_daily_nutrition")[0][0]
    check("Tages-Naehrwerte: 800 kcal bei 1 von 4 Portionen = 200 kcal",
          [float(x) for x in row] == [200.0, 5.0, 0.5, 1.0], str(row))
    check("Wochen-Naehrwerte liefern Tagesdurchschnitt", one("select avg_kcal_per_day from v_weekly_nutrition") == 200)
    check("RLS: B sieht keine Mahlzeiten von A", one("select count(*) from meals", user=B) == 0)
    check("RLS: B sieht keine Tages-Naehrwerte von A", one("select count(*) from v_daily_nutrition", user=B) == 0)
    check("Bewegung darf auf Mahlzeit zeigen (FK)",
          not raises("insert into inventory_movements (household_id, product_id, type, quantity_delta, unit, meal_id) "
                     "values (%s,%s,'meal',-0.6,'kg',%s)", (ha, pid, meal)))
    # --- Bilanz und Gegenbuchungen (0016): eigenes Produkt, damit die Zeilen oben unberuehrt bleiben ---
    db("insert into products (household_id, name, base_unit) values (%s,'Reis','kg')", (ha,))
    rice = one("select id from products where name='Reis'")
    cooked = one("insert into meals (household_id, eaten_at, title) values (%s,'2026-10-07 12:00+02','Reispfanne') returning id", (ha,))
    kept = one("insert into meals (household_id, eaten_at, title) values (%s,'2026-10-08 12:00+02','Reisbeilage') returning id", (ha,))
    ins_flow = ("insert into inventory_movements (household_id, product_id, type, quantity_delta, unit, occurred_at, meal_id) "
                "values (%s,%s,%s,%s,'kg',%s,%s)")
    db(ins_flow, (ha, rice, "purchase", 3, "2026-10-06 10:00+02", None))
    db(ins_flow, (ha, rice, "meal", -0.5, "2026-10-07 12:00+02", cooked))
    db(ins_flow, (ha, rice, "meal", -0.2, "2026-10-08 12:00+02", kept))
    db(ins_flow, (ha, rice, "consumed", -0.3, "2026-10-09 12:00+02", None))
    db(ins_flow, (ha, rice, "adjustment", -0.1, "2026-10-09 18:00+02", None))
    flow_sql = "select eaten, consumed_manual, adjusted, net_change from v_weekly_stock_flow where product_id=%s order by week"
    row = db(flow_sql, (rice,))[0][0]
    check("Bilanz-View: Mahlzeiten 0,7, aufgebraucht 0,3, Korrektur -0,1, netto +1,9",
          [float(x) for x in row] == [0.7, 0.3, -0.1, 1.9], str(row))
    # Mahlzeit 'cooked' wird zwei Wochen spaeter geloescht: Gegenbuchung nimmt den Abzug zurueck
    db(ins_flow, (ha, rice, "adjustment", 0.5, "2026-10-20 09:00+02", cooked))
    rows = db(flow_sql, (rice,))[0]
    check("Bilanz-View: Gegenbuchung bleibt in der Woche ihrer Mahlzeit (eine Woche, keine negative Folgewoche)",
          len(rows) == 1, str(rows))
    eaten, consumed, adjusted, net = (float(x) for x in rows[0])
    check("Bilanz-View: Gegenbuchung mindert gegessen auf 0,2 und zaehlt nicht als Korrektur (adjusted bleibt -0,1)",
          [eaten, adjusted] == [0.2, -0.1], str(rows[0]))
    check("Bilanz-View: Summe ueber alle Wochen entspricht dem Ledger (3 - 0,5 - 0,2 - 0,3 - 0,1 + 0,5 = 2,4)",
          abs(sum(float(r[3]) for r in rows) - 2.4) < 1e-9, str(rows))
    db(ins_flow, (ha, rice, "meal", -0.4, "2026-10-21 12:00+02", kept))
    rows = db(flow_sql, (rice,))[0]
    check("Bilanz-View: neue Mahlzeit der Folgewoche erscheint in der Folgewoche",
          len(rows) == 2 and abs(float(rows[1][0]) - 0.4) < 1e-9, str(rows))
    check("RLS: B sieht die Bilanz-Zeilen von A nicht", one("select count(*) from v_weekly_stock_flow where product_id=%s", (rice,), user=B) == 0)

    check("Storage: Bucket meals ist geschuetzt",
          raises("insert into storage.objects (bucket_id, name) values ('meals', %s)", (f"{hb}/x.jpg",), user=A))

    # --- bls_foods (0014_meal_diary.sql, Phase 7a): globale Referenztabelle, nur lesbar ----------
    db("insert into bls_foods (bls_code, name_de, kcal, protein_g) values ('TEST01', 'Test-Apfel', 52, 0.3)")
    check("bls_foods: authentifizierter Nutzer kann lesen",
          one("select count(*) from bls_foods where bls_code='TEST01'", user=A) == 1)
    check("bls_foods: authentifizierter Nutzer darf nicht einfuegen (nur lesbar, gleiches Muster wie default_categories)",
          raises("insert into bls_foods (bls_code, name_de) values ('TEST02', 'x')", user=A))
    # Ohne UPDATE-Policy filtert RLS die Zeile aus der WHERE-Klausel heraus (0 betroffene Zeilen),
    # statt einen Fehler zu werfen -- anders als beim INSERT oben, wo keine Policy ueberhaupt zutrifft.
    _, updated_rowcount = db("update bls_foods set kcal=0 where bls_code='TEST01'", user=A)
    check("bls_foods: authentifizierter Nutzer darf nicht aendern (RLS filtert die Zeile, 0 betroffen)",
          updated_rowcount == 0)

    # --- Online-Preise (0018, ADR-019): Preis-Snapshots, Feed-Status, Verknuepfung, Suche -------------------------
    ins_price = ("insert into online_prices (store, external_id, name, price_cents, quantity, unit, base_unit, unit_price_norm_cents, seen_at) "
                 "values (%s,%s,%s,%s,%s,%s,%s,%s, now())")
    for row in [
        ("billa", "00-1", "Ja! Natuerlich Bio-Vollmilch 3,5% 1l", 189, 1, "l", "l", 189),
        ("billa", "00-2", "Clever Vollmilch 1l", 129, 1, "l", "l", 129),
        ("billa", "00-3", "Cola Zero 1,5l", 159, 1.5, "l", "l", 106),
        ("billa", "00-4", "Ariel Waschmittelpods", 849, 19, "wg", None, None),
        ("billa", "00-5", "BILLA Vollmilchglasur", 199, 150, "g", "kg", 1327),
        ("billa", "00-6", "Pasabahce Krug 1L", 499, 1, "l", "l", 499),
        ("billa", "00-7", "Schogetten Vollmilch", 199, 100, "g", "kg", 1990),
        ("spar", "2020", "A-zwei Vollmilch laenger frisch 1l", 208, 1, "l", "l", 208),
        ("spar", "2021", "Vollkornbrot Roggen 500g", 249, 500, "g", "kg", 498),
        ("sparSi", "9", "Mleko polnomastno 1l", 99, 1, "l", "l", 99),
    ]:
        db(ins_price, row)
    check("online_prices: authentifizierter Nutzer kann lesen", one("select count(*) from online_prices", user=A) == 10)
    check("online_prices: Nutzer darf nicht einfuegen (nur lesbar)", raises(ins_price, ("billa", "x", "x", 1, 1, "stk", "stk", 1), user=A))
    check("online_prices: Nutzer darf nicht aendern (RLS filtert, 0 betroffen)",
          db("update online_prices set price_cents = 1 where store='billa'", user=A)[1] == 0)
    check("online_prices: Nutzer darf nicht loeschen (RLS filtert, 0 betroffen)",
          db("delete from online_prices where store='billa'", user=A)[1] == 0)
    check("online_prices: unbekannte Basiseinheit wird vom Check abgelehnt",
          raises(ins_price, ("billa", "bad", "x", 1, 1, "stk", "dozen", 1)))
    check("online_prices: Preis darf nicht negativ sein", raises(ins_price, ("billa", "neg", "x", -1, 1, "stk", "stk", 1)))

    db("insert into online_feed_status (source, feed_last_modified, last_success_at, row_counts) values ('heisse_preise', now(), now(), '{\"billa\": 4}')")
    check("online_feed_status: Nutzer kann lesen", one("select count(*) from online_feed_status", user=A) == 1)
    check("online_feed_status: Nutzer darf nicht aendern (RLS filtert, 0 betroffen)",
          db("update online_feed_status set last_error='x'", user=A)[1] == 0)
    check("online_feed_status: Nutzer darf nicht einfuegen", raises("insert into online_feed_status (source) values ('x')", user=A))

    def search(q, **kw):
        stores = kw.get("stores", ["billa", "spar"])
        n = kw.get("n", 8)
        return db("select store, external_id, name from search_online_prices(%s, %s, %s, %s)", (q, stores, n, kw.get("prefer")), user=A)[0]

    vm = search("Vollmilch")
    check("Suche: findet Vollmilch bei Billa und Spar, nicht Cola, Waschmittel oder Krug",
          {r[1] for r in vm} == {"00-1", "00-2", "00-5", "00-7", "2020"}, str(vm))
    check("Suche: kuerzerer Name steht bei gleichem Treffer zuerst", [r[1] for r in vm if r[0] == "billa"][0] == "00-2", str(vm))
    check("Suche: ganzes Wort vor Wortanfang (Vollmilch vor Vollmilchglasur)", [r[1] for r in vm if r[0] == "billa"][-1] == "00-5", str(vm))
    check("Suche: ein Wort mehrfach im Namen (Bindestrich-Wort) zaehlt nicht mehr",
          [r[1] for r in search("Vollmilch", stores=["billa"])][0] == "00-2", str(search("Vollmilch", stores=["billa"])))
    both = [r[1] for r in search("Vollmilch Bio", stores=["billa"])]
    check("Suche: alle Woerter der Anfrage zu treffen schlaegt eines", both[0] == "00-1", str(both))
    plain = [r[1] for r in search("Vollmilch", stores=["billa"])]
    pref_l = [r[1] for r in search("Vollmilch", stores=["billa"], prefer="l")]
    pref_kg = [r[1] for r in search("Vollmilch", stores=["billa"], prefer="kg")]
    check("Suche: ohne Vorliebe entscheidet bei gleicher Wertung der kuerzere Name", plain[:3] == ["00-2", "00-7", "00-1"], str(plain))
    check("Suche: Basiseinheit l bevorzugt (Milch vor Schokolade)", pref_l[:3] == ["00-2", "00-1", "00-7"], str(pref_l))
    check("Suche: Basiseinheit kg bevorzugt", pref_kg[:3] == ["00-7", "00-2", "00-1"], str(pref_kg))
    check("Suche: Basiseinheit schlaegt nur bei gleicher Wertung (Wortanfang-Treffer bleibt hinten)",
          pref_kg[-1] == "00-5" and set(pref_kg) == set(plain))
    check("Suche: Mengen in der Anfrage (1l, 500g) werden ignoriert",
          search("Vollmilch 1l") == vm and search("1l") == [] and search("500g") == [])
    check("Suche: nur die gewuenschten Haendler (sparSi kommt nie vor)", {r[0] for r in search("mleko polnomastno")} == set())
    check("Suche: Haendlerauswahl wird beachtet", {r[0] for r in search("Vollmilch", stores=["spar"])} == {"spar"})
    check("Suche: Begrenzung je Haendler", len([r for r in search("Vollmilch", n=1) if r[0] == "billa"]) == 1)
    check("Suche: Wortanfang genuegt (Vollk -> Vollkornbrot)", [r[1] for r in search("Vollk")] == ["2021"])
    check("Suche: leere Anfrage ergibt nichts, ohne Fehler", search("") == [] and search("  ") == [] and search("a") == [])
    check("Suche: Sonderzeichen der Anfrage brechen die Suche nicht",
          not raises("select * from search_online_prices(%s)", ("vollmilch & | ! ( ) :* ' --",), user=A))

    db("insert into products (household_id, name, base_unit) values (%s,'Milch 1l','l')", (ha,))
    milk = one("select id from products where household_id=%s and name='Milch 1l'", (ha,))
    ins_link = ("insert into product_online_links (household_id, product_id, store, external_id, linked_name) "
                "values (%s,%s,%s,%s,%s)")
    check("Online-Verknuepfung: A kann den eigenen Haushalt verknuepfen", not raises(ins_link, (ha, milk, "billa", "00-2", "Clever Vollmilch 1l"), user=A))
    check("Online-Verknuepfung: B sieht sie nicht", one("select count(*) from product_online_links", user=B) == 0)
    check("Online-Verknuepfung: B kann nicht in Haushalt A verknuepfen",
          raises(ins_link, (ha, milk, "spar", "2020", "x"), user=B))
    check("Online-Verknuepfung: derselbe Artikel nur einmal je Produkt",
          raises(ins_link, (ha, milk, "billa", "00-2", "Clever Vollmilch noch einmal"), user=A))
    check("Online-Verknuepfung: mehrere Artikel desselben Haendlers fuer ein Produkt (Bio und normal)",
          not raises(ins_link, (ha, milk, "billa", "00-1", "Ja! Natuerlich Bio-Vollmilch"), user=A))
    check("Online-Verknuepfung: anderer Haendler fuer dasselbe Produkt geht", not raises(ins_link, (ha, milk, "spar", "2020", "A-zwei Vollmilch"), user=A))
    db("insert into products (household_id, name, base_unit) values (%s,'Milch fettarm','l')", (ha,))
    low_fat = one("select id from products where name='Milch fettarm'")
    check("Online-Verknuepfung: derselbe Artikel darf bei einem anderen Produkt vorkommen",
          not raises(ins_link, (ha, low_fat, "billa", "00-2", "Clever Vollmilch"), user=A))
    check("Online-Verknuepfung: ein Produkt hat jetzt zwei aktive Billa-Artikel",
          one("select count(*) from product_online_links where product_id=%s and store='billa' and deleted_at is null", (milk,)) == 2)
    db("update product_online_links set deleted_at = now() where product_id=%s and store='billa' and external_id='00-2'", (milk,))
    check("Online-Verknuepfung: nach dem Loeschen (Soft-Delete) ist derselbe Artikel wieder verknuepfbar",
          not raises(ins_link, (ha, milk, "billa", "00-2", "Clever Vollmilch"), user=A))
    before_touch = one("select updated_at from product_online_links where store='spar'")
    db("update product_online_links set linked_name='A-zwei Vollmilch 1l' where store='spar'")
    check("Online-Verknuepfung: updated_at wird beim Aendern gesetzt",
          one("select updated_at > %s from product_online_links where store='spar'", (before_touch,)))
    db("delete from products where id=%s", (milk,))
    check("Online-Verknuepfung: faellt mit dem Produkt weg", one("select count(*) from product_online_links where product_id=%s", (milk,)) == 0)
    db("delete from online_prices")
    db("delete from online_feed_status")

    # --- Food Resolver (0022, Phase N1, ADR-031): Zuordnung von Zutatennamen zu BLS-Eintraegen -------------------
    # Mit der ECHTEN BLS (7.140 Eintraege) und den echten Synonymen, damit der Golden-Test die Funktionen so prueft, wie sie
    # auf Produktion laufen. Die SQL-Dateien erzeugen tools/import_bls_foods.py und tools/build_food_synonyms.py.
    import csv
    repo_root = ROOT.parent
    db((repo_root / "tools" / "bls_foods_import.sql").read_text(encoding="utf-8"))
    db((repo_root / "tools" / "food_synonyms_import.sql").read_text(encoding="utf-8"))
    check("BLS: alle 7.140 Eintraege eingespielt", one("select count(*) from bls_foods where bls_code <> 'TEST01'") == 7140)

    norm_cases = [
        ("200 g frische Tomaten", "tomate", "tomate"),
        ("Tomaten", "tomate", "tomate"),
        ("rote Paprika", "rot paprika", "paprika rot"),
        ("Paprika rot", "paprika rot", "paprika rot"),
        ("gekochter Reis", "reis", "reis"),
        ("Crème fraîche", "creme fraiche", "creme fraiche"),
        ("Milch 1,5%", "milch fettarm", "fettarm milch"),
        ("Milch 3,5 %", "milch", "milch"),
        ("Bio Karotten", "karotte", "karotte"),
        ("Kiwis", "kiwi", "kiwi"),
        ("Ananas", "ananas", "ananas"),
        ("Kürbis", "kürbis", "kürbis"),
        ("Reis", "reis", "reis"),
        ("geriebener Käse", "käse", "käse"),
        ("Eier hartgekocht", "eier", "eier"),
        ("Brötchen", "brötchen", "brötchen"),
        ("", "", ""),
        ("123 !!", "", ""),
    ]
    bad_norm = [(t, one("select public.food_core(%s)", (t,)), one("select public.food_key(%s)", (t,)), c, k)
                for t, c, k in norm_cases
                if (one("select public.food_core(%s)", (t,)), one("select public.food_key(%s)", (t,))) != (c, k)]
    check("food_core und food_key: Normalisierung (Plural, Farben, Akzente, Fettstufe, Fuellwoerter, Zustand)", not bad_norm, str(bad_norm[:3]))
    state_cases = [("gekochter Reis", "gekocht"), ("rohe Karotten", "roh"), ("Hähnchen gebraten", "gebraten"), ("gedünstete Zucchini", "gedünstet"),
                   ("Ei hartgekocht", "gekocht"), ("Reis", None), ("Rohschinken", None), ("überbackener Käse", "gebacken")]
    bad_state = [(t, one("select public.food_state(%s)", (t,)), e) for t, e in state_cases if one("select public.food_state(%s)", (t,)) != e]
    check("food_state: Zustandswunsch im Namen (Rohschinken ist kein 'roh')", not bad_state, str(bad_state[:3]))

    # Synonyme
    n_syn = one("select count(*) from food_synonyms")
    check("Synonyme: mindestens 500 eingespielt", n_syn >= 500, str(n_syn))
    check("Synonyme: jeder Begriff ist bereits normalisiert (food_key(term) = term), sonst fand ihn die Suche nie",
          one("select count(*) from food_synonyms where public.food_key(term_norm) <> term_norm") == 0)
    check("Synonyme: Nutzer kann lesen", one("select count(*) from food_synonyms", user=A) == n_syn)
    check("Synonyme: Nutzer darf nicht einfuegen", raises("insert into food_synonyms (term_norm, bls_code) values ('x', 'C352000')", user=A))
    check("Synonyme: Nutzer darf nicht aendern (RLS filtert, 0 betroffen)", db("update food_synonyms set bls_code = 'C352000'", user=A)[1] == 0)
    check("Synonyme: Code muss in der BLS existieren", raises("insert into food_synonyms (term_norm, bls_code) values ('zzz', 'NICHT00')"))

    def top1(name, **kw):
        r = db("select bls_code, name_de, method, confidence, coverage from search_bls_foods(%s, %s, %s, %s)",
               (name, kw.get("n", 1), kw.get("household"), kw.get("loose", False)), user=kw.get("user", A))[0]
        return r[0] if r else None

    def code1(name, **kw):
        r = top1(name, **kw)
        return r[0] if r else None

    # Golden-Test: 380+ Alltagsnamen mit erwartetem BLS-Code (tools/food_golden.csv)
    golden = list(csv.DictReader((repo_root / "tools" / "food_golden.csv").open(encoding="utf-8", newline="")))
    syn_terms = {r[0] for r in db("select term_norm from food_synonyms")[0]}
    ok = held = held_ok = silent = unsure_miss = 0
    problems = []
    for g in golden:
        name, expected, mode = g["name"], {x for x in g["expected"].split("|") if x}, g["mode"]
        r = top1(name)
        is_held = one("select public.food_key(%s)", (name,)) not in syn_terms
        held += is_held
        sure = bool(r) and r[3] in ("sure", "auto")
        if mode == "none":
            good = not sure
        elif r and r[0] in expected:
            good = sure or mode == "top"
        else:
            good = False
        if r and sure and (mode == "none" or r[0] not in expected):
            silent += 1
            problems.append(f"STILL FALSCH {name}: {r[1]} [{r[0]}]")
        elif not good:
            unsure_miss += 1
            problems.append(f"daneben {name}: {r[1] if r else 'kein Treffer'}")
        ok += good
        held_ok += good and is_held
    check(f"Golden-Test: {len(golden)} Namen, mindestens 95 % richtig ({ok} = {ok / len(golden):.1%})", ok / len(golden) >= 0.95, "; ".join(problems[:4]))
    check(f"Golden-Test: auch ausserhalb der Synonyme mindestens 90 % ({held_ok} von {held})", held and held_ok / held >= 0.90, "; ".join(problems[:4]))
    check("Golden-Test: nie stillschweigend falsch (sicher oder automatisch zugeordnet, aber falscher Eintrag)", silent == 0, "; ".join(problems[:4]))

    check("Suche: Zustand aus dem Namen waehlt das Geschwister (gekochter Reis -> Reis gekocht)", code1("gekochter Reis") == "C352032")
    check("Suche: Zustand gedünstet (Karotten gedünstet)", code1("Karotten gedünstet") == "G620152")
    check("Suche: Zustand gebraten (Pfanne) bei Haehnchenbrust", code1("Hähnchenbrust gebraten") == "V416182")
    check("Suche: ohne Geschwister bleibt es beim rohen Eintrag (gekochte Banane)", code1("gekochte Banane") == "F503100")
    check("Suche: ohne Zustandswunsch der rohe Eintrag", code1("Karotten") == "G620100")
    r = db("select bls_code, method, confidence from search_bls_foods('Reis', 1, null, false)", user=A)[0][0]
    check("Suche: Synonym ist sicher (Reis)", r[1] == "synonym" and r[2] == "sure", str(r))
    r = db("select bls_code, method, confidence from search_bls_foods('Kohlrabi', 1, null, false)", user=A)[0][0]
    check("Suche: eindeutiger Name der BLS ist automatisch, ohne Synonym (Kohlrabi)", r == ("G331100", "search", "auto"), str(r))
    check("Suche: Kirschen ergibt die Kirsche und nicht Weinbrand-Kirschen (Synonym vor Zufallstreffer)", code1("Kirschen") == "F211100")
    check("Suche: nur Rang 1 kann sicher oder automatisch sein, alle anderen Treffer sind 'unsure'",
          all(c == "unsure" for (rk, c) in db("select rank, confidence from search_bls_foods('Apfel', 8)", user=A)[0] if rk > 1))
    check("Suche: leere und unsinnige Anfragen ergeben nichts, ohne Fehler",
          db("select count(*) from search_bls_foods('')", user=A)[0][0][0] == 0
          and db("select count(*) from search_bls_foods(%s)", ("'; drop table bls_foods; --",), user=A)[0][0][0] >= 0
          and db("select count(*) from search_bls_foods('123')", user=A)[0][0][0] == 0)
    check("Suche: Anzahl der Treffer ist begrenzt (n = 100 ergibt hoechstens 25)", db("select count(*) from search_bls_foods('Apfel', 100)", user=A)[0][0][0] <= 25)
    strict_n = db("select count(*) from search_bls_foods('Paprika rot geröstet', 10, null, false)", user=A)[0][0][0]
    loose_n = db("select count(*) from search_bls_foods('Paprika rot geröstet', 10, null, true)", user=A)[0][0][0]
    check("Suche: lockere Suche findet auch Namen mit nur einem Teil der Woerter", loose_n > strict_n, f"{strict_n} / {loose_n}")
    check("Suche: liefert die acht Naehrwerte des Eintrags mit",
          one("select s.kcal is not distinct from f.kcal and s.protein_g is not distinct from f.protein_g and s.salt_g is not distinct from f.salt_g "
              "from search_bls_foods('Apfel', 1) s join bls_foods f on f.bls_code = s.bls_code", user=A))

    # Gedaechtnis des Haushalts
    paprika_gruen = "G541100"
    ins_food_link = "insert into household_food_links (household_id, name_norm, bls_code) values (%s,%s,%s)"
    check("Gedaechtnis: A kann die eigene Zuordnung anlegen", not raises(ins_food_link, (ha, one("select public.food_key('Paprika')"), paprika_gruen), user=A))
    r = db("select bls_code, method, confidence from search_bls_foods('Paprika', 1)", user=A)[0][0]
    check("Gedaechtnis: eigene Zuordnung geht vor das Synonym (Paprika -> gruen), sicher", r == (paprika_gruen, "memory", "sure"), str(r))
    r = db("select bls_code, method from search_bls_foods('frische Paprika', 1)", user=A)[0][0]
    check("Gedaechtnis: gilt auch fuer Schreibvarianten (frische Paprika)", r == (paprika_gruen, "memory"), str(r))
    r = db("select bls_code, method from search_bls_foods('Paprika', 1)", user=B)[0][0]
    check("Gedaechtnis: Haushalt B sieht die Zuordnung von A nicht, bekommt das Synonym", r == ("G543100", "synonym"), str(r))
    check("Gedaechtnis: B sieht die Zeile nicht", one("select count(*) from household_food_links", user=B) == 0)
    check("Gedaechtnis: B kann nicht in Haushalt A schreiben", raises(ins_food_link, (ha, "x", paprika_gruen), user=B))
    r = db("select bls_code, method from search_bls_foods('Paprika', 1, %s)", (ha,))[0][0]
    check("Gedaechtnis: mit Haushaltsangabe (Service-Aufruf) wird das Gedaechtnis dieses Haushalts genutzt", r == (paprika_gruen, "memory"), str(r))
    r = db("select bls_code, method from search_bls_foods('Paprika', 1, %s)", (hb,))[0][0]
    check("Gedaechtnis: mit dem anderen Haushalt nicht", r == ("G543100", "synonym"), str(r))
    db("update household_food_links set deleted_at = now() where household_id = %s", (ha,))
    r = db("select bls_code, method from search_bls_foods('Paprika', 1)", user=A)[0][0]
    check("Gedaechtnis: eine geloeschte Zuordnung gilt nicht mehr", r == ("G543100", "synonym"), str(r))
    check("Gedaechtnis: nach dem Loeschen ist der Name wieder zuordenbar",
          not raises(ins_food_link, (ha, one("select public.food_key('Paprika')"), "G542100"), user=A))
    before_touch = one("select updated_at from household_food_links where deleted_at is null and household_id = %s", (ha,))
    db("update household_food_links set bls_code = 'G541100' where deleted_at is null and household_id = %s", (ha,))
    check("Gedaechtnis: updated_at wird beim Aendern gesetzt",
          one("select updated_at > %s from household_food_links where deleted_at is null and household_id = %s", (before_touch, ha)))
    db("delete from household_food_links")
    # Der Server normalisiert den Namen (die App schickt ihn roh)
    db(ins_food_link, (ha, "Frische Rote Paprika", "G543100"))
    check("Gedaechtnis: der Name wird beim Speichern zum Schluessel (Frische Rote Paprika -> paprika rot)",
          one("select name_norm from household_food_links where household_id = %s", (ha,)) == "paprika rot")
    # Die App kennt den Schluessel nicht und legt dafuer eine neue Zeile an: die darf nie dauerhaft in der Outbox haengen bleiben (0031)
    check("Gedaechtnis: derselbe Name in anderer Schreibweise wird angenommen", not raises(ins_food_link, (ha, "paprika, ROTE", "G542100"), user=A))
    check("Gedaechtnis: die neue Zuordnung gilt",
          one("select bls_code from household_food_links where deleted_at is null and household_id = %s", (ha,)) == "G542100")
    check("Gedaechtnis: es bleibt eine aktive Zeile, die alte ist weich geloescht",
          one("select count(*) filter (where deleted_at is null) || '/' || count(*) from household_food_links where household_id = %s", (ha,)) == "1/2")
    db("update household_food_links set unit_weight_g = 150 where deleted_at is null and household_id = %s", (ha,))
    db(ins_food_link, (ha, "Rote Paprika", "G542100"))
    check("Gedaechtnis: bei gleichem Eintrag bleibt das Stueckgewicht",
          float(one("select unit_weight_g from household_food_links where deleted_at is null and household_id = %s", (ha,))) == 150.0)
    db(ins_food_link, (ha, "Rote Paprika", "G543100"))
    check("Gedaechtnis: bei anderem Eintrag faellt das Stueckgewicht weg",
          one("select unit_weight_g from household_food_links where deleted_at is null and household_id = %s", (ha,)) is None)
    db("delete from household_food_links where deleted_at is not null and household_id = %s", (ha,))
    check("Gedaechtnis: ein Name ohne Kernwoerter wird abgelehnt", raises(ins_food_link, (ha, "200 g", "G543100")))
    db("update household_food_links set name_norm = 'Gelbe Paprika' where household_id = %s", (ha,))
    check("Gedaechtnis: auch beim Aendern des Namens", one("select name_norm from household_food_links where household_id = %s", (ha,)) == "gelb paprika")
    db("delete from household_food_links")

    # Spalten fuer die Herkunft der Naehrwerte (0023)
    db("insert into meals (household_id, eaten_at, title) values (%s, now(), 'Test N1')", (ha,))
    meal_n1 = one("select id from meals where title = 'Test N1'")
    ins_ing = ("insert into meal_ingredients (household_id, meal_id, free_text, quantity, unit, bls_code, nutrient_basis) "
               "values (%s,%s,'Paprika',0.1,'kg',%s,%s)")
    check("Zutat: bls_code und nutrient_basis lassen sich speichern", not raises(ins_ing, (ha, meal_n1, "G543100", "bls_matched")))
    check("Zutat: unbekannter BLS-Code wird abgelehnt (Fremdschluessel)", raises(ins_ing, (ha, meal_n1, "NICHT00", "bls_matched")))
    check("Zutat: unbekannte nutrient_basis wird abgelehnt", raises(ins_ing, (ha, meal_n1, "G543100", "geraten")))
    for basis in ("product", "bls_exact", "bls_matched", "llm_estimate", "manual", "unknown"):
        check(f"Zutat: nutrient_basis {basis} erlaubt", not raises(ins_ing, (ha, meal_n1, None, basis)))
    db("update products set bls_code = 'G543100' where household_id = %s", (ha,))
    check("Produkt: bls_code lässt sich setzen", one("select count(*) from products where household_id = %s and bls_code = 'G543100'", (ha,)) >= 1)
    check("Produkt: unbekannter BLS-Code wird abgelehnt", raises("update products set bls_code = 'NICHT00' where household_id = %s", (ha,)))
    db("delete from meals where id = %s", (meal_n1,))
    db("update products set bls_code = null")

    # --- Stueckgewichte (0024, Phase N2, ADR-033) ------------------------------------------------------------------
    db((repo_root / "tools" / "food_units_import.sql").read_text(encoding="utf-8"))
    n_units = one("select count(*) from food_units")
    check("Einheiten: Import eingespielt (mehr als 150 Zeilen)", n_units > 150, n_units)
    check("Einheiten: jede Zeile gehoert zu einem BLS-Eintrag",
          one("select count(*) from food_units u left join bls_foods b using (bls_code) where b.bls_code is null") == 0)
    check("Einheiten: Banane, 1 Stueck mittel = 118 g (USDA)",
          float(one("select grams_edible from food_units where bls_code = 'F503100' and unit_key = 'piece' and size = 'medium'")) == 118.0)
    check("Einheiten: Olivenoel, 1 EL = 13,5 g",
          float(one("select grams_edible from food_units where bls_code = 'Q120000' and unit_key = 'tbsp' and size = ''")) == 13.5)
    check("Einheiten: Ei Groesse M = 50 g, L = 56 g (USDA large und extra large, auf EU-Groessen umbenannt)",
          [float(r[0]) for r in db("select grams_edible from food_units where bls_code = 'E111100' and unit_key = 'piece' "
                                   "and size in ('medium', 'large') order by size desc")[0]] == [50.0, 56.0])
    check("Einheiten: Groessen gibt es nur bei Stueck, Kopf und Stange",
          one("select count(*) from food_units where size <> '' and unit_key not in ('piece', 'head', 'stalk')") == 0)
    check("Einheiten: Nutzer kann lesen", one("select count(*) from food_units", user=A) == n_units)
    ins_unit = "insert into food_units (bls_code, unit_key, size, grams_edible, source) values (%s,%s,%s,%s,%s)"
    check("Einheiten: Nutzer darf nicht einfuegen", raises(ins_unit, ("C352000", "tbsp", "", 15, "usda"), user=A))
    check("Einheiten: Nutzer darf nicht aendern (RLS filtert, 0 betroffen)", db("update food_units set grams_edible = 1", user=A)[1] == 0)
    check("Einheiten: Nutzer darf nicht loeschen (RLS filtert, 0 betroffen)", db("delete from food_units", user=A)[1] == 0)
    check("Einheiten: Eintrag mit gueltigen Werten wird angenommen", not raises(ins_unit, ("C352000", "tbsp", "", 15, "curated")))
    check("Einheiten: dieselbe Einheit und Groesse zweimal wird abgelehnt (Primaerschluessel)", raises(ins_unit, ("C352000", "tbsp", "", 16, "curated")))
    check("Einheiten: Gewicht 0 wird abgelehnt", raises(ins_unit, ("C352000", "tsp", "", 0, "curated")))
    check("Einheiten: negatives Gewicht wird abgelehnt", raises(ins_unit, ("C352000", "tsp", "", -3, "curated")))
    check("Einheiten: Gewicht ueber 5 kg wird abgelehnt", raises(ins_unit, ("C352000", "tsp", "", 5001, "curated")))
    check("Einheiten: unbekannte Einheit wird abgelehnt", raises(ins_unit, ("C352000", "handvoll", "", 20, "curated")))
    check("Einheiten: unbekannte Groesse wird abgelehnt", raises(ins_unit, ("C352000", "piece", "riesig", 20, "curated")))
    check("Einheiten: unbekannte Quelle wird abgelehnt", raises(ins_unit, ("C352000", "tsp", "", 5, "geraten")))
    check("Einheiten: unbekannter BLS-Code wird abgelehnt", raises(ins_unit, ("NICHT00", "tsp", "", 5, "curated")))
    for key in ("piece", "slice", "tbsp", "tsp", "clove", "head", "stalk"):
        check(f"Einheiten: {key} erlaubt", not raises(ins_unit, ("C351000", key, "", 5, "llm_estimate")))
    for size in ("small", "medium", "large"):
        check(f"Einheiten: Groesse {size} erlaubt", not raises(ins_unit, ("C351000", "piece", size, 5, "off")))
    db("delete from food_units where bls_code in ('C352000', 'C351000')")
    db((repo_root / "tools" / "food_units_import.sql").read_text(encoding="utf-8"))
    check("Einheiten: der Import laesst sich wiederholen (on conflict), keine Doppelten", one("select count(*) from food_units") == n_units)
    db("insert into bls_foods (bls_code, name_de) values ('CASC01', 'Wegwerf')")
    db(ins_unit, ("CASC01", "piece", "", 10, "curated"))
    db("delete from bls_foods where bls_code = 'CASC01'")
    check("Einheiten: fallen mit dem BLS-Eintrag weg (cascade)", one("select count(*) from food_units where bls_code = 'CASC01'") == 0)

    # Eigenes Stueckgewicht im Gedaechtnis des Haushalts (0024)
    check("Gedaechtnis: eigenes Stueckgewicht lässt sich speichern",
          not raises("insert into household_food_links (household_id, name_norm, bls_code, unit_weight_g) values (%s,'banane','F503100',135)", (ha,), user=A))
    check("Gedaechtnis: Stueckgewicht ist lesbar", float(one("select unit_weight_g from household_food_links where household_id = %s", (ha,))) == 135.0)
    check("Gedaechtnis: Stueckgewicht 0 wird abgelehnt", raises("update household_food_links set unit_weight_g = 0 where household_id = %s", (ha,)))
    check("Gedaechtnis: Stueckgewicht ueber 5 kg wird abgelehnt", raises("update household_food_links set unit_weight_g = 6000 where household_id = %s", (ha,)))
    check("Gedaechtnis: ohne Stueckgewicht (null) bleibt moeglich", not raises("update household_food_links set unit_weight_g = null where household_id = %s", (ha,)))
    db("delete from household_food_links")

    # --- Mikronaehrstoffe (0025, Phase N3, ADR-032) ------------------------------------------------------------------
    db((repo_root / "tools" / "bls_nutrients_import.sql").read_text(encoding="utf-8"))
    check("Mikronaehrstoffe: alle 7.140 BLS-Eintraege haben ein nutrients-Objekt",
          one("select count(*) from bls_foods where bls_code <> 'TEST01' and nutrients is not null") == 7140)
    check("Mikronaehrstoffe: hoechstens 38 Schluessel je Eintrag",
          one("select max((select count(*) from jsonb_object_keys(nutrients))) from bls_foods where nutrients is not null") <= 38)
    check("Mikronaehrstoffe: alle Werte sind Zahlen und nicht negativ",
          one("select count(*) from bls_foods b, jsonb_each(b.nutrients) e where jsonb_typeof(e.value) <> 'number' or (e.value)::numeric < 0") == 0)
    check("Mikronaehrstoffe: Banane hat 11 mg Vitamin C und 334 mg Kalium",
          [float(x) for x in db("select nutrients->>'vit_c_mg', nutrients->>'potassium_mg' from bls_foods where bls_code = 'F503100'")[0][0]] == [11.0, 334.0])
    check("Mikronaehrstoffe: Vitamin B6 und Kupfer sind von ug in mg umgerechnet (Banane unter 1 mg B6)",
          float(one("select nutrients->>'vit_b6_mg' from bls_foods where bls_code = 'F503100'")) < 1)
    check("Mikronaehrstoffe: ein fehlender Wert ist ein fehlender Schluessel, keine 0 (Jod fehlt bei vielen Eintraegen)",
          one("select count(*) from bls_foods where bls_code <> 'TEST01' and not (nutrients ? 'iodine_ug')") > 100)
    check("Mikronaehrstoffe: eine echte Null bleibt 0 (Vitamin D der Banane)",
          float(one("select nutrients->>'vit_d_ug' from bls_foods where bls_code = 'F503100'")) == 0.0)
    check("Mikronaehrstoffe: Nutzer kann lesen", one("select count(*) from bls_foods where nutrients is not null", user=A) >= 7140)
    check("Mikronaehrstoffe: Nutzer darf nicht aendern (RLS filtert, 0 betroffen)", db("update bls_foods set nutrients = '{}'::jsonb", user=A)[1] == 0)
    check("Mikronaehrstoffe: ein Array als nutrients wird abgelehnt", raises("update bls_foods set nutrients = '[1]'::jsonb where bls_code = 'F503100'"))
    check("Suche: liefert die Naehrstoffe mit (Banane, Vitamin C 11 mg)",
          float(one("select nutrients->>'vit_c_mg' from search_bls_foods('Banane', 1)")) == 11.0)
    check("Suche: die Reihung ist unveraendert (Rang 1 zuerst, Synonym Paprika -> Gemuesepaprika rot)",
          [r[0] for r in db("select bls_code from search_bls_foods('Paprika', 3)")[0]][0] == "G543100")
    check("Suche: die Basisfunktion gibt es weiter", one("select count(*) from search_bls_foods_base('Banane', 1)") == 1)

    db("insert into meals (household_id, eaten_at, title) values (%s, now(), 'Test N3')", (ha,))
    meal_n3 = one("select id from meals where title = 'Test N3'")
    ins_micro = ("insert into meal_ingredients (household_id, meal_id, free_text, quantity, unit, micros) "
                 "values (%s,%s,'Banane',0.12,'kg',%s::jsonb)")
    check("Zutat: micros als Objekt lassen sich speichern", not raises(ins_micro, (ha, meal_n3, '{"vit_c_mg": 13.2, "iron_mg": 0.5}')))
    check("Zutat: micros ohne Werte (null) bleiben moeglich", not raises("insert into meal_ingredients (household_id, meal_id, free_text, quantity, unit) values (%s,%s,'Etwas',1,'piece')", (ha, meal_n3)))
    check("Zutat: micros als Array werden abgelehnt", raises(ins_micro, (ha, meal_n3, '[1,2]')))
    check("Zutat: micros als Zahl werden abgelehnt", raises(ins_micro, (ha, meal_n3, '5')))
    db("delete from meals where id = %s", (meal_n3,))

    # --- Haushalts-Einladungen (0017, Phase 6, ADR-017 Option A) -----------------------------------------------
    import re
    codes = [one("select new_invite_code()") for _ in range(300)]
    check("Einladungscode: 12 Zeichen aus dem Alphabet ohne I, L, O, 0, 1",
          all(re.fullmatch(r"[A-HJKMNP-Z2-9]{12}", c) for c in codes), codes[0])
    check("Einladungscode: 300 Codes sind alle verschieden", len(set(codes)) == 300)

    ins_inv = "insert into household_invites (household_id, invited_by, email) values (%s,%s,%s)"
    check("Einladung: Mitglied A kann in den eigenen Haushalt einladen", not raises(ins_inv, (ha, A, "neu@test.at"), user=A))
    check("Einladung: Code wird automatisch vergeben (12 Zeichen)",
          re.fullmatch(r"[A-Z0-9]{12}", one("select token from household_invites where email='neu@test.at'")) is not None)
    check("Einladung: B kann nicht in Haushalt A einladen (RLS)", raises(ins_inv, (ha, B, "fremd@test.at"), user=B))
    check("Einladung: A kann nicht im Namen von B einladen (invited_by = auth.uid())", raises(ins_inv, (ha, B, "x@test.at"), user=A))
    check("Einladung: Rolle owner wird abgelehnt (nur member)",
          raises("insert into household_invites (household_id, invited_by, email, role) values (%s,%s,'o@test.at','owner')", (ha, A), user=A))
    check("Einladung: E-Mail muss klein geschrieben und ohne Leerzeichen am Rand sein", raises(ins_inv, (ha, A, "Gross@Test.at"), user=A))
    check("Einladung: E-Mail muss wie eine Adresse aussehen", raises(ins_inv, (ha, A, "keine-adresse"), user=A))
    check("Einladung: zweite offene Einladung fuer dieselbe Adresse wird abgelehnt", raises(ins_inv, (ha, A, "neu@test.at"), user=A))
    check("RLS: B sieht keine Einladungen von A", one("select count(*) from household_invites", user=B) == 0)
    check("RLS: A sieht die eigenen Einladungen", one("select count(*) from household_invites", user=A) == 1)
    check("Einladung: Client kann Code und Ablauf nicht aendern (keine Update-Policy, 0 betroffen)",
          db("update household_invites set expires_at = now() + interval '1 year'", user=A)[1] == 0)

    for fn in ("peek_invite('X','x@test.at')", "redeem_invite('X', gen_random_uuid())"):
        check(f"Einladung: authentifizierter Client darf {fn.split('(')[0]} nicht aufrufen", raises(f"select * from {fn}", user=A))
    check("Einladung: service_role darf pruefen und einloesen",
          one("select has_function_privilege('service_role', 'public.peek_invite(text,text)', 'execute')")
          and one("select has_function_privilege('service_role', 'public.redeem_invite(text,uuid)', 'execute')"))

    def peek(token, email):
        return db("select status, household_id from peek_invite(%s,%s)", (token, email))[0][0]

    token = one("select token from household_invites where email='neu@test.at'")
    check("Pruefen: unbekannter Code -> not_found", peek("AAAAAAAAAAAA", "neu@test.at")[0] == "not_found")
    check("Pruefen: Code mit Kleinbuchstaben und Leerzeichen wird normalisiert, Adresse ebenso -> ok",
          peek(f" {token.lower()} ", " Neu@Test.at ") == ("ok", ha))
    check("Pruefen: falsche Adresse -> email_mismatch", peek(token, "anders@test.at")[0] == "email_mismatch")
    check("Pruefen: Fehlversuch wird gezaehlt (nicht mit der Ausnahme zurueckgerollt)",
          one("select failed_attempts from household_invites where token=%s", (token,)) == 1)
    for _ in range(4):
        peek(token, "anders@test.at")
    check("Pruefen: nach 5 Fehlversuchen ist der Code gesperrt, auch mit richtiger Adresse", peek(token, "neu@test.at")[0] == "locked")
    db("update household_invites set failed_attempts = 0 where token=%s", (token,))

    db(ins_inv, (ha, A, "spaet@test.at"))
    t_exp = one("select token from household_invites where email='spaet@test.at'")
    db("update household_invites set expires_at = now() - interval '1 minute' where token=%s", (t_exp,))
    check("Pruefen: abgelaufene Einladung -> expired", peek(t_exp, "spaet@test.at")[0] == "expired")

    # Annahme: eingeladener Nutzer entsteht per Admin-API mit app_metadata.invited_to, bekommt keinen eigenen Haushalt
    households_before = one("select count(*) from households")
    NEW = "33333333-3333-3333-3333-333333333333"
    db("insert into auth.users (id, email, raw_app_meta_data) values (%s, 'neu@test.at', jsonb_build_object('invited_to', %s::text))", (NEW, str(ha)))
    check("Signup-Trigger: eingeladener Nutzer (invited_to) bekommt keinen eigenen Haushalt",
          one("select count(*) from households") == households_before and one("select count(*) from household_members where user_id=%s", (NEW,)) == 0)
    check("Einloesen: gibt den Haushalt zurueck", str(one("select redeem_invite(%s, %s)", (token.lower(), NEW))) == str(ha))
    check("Einloesen: Mitgliedschaft mit Rolle member",
          db("select role::text from household_members where user_id=%s and household_id=%s", (NEW, ha))[0][0][0] == "member")
    check("Einloesen: Einladung ist als angenommen markiert (Zeitpunkt und Nutzer)",
          db("select accepted_at is not null, accepted_by = %s from household_invites where token=%s", (NEW, token))[0][0] == (True, True))
    check("Einloesen: derselbe Code ein zweites Mal wird abgelehnt", raises("select redeem_invite(%s, %s)", (token, A)))
    check("Pruefen: eingeloeste Einladung -> used", peek(token, "neu@test.at")[0] == "used")
    check("Einloesen: abgelaufene Einladung wird abgelehnt", raises("select redeem_invite(%s, %s)", (t_exp, B)))
    check("Neues Mitglied sieht die Daten des Haushalts (RLS ueber household_members)",
          one("select count(*) from stores", user=NEW) == one("select count(*) from stores where household_id=%s", (ha,)))
    check("Neues Mitglied sieht den Haushalt von B nicht", one("select count(*) from stores where household_id=%s", (hb,), user=NEW) == 0)
    check("Angenommene Einladung kann nicht mehr zurueckgezogen werden (0 betroffen)",
          db("delete from household_invites where token=%s", (token,), user=A)[1] == 0)

    db(ins_inv, (ha, A, "zurueck@test.at"))
    check("Offene Einladung kann das Mitglied zurueckziehen",
          db("delete from household_invites where email='zurueck@test.at'", user=A)[1] == 1)
    check("B kann Einladungen von A nicht zurueckziehen", db("delete from household_invites where email='spaet@test.at'", user=B)[1] == 0)

    db("insert into auth.users (id, email) values (gen_random_uuid(), 'normal@test.at')")
    check("Signup-Trigger: normale Registrierung legt weiterhin einen Haushalt an", one("select count(*) from households") == households_before + 1)

    # Haushaltsgroesse: ab 10 Mitgliedern keine Annahme mehr
    db("delete from household_invites where accepted_at is null")
    members_now = one("select count(*) from household_members where household_id=%s", (ha,))
    for i in range(10 - members_now):
        db("insert into auth.users (id, email, raw_app_meta_data) values (gen_random_uuid(), %s, jsonb_build_object('invited_to', %s::text)) ",
           (f"m{i}@test.at", str(ha)))
        uid = one("select id from auth.users where email=%s", (f"m{i}@test.at",))
        db("insert into household_members (household_id, user_id) values (%s,%s)", (ha, uid))
    db(ins_inv, (ha, A, "elfte@test.at"))
    t_full = one("select token from household_invites where email='elfte@test.at'")
    check("Haushalt mit 10 Mitgliedern: Pruefen meldet full", peek(t_full, "elfte@test.at")[0] == "full")
    check("Haushalt mit 10 Mitgliedern: Einloesen wird abgelehnt", raises("select redeem_invite(%s, %s)", (t_full, B)))

    # Hoechstens 20 offene Einladungen je Haushalt (Missbrauchsschutz)
    db("delete from household_invites where accepted_at is null")
    for i in range(20):
        db(ins_inv, (ha, A, f"bulk{i}@test.at"))
    check("Hoechstens 20 offene Einladungen je Haushalt", raises(ins_inv, (ha, A, "bulk21@test.at"), user=A))
    db("delete from household_invites where accepted_at is null")


    # --- Vertrag App <-> Schema: Zeilen, die die App fuers Essenstagebuch zum Server schickt -----------------------
    # `app/test/payload_contract_test.dart` erzeugt sie mit den echten Repositories (Mahlzeit anlegen, aendern, loeschen,
    # Abzug und Gegenbuchung, Richtwerte) aus der Outbox. Hier laufen sie in der Reihenfolge des Syncs in das echte Schema:
    # eine Spalte, die es nicht gibt, ein abgelehntes Enum oder eine verletzte Check-Regel faellt sonst erst auf dem Geraet
    # auf, wenn alle Mahlzeiten als "Datenfehler" in der Outbox haengen bleiben.
    import json
    from psycopg.types.json import Jsonb

    fixture = pathlib.Path(__file__).parent / "fixtures" / "app_payloads.json"
    entries = json.loads(fixture.read_text(encoding="utf-8"))["entries"]
    jsonb_cols = {(t, c) for t, c in db("select table_name, column_name from information_schema.columns "
                                        "where table_schema='public' and data_type='jsonb'")[0]}
    contract_failures = []
    for e in entries:
        table, row = e["table"], dict(e["payload"])
        if "household_id" in row:
            row["household_id"] = str(ha)
        cols = list(row)
        vals = [Jsonb(row[c]) if (table, c) in jsonb_cols and row[c] is not None else row[c] for c in cols]
        key_cols = {"nutrition_targets": ["household_id"], "household_prefs": ["household_id", "key"], "product_barcodes": ["household_id", "ean"]}.get(table, ["id"])
        updates = ", ".join(f"{c}=excluded.{c}" for c in cols if c not in key_cols)
        sql = (f"insert into public.{table} ({', '.join(cols)}) values ({', '.join(['%s'] * len(cols))}) "
               f"on conflict ({', '.join(key_cols)}) do update set {updates}")
        try:
            db(sql, vals)
        except psycopg.Error as ex:
            contract_failures.append(f"{table}: {str(ex).splitlines()[0]}")
    tables_in_fixture = {e["table"] for e in entries}
    check("Vertrag: Fixture enthaelt Tagebuch, Ledger, Richtwerte, Ergaenzungen und Einstellungen",
          {"meals", "meal_ingredients", "inventory_movements", "nutrition_targets", "supplements", "supplement_intakes", "household_prefs", "meal_plan_entries", "cooking_sessions"} <= tables_in_fixture,
          str(tables_in_fixture))
    check(f"Vertrag: alle {len(entries)} Zeilen der App werden vom echten Schema angenommen", not contract_failures, "; ".join(contract_failures[:3]))
    meal_ids = [e["payload"]["id"] for e in entries if e["table"] == "meals"]
    check("Vertrag: die eingespielten Mahlzeiten liegen in der Datenbank (Soft-Delete eingeschlossen)",
          one("select count(*) from meals where id = any(%s::uuid[])", (meal_ids,)) == len(set(meal_ids)))
    check("Vertrag: Gegenbuchung der geloeschten Mahlzeit ist mit meal_id verknuepft",
          one("select count(*) from inventory_movements where type='adjustment' and meal_id = any(%s::uuid[])", (meal_ids,)) >= 1)

    # --- Mehrfachpackungen (Migration 0035) ------------------------------------------------------------------------------
    check("Mehrfachpackung: das Produkt aus dem Fixture traegt Stueckzahl und Namen",
          one("select count(*) from products where household_id = %s and pieces_per_pack = 6 and piece_label = 'Fläschchen'", (ha,)) == 1)
    upd_pack = "update products set pieces_per_pack = %s where household_id = %s and pieces_per_pack = 6"
    check("Mehrfachpackung: eine Stueckzahl unter 2 wird abgelehnt", raises(upd_pack, (1, ha)))
    check("Mehrfachpackung: ein leerer Name wird abgelehnt",
          raises("update products set piece_label = '  ' where household_id = %s and pieces_per_pack = 6", (ha,)))

    # Bereinigung (tools/mengenkonzept_bereinigung_2026-11-02.sql): Yakult wie bisher gespeichert, ein Bon-Vorschlag in Stueck auf einem kg-Produkt
    alt = one("insert into products (household_id, name, base_unit, pack_size) values (%s, 'Yakult Drink', 'piece', 0.39) returning id", (hb,))
    nudeln = one("insert into products (household_id, name, base_unit, pack_size) values (%s, 'Nudeln alt', 'kg', 0.5) returning id", (hb,))
    lose = one("insert into products (household_id, name, base_unit) values (%s, 'Aepfel alt', 'kg') returning id", (hb,))
    ins_item = "insert into inventory_items (household_id, product_id, quantity, unit, is_suggestion) values (%s,%s,%s,'piece',%s) returning id"
    i_alt = one(ins_item, (hb, alt, 6, False))
    i_nudeln = one(ins_item, (hb, nudeln, 2, True))
    i_lose = one(ins_item, (hb, lose, 3, True))
    ins_move = "insert into inventory_movements (household_id, inventory_item_id, product_id, type, quantity_delta, unit) values (%s,%s,%s,%s,%s,'piece')"
    db(ins_move, (hb, i_alt, alt, "purchase", 1))
    db(ins_move, (hb, i_alt, alt, "adjustment", 5))
    db(ins_move, (hb, i_nudeln, nudeln, "purchase", 2))
    script = (pathlib.Path(__file__).parents[2] / "tools" / "mengenkonzept_bereinigung_2026-11-02.sql").read_text(encoding="utf-8")
    for _ in range(2):  # zweimal: mehrfach ausfuehrbar
        db(script)
    stand = lambda i: db("select quantity::float8, unit::text from inventory_items where id = %s", (i,))[0][0]
    check("Bereinigung: 6 Flaeschchen werden zu 0,39 l", stand(i_alt) == (0.39, "l"), str(stand(i_alt)))
    check("Bereinigung: 2 Packungen aus dem Bon werden zu 1 kg", stand(i_nudeln) == (1.0, "kg"), str(stand(i_nudeln)))
    check("Bereinigung: ohne bekannten Inhalt bleibt der Bestand", stand(i_lose) == (3.0, "piece"), str(stand(i_lose)))
    check("Bereinigung: das Produkt ist eine Mehrfachpackung",
          db("select base_unit::text, pieces_per_pack, piece_label from products where id = %s", (alt,))[0][0] == ("l", 6, "Fläschchen"))
    check("Bereinigung: die Buchungen wandern mit, ihre Summe ist der Bestand",
          db("select sum(quantity_delta)::float8, min(unit::text), count(*) from inventory_movements where inventory_item_id = %s", (i_alt,))[0][0] == (0.39, "l", 2))
    db("delete from inventory_movements where inventory_item_id = any(%s::uuid[])", ([i_alt, i_nudeln, i_lose],))
    db("delete from inventory_items where id = any(%s::uuid[])", ([i_alt, i_nudeln, i_lose],))
    db("delete from products where id = any(%s::uuid[])", ([alt, nudeln, lose],))

    # --- Einkaufsliste archivieren (Migration 0034) ---------------------------------------------------------------------
    check("Archiv: der abgeschlossene Einkauf aus dem Fixture traegt seinen Zeitstempel",
          one("select count(*) from shopping_list_items where household_id = %s and archived_at is not null and checked", (ha,)) >= 1)
    check("Archiv: B sieht nichts von Haushalt A",
          one("select count(*) from shopping_list_items where archived_at is not null", user=B) == 0)

    # --- Wochenplan (Migration 0033) ----------------------------------------------------------------------------------
    check("Wochenplan: Fixture-Zeilen sind da, Zutaten als jsonb-Array",
          one("select count(*) from meal_plan_entries where household_id = %s and jsonb_typeof(ingredients) = 'array'", (ha,)) >= 2)
    check("Wochenplan: B sieht nichts von Haushalt A", one("select count(*) from meal_plan_entries", user=B) == 0)
    ins_plan = "insert into meal_plan_entries (household_id, planned_on, slot, title) values (%s,'2026-11-02',%s,%s)"
    check("Wochenplan: A kann planen", not raises(ins_plan, (ha, "dinner", "Linsencurry"), user=A))
    check("Wochenplan: B kann nicht in Haushalt A schreiben", raises(ins_plan, (ha, "dinner", "Fremd"), user=B))
    check("Wochenplan: unbekannte Tageszeit wird abgelehnt", raises(ins_plan, (ha, "drink", "Tee"), user=A))
    check("Wochenplan: leerer Titel wird abgelehnt", raises(ins_plan, (ha, "dinner", "  "), user=A))

    # --- Barcodes loesen (Migration 0039) ---------------------------------------------------------------------------
    check("Barcode loesen: Spalte deleted_at ist da",
          one("select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'product_barcodes' and column_name = 'deleted_at'") == 1)
    check("Barcode loesen: A kann einen eigenen Barcode als geloest markieren",
          not raises("update product_barcodes set deleted_at = now() where household_id = %s", (ha,), user=A))

    # --- Trinkbare Produkte (Migration 0037) ---------------------------------------------------------------------------
    check("Trinkbar: true, false und null aus dem Fixture sind da",
          one("select count(distinct coalesce(is_drink::text, 'null')) from products where household_id = %s", (ha,)) == 3)
    check("Getraenk: Eintrag vom Typ drink mit Wasseranteil aus dem Fixture",
          one("select count(*) from meals m join meal_ingredients i on i.meal_id = m.id where m.household_id = %s and m.meal_type = 'drink' and i.bls_code = 'N110000' and i.kcal = 0", (ha,)) >= 1)

    # --- Kochzeiten (Migration 0036) ----------------------------------------------------------------------------------
    check("Kochzeiten: Fixture-Zeilen sind da", one("select count(*) from cooking_sessions where household_id = %s and active_seconds > 0", (ha,)) >= 2)
    check("Kochzeiten: B sieht nichts von Haushalt A", one("select count(*) from cooking_sessions", user=B) == 0)
    ins_session = "insert into cooking_sessions (household_id, recipe_title, started_at, ended_at, active_seconds) values (%s,%s,%s,%s,%s)"
    check("Kochzeiten: A kann speichern", not raises(ins_session, (ha, "Curry", "2026-11-02 17:00+00", "2026-11-02 17:40+00", 2400), user=A))
    check("Kochzeiten: B kann nicht in Haushalt A schreiben", raises(ins_session, (ha, "Fremd", "2026-11-02 17:00+00", "2026-11-02 17:40+00", 2400), user=B))
    check("Kochzeiten: Dauer 0 wird abgelehnt", raises(ins_session, (ha, "Curry", "2026-11-02 17:00+00", "2026-11-02 17:40+00", 0), user=A))
    check("Kochzeiten: Ende vor dem Start wird abgelehnt", raises(ins_session, (ha, "Curry", "2026-11-02 17:40+00", "2026-11-02 17:00+00", 60), user=A))
    check("Kochzeiten: leerer Name wird abgelehnt", raises(ins_session, (ha, "  ", "2026-11-02 17:00+00", "2026-11-02 17:40+00", 60), user=A))

    # --- Nahrungsergaenzung und gemeinsame Einstellungen (Phase N4, Migration 0026) -----------------------------------
    check("Ergaenzungen: Fixture-Zeilen sind da (angelegt, geaendert, geloescht)",
          one("select count(*) from supplements where household_id = %s", (ha,)) >= 3 and
          one("select count(*) from supplements where household_id = %s and deleted_at is not null", (ha,)) >= 1)
    check("Ergaenzungen: Einnahmen tragen Name und absolute Mengen als jsonb",
          one("select count(*) from supplement_intakes where household_id = %s and jsonb_typeof(micros) = 'object' and name <> ''", (ha,)) >= 2)
    check("Einstellungen: je Schluessel eine Zeile, Werte sind jsonb",
          one("select count(*) from household_prefs where household_id = %s and key in ('micro_reference_on','micro_reference_overrides')", (ha,)) == 2)
    check("Ergaenzungen: B sieht nichts von Haushalt A",
          one("select count(*) from supplements", user=B) == 0 and one("select count(*) from supplement_intakes", user=B) == 0 and
          one("select count(*) from household_prefs", user=B) == 0)
    check("Ergaenzungen: A sieht die eigenen Zeilen", one("select count(*) from supplements", user=A) >= 3)
    ins_supp = "insert into supplements (household_id, name, serving_label, micros) values (%s,%s,%s,'{\"iron_mg\":14}')"
    check("Ergaenzungen: A kann eine anlegen", not raises(ins_supp, (ha, "Eisen", "Tablette"), user=A))
    check("Ergaenzungen: B kann nicht in Haushalt A schreiben", raises(ins_supp, (ha, "Fremd", "Tablette"), user=B))
    check("Ergaenzungen: leerer Name wird abgelehnt", raises(ins_supp, (ha, "  ", "Tablette"), user=A))
    check("Ergaenzungen: leere Einheit wird abgelehnt", raises(ins_supp, (ha, "X", " "), user=A))
    supp_id = one("select id from supplements where household_id = %s and name = 'Eisen'", (ha,))
    ins_intake = "insert into supplement_intakes (household_id, supplement_id, name, taken_at, servings, micros) values (%s,%s,'Eisen', now(), %s,'{\"iron_mg\":14}')"
    check("Einnahmen: A kann eine eintragen", not raises(ins_intake, (ha, supp_id, 1), user=A))
    check("Einnahmen: B kann nicht in Haushalt A schreiben", raises(ins_intake, (ha, supp_id, 1), user=B))
    check("Einnahmen: Anzahl 0 wird abgelehnt", raises(ins_intake, (ha, supp_id, 0), user=A))
    check("Einnahmen: negative Anzahl wird abgelehnt", raises(ins_intake, (ha, supp_id, -1), user=A))
    db("delete from supplements where id = %s", (supp_id,))
    check("Einnahmen: wird die Ergaenzung hart geloescht, bleibt die Einnahme (ohne Verweis, mit eigenem Snapshot)",
          one("select count(*) from supplement_intakes where name = 'Eisen' and supplement_id is null") == 1)
    ins_pref = "insert into household_prefs (household_id, key, value) values (%s,%s,%s::jsonb)"
    check("Einstellungen: A kann einen Wert anlegen", not raises(ins_pref, (ha, "test_key", "true"), user=A))
    check("Einstellungen: derselbe Schluessel zweimal wird abgelehnt (zusammengesetzter Schluessel)", raises(ins_pref, (ha, "test_key", "false"), user=A))
    check("Einstellungen: derselbe Schluessel in einem anderen Haushalt ist erlaubt", not raises(ins_pref, (hb, "test_key", "1"), user=B))
    check("Einstellungen: B kann nicht in Haushalt A schreiben", raises(ins_pref, (ha, "fremd", "1"), user=B))
    check("Einstellungen: leerer Schluessel wird abgelehnt", raises(ins_pref, (ha, "", "1"), user=A))
    check("Einstellungen: zu langer Schluessel wird abgelehnt", raises(ins_pref, (ha, "x" * 65, "1"), user=A))
    before_pref = one("select updated_at from household_prefs where household_id = %s and key = 'test_key'", (ha,))
    db("update household_prefs set value = '42'::jsonb where household_id = %s and key = 'test_key'", (ha,))
    check("Einstellungen: updated_at wird beim Aendern gesetzt",
          one("select updated_at > %s from household_prefs where household_id = %s and key = 'test_key'", (before_pref, ha)))
    db("delete from household_prefs where key = 'test_key'")


    # --- Haushaltseinheit (ADR-033, Migration 0038) ------------------------------------------------------------------------
    check("Haushaltseinheit: die Zeile aus der App (2 Scheiben) ist in der Datenbank",
          one("select count(*) from meal_ingredients where unit_key = 'slice' and household_id = %s", (ha,)) >= 1)
    meal_for_unit = one("select id from meals where household_id = %s and deleted_at is null limit 1", (ha,))
    ins_unit = "insert into meal_ingredients (household_id, meal_id, free_text, quantity, unit, unit_key) values (%s,%s,'x',1,'piece',%s)"
    check("Haushaltseinheit: tbsp wird angenommen", not raises(ins_unit, (ha, meal_for_unit, "tbsp"), user=A))
    check("Haushaltseinheit: unbekannte Einheit wird abgelehnt", raises(ins_unit, (ha, meal_for_unit, "tasse"), user=A))
    db("delete from meal_ingredients where free_text = 'x' and unit_key = 'tbsp'")


    # --- Garfaktoren (Phase N4, Migration 0027): Zubereitung je Zutat ----------------------------------------------------
    check("Zubereitung: die Zeile aus der App (gekochtes Gemuese) ist in der Datenbank",
          one("select count(*) from meal_ingredients where preparation = 'veg_other:boiled' and household_id = %s", (ha,)) >= 1)
    meal_for_prep = one("select id from meals where household_id = %s and deleted_at is null limit 1", (ha,))
    ins_prep = "insert into meal_ingredients (household_id, meal_id, free_text, quantity, unit, preparation) values (%s,%s,'x',1,'piece',%s)"
    for ok in ("beef:grilled", "fish_lean:steamed", "veg_other:boiled", "tomato:baked"):
        check(f"Zubereitung: {ok} wird angenommen", not raises(ins_prep, (ha, meal_for_prep, ok), user=A))
    for bad in ("beef", "beef:smoked", "Beef:grilled", "beef:grilled:x", ":boiled", "1:boiled", "beef: grilled"):
        check(f"Zubereitung: '{bad}' wird abgelehnt", raises(ins_prep, (ha, meal_for_prep, bad), user=A))
    check("Zubereitung: leer (NULL) ist erlaubt", not raises("insert into meal_ingredients (household_id, meal_id, free_text, quantity, unit) values (%s,%s,'y',1,'piece')", (ha, meal_for_prep), user=A))

    # --- Verweise nur im selben Haushalt (0028, Codereview 2026-10-16 Fund S7) -----------------------------------------
    pa = one("insert into products (household_id, name) values (%s, 'Probe A') returning id", (ha,))
    pb = one("insert into products (household_id, name) values (%s, 'Probe B') returning id", (hb,))
    ins_item = "insert into inventory_items (household_id, product_id) values (%s,%s) returning id"
    check("Haushaltsgrenze: A kann einen Bestand zum eigenen Produkt anlegen", not raises(ins_item, (ha, pa), user=A))
    check("Haushaltsgrenze: A kann keinen Bestand auf ein Produkt von B zeigen lassen", raises(ins_item, (ha, pb), user=A))
    own_item = one("select id from inventory_items where household_id = %s and product_id = %s", (ha, pa))
    check("Haushaltsgrenze: auch nicht nachtraeglich per Update",
          raises("update inventory_items set product_id = %s where id = %s", (pb, own_item), user=A))
    check("Haushaltsgrenze: gilt auch fuer die service_role (Edge Functions)", raises(ins_item, (ha, pb)))
    lb = one("insert into shopping_lists (household_id, name, is_default) values (%s, 'Probe', false) returning id", (hb,))
    check("Haushaltsgrenze: kein Eintrag in die Einkaufsliste eines anderen Haushalts",
          raises("insert into shopping_list_items (household_id, list_id, free_text) values (%s,%s,'x')", (ha, lb), user=A))
    try:
        db(ins_item, (ha, pb), user=A)
        code = None
    except psycopg.Error as e:
        code = e.sqlstate
    check("Haushaltsgrenze: Fehlercode 23503 (die App stuft das als Datenfehler ein, die Outbox bleibt frei)", code == "23503", f"{code}")
    check("Haushaltsgrenze: ein leerer Verweis bleibt erlaubt",
          not raises("insert into receipt_items (household_id, receipt_id, line_no, raw_text, line_total_cents, product_id) "
                     "select %s, id, 99, 'x', 1, null from receipts where household_id = %s limit 1", (ha, ha), user=A))
    db("delete from inventory_items where product_id in (%s, %s)", (pa, pb))
    db("delete from products where id in (%s, %s)", (pa, pb))
    db("delete from shopping_lists where id = %s", (lb,))

    fks = db("""
        select c.conrelid::regclass::text, a.attname, c.confrelid::regclass::text
        from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
        where c.contype = 'f' and array_length(c.conkey, 1) = 1 and c.connamespace = 'public'::regnamespace
          and a.attname <> 'household_id'
          and exists (select 1 from pg_attribute x where x.attrelid = c.conrelid and x.attname = 'household_id' and not x.attisdropped)
          and exists (select 1 from pg_attribute y where y.attrelid = c.confrelid and y.attname = 'household_id' and not y.attisdropped)
        order by 1, 2""")[0]
    trigger_defs = [r[0] for r in db("""
        select pg_get_triggerdef(t.oid) from pg_trigger t
        where not t.tgisinternal and t.tgfoid = 'public.ensure_same_household'::regproc""")[0]]
    unguarded_fks = [f"{tab}.{col}" for tab, col, ref in fks
                     if not any(f" ON public.{tab} " in d and f"'{col}', '{ref}'" in d for d in trigger_defs)]
    check("Invariante: jeder Fremdschluessel zwischen Haushaltstabellen prueft den Haushalt (Trigger ensure_same_household)",
          fks and not unguarded_fks, f"ohne Trigger: {unguarded_fks}")

    # --- Einladungen: Code, Ablauf und Zaehler setzt der Server (0029, Fund S8) ------------------------------------------
    db("""insert into household_invites (household_id, invited_by, email, token, failed_attempts, expires_at, accepted_at)
          values (%s, %s, 'selbstgemacht@test.at', 'AAAAAAAAAAAA', -1000, now() + interval '10 years', now())""", (ha, A), user=A)
    tok, attempts, days, accepted = db("""select token, failed_attempts, extract(day from expires_at - now()), accepted_at
                                         from household_invites where email = 'selbstgemacht@test.at'""")[0][0]
    check("Einladung: selbst gewaehlter Code wird ersetzt", tok != "AAAAAAAAAAAA" and re.fullmatch(r"[A-HJKMNP-Z2-9]{12}", tok), tok)
    check("Einladung: Fehlversuchszaehler startet immer bei 0 (kein Aushebeln der Sperre)", attempts == 0, f"{attempts}")
    check("Einladung: Ablauf ist immer 7 Tage", days is not None and 6 <= days <= 7, f"{days}")
    check("Einladung: kann nicht als schon angenommen angelegt werden", accepted is None)
    db("delete from household_invites where email = 'selbstgemacht@test.at'")

    # --- Tageslimit der KI-Functions: atomare Reservierung (0030, Fund S9) ----------------------------------------------
    db("delete from llm_usage where household_id = %s", (hb,))
    first = one("select reserve_llm_call(%s, 'm', 2)", (hb,))
    second = one("select reserve_llm_call(%s, 'm', 2)", (hb,))
    third = one("select reserve_llm_call(%s, 'm', 2)", (hb,))
    check("Reservierung: bis zum Limit gibt es eine Zeilen-ID, danach null", first and second and third is None, f"{first} {second} {third}")
    check("Reservierung: die reservierten Zeilen zaehlen sofort (2 Zeilen mit 0 Tokens)",
          one("select count(*) from llm_usage where household_id = %s and input_tokens = 0", (hb,)) == 2)
    db("update llm_usage set created_at = now() - interval '25 hours' where id = %s", (first,))
    check("Reservierung: Aufrufe aelter als 24 Stunden zaehlen nicht mehr", one("select reserve_llm_call(%s, 'm', 2)", (hb,)) is not None)
    check("Reservierung: Clients duerfen nicht reservieren (nur service_role)",
          raises("select reserve_llm_call(%s, 'm', 100)", (hb,), user=B)
          and one("select has_function_privilege('service_role', 'public.reserve_llm_call(uuid,text,integer)', 'execute')"))
    # Zwei gleichzeitige Transaktionen: die zweite wartet auf die Sperre der ersten und sieht deren Zeile
    db("delete from llm_usage where household_id = %s", (hb,))
    with psycopg.connect(uri) as c1, psycopg.connect(uri) as c2:
        r1 = c1.execute("select reserve_llm_call(%s, 'm', 1)", (hb,)).fetchone()[0]
        import threading
        out = {}
        t = threading.Thread(target=lambda: out.update(r2=c2.execute("select reserve_llm_call(%s, 'm', 1)", (hb,)).fetchone()[0]))
        t.start()
        t.join(timeout=1)
        waited = t.is_alive()
        c1.commit()
        t.join(timeout=10)
        c2.commit()
    check("Reservierung: parallele Aufrufe desselben Haushalts warten aufeinander (Advisory-Sperre)", waited)
    check("Reservierung: von zwei gleichzeitigen Aufrufen bei Limit 1 bekommt nur einer eine Zeile",
          r1 is not None and out.get("r2", "fehlt") is None, f"{r1} {out}")
    db("delete from llm_usage where household_id = %s", (hb,))

    # --- Sicherheits-Invarianten ueber den Katalog (Codereview 2026-10-16) --------------------------------------------
    # Die Tests oben pruefen einzelne Tabellen; diese hier gelten fuer ALLE, auch fuer kuenftige Migrationen. Eine neue
    # Tabelle ohne RLS oder eine neue SECURITY-DEFINER-Funktion ohne festen search_path faellt so sofort auf.
    no_rls = [r[0] for r in db("""
        select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity order by 1""")[0]]
    check("Invariante: jede Tabelle in public hat Row Level Security", not no_rls, f"ohne RLS: {no_rls}")

    hh_tables = [r[0] for r in db("""
        select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attname = 'household_id' and not a.attisdropped
        where n.nspname = 'public' and c.relkind in ('r', 'p') order by 1""")[0]]
    unguarded = [r[0] for r in db("""
        select t from unnest(%s::text[]) t
        where not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t
                          and p.qual like '%%is_household_member(household_id)%%')
        order by 1""", (hh_tables,))[0]]
    # llm_usage und household_invites haben eigene, engere Policies (nur lesen bzw. nur offene zurueckziehen), pruefen aber
    # ebenfalls die Mitgliedschaft; bug_reports usw. laufen ueber die Standard-Policy.
    check("Invariante: jede Tabelle mit household_id hat eine Policy, die die Mitgliedschaft prueft", not unguarded, f"ohne: {unguarded}")

    loose_writes = [f"{r[0]}.{r[1]}" for r in db("""
        select tablename, policyname from pg_policies
        where schemaname = 'public' and cmd in ('INSERT', 'UPDATE', 'ALL')
          and tablename = any(%s::text[])
          and coalesce(with_check, qual, '') not like '%%is_household_member(household_id)%%'
        order by 1, 2""", (hh_tables,))[0]]
    check("Invariante: schreibende Policies auf Haushaltstabellen pruefen die Mitgliedschaft auch beim Schreiben",
          not loose_writes, f"{loose_writes}")

    definer_no_path = [r[0] for r in db("""
        select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.prosecdef
          and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%%')
        order by 1""")[0]]
    check("Invariante: jede SECURITY-DEFINER-Funktion hat einen festen search_path (Schutz vor Objekt-Unterschiebung)",
          not definer_no_path, f"ohne search_path: {definer_no_path}")

    definer_for_clients = [r[0] for r in db("""
        select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.prosecdef and p.proname in ('peek_invite', 'redeem_invite')
          and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
        order by 1""")[0]]
    check("Invariante: Einladungen pruefen/einloesen darf nur die service_role (kein Client)", not definer_for_clients,
          f"fuer Clients ausfuehrbar: {definer_for_clients}")

    invoker_missing = [r[0] for r in db("""
        select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind = 'v'
          and not coalesce('security_invoker=true' = any(c.reloptions), false)
        order by 1""")[0]]
    check("Invariante: jede View laeuft mit den Rechten des Aufrufers (security_invoker), sonst umginge sie RLS",
          not invoker_missing, f"ohne security_invoker: {invoker_missing}")

    public_buckets = [r[0] for r in db("select id from storage.buckets where public order by 1")[0]]
    check("Invariante: alle Storage-Buckets sind privat (Bon-Fotos, Essensfotos)", not public_buckets, f"oeffentlich: {public_buckets}")

    anon_storage = [r[0] for r in db("""
        select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects'
          and not (roles = '{authenticated}'::name[]) order by 1""")[0]]
    check("Invariante: Storage-Policies gelten nur fuer angemeldete Nutzer", not anon_storage, f"{anon_storage}")

    # In echtem Supabase hat die Rolle anon (Aufruf nur mit dem oeffentlichen Client-Schluessel, ohne Anmeldung) Lese-
    # rechte auf alle Tabellen; geschuetzt wird allein durch RLS. Hier nachgebildet und fuer jede Haushaltstabelle geprueft.
    db("grant select on all tables in schema public to anon")

    def anon_count(table):
        with psycopg.connect(uri, autocommit=True) as c:
            with c.cursor() as cur:
                cur.execute("set role anon")
                cur.execute(f"select count(*) from public.{table}")
                return cur.fetchone()[0]

    total_rows = {t: one(f"select count(*) from public.{t}") for t in hh_tables}
    visible_to_anon = {t: n for t in hh_tables if (n := anon_count(t)) > 0}
    check("Invariante: ohne Anmeldung (anon) ist keine Haushaltszeile sichtbar", not visible_to_anon, f"{visible_to_anon}")
    check("Invariante: die anon-Pruefung ist aussagekraeftig (es gibt Haushaltszeilen)", sum(total_rows.values()) > 0)

    # --- Geplante Migrationen (z.B. kuenftige Phase-6-Vorbereitung) muessen sauber einspielbar sein
    planned_ok = True
    try:
        for m in PLANNED:
            db(m.read_text(encoding="utf-8"))
    except psycopg.Error as e:
        planned_ok = False
        print("  Fehler in geplanter Migration:", e)
    check("Geplante Migrationen (planned/) lassen sich einspielen", planned_ok)
    db(GRANTS)  # in echtem Supabase per Default-Privileges, hier nachziehen

    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} Tests bestanden")
    srv.cleanup()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
