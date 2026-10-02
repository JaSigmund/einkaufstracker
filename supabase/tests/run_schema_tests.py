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
        key = "household_id" if table == "nutrition_targets" else "id"
        updates = ", ".join(f"{c}=excluded.{c}" for c in cols if c != key)
        sql = (f"insert into public.{table} ({', '.join(cols)}) values ({', '.join(['%s'] * len(cols))}) "
               f"on conflict ({key}) do update set {updates}")
        try:
            db(sql, vals)
        except psycopg.Error as ex:
            contract_failures.append(f"{table}: {str(ex).splitlines()[0]}")
    tables_in_fixture = {e["table"] for e in entries}
    check("Vertrag: Fixture enthaelt Tagebuch, Ledger und Richtwerte",
          {"meals", "meal_ingredients", "inventory_movements", "nutrition_targets"} <= tables_in_fixture, str(tables_in_fixture))
    check(f"Vertrag: alle {len(entries)} Zeilen der App werden vom echten Schema angenommen", not contract_failures, "; ".join(contract_failures[:3]))
    meal_ids = [e["payload"]["id"] for e in entries if e["table"] == "meals"]
    check("Vertrag: die eingespielten Mahlzeiten liegen in der Datenbank (Soft-Delete eingeschlossen)",
          one("select count(*) from meals where id = any(%s::uuid[])", (meal_ids,)) == len(set(meal_ids)))
    check("Vertrag: Gegenbuchung der geloeschten Mahlzeit ist mit meal_id verknuepft",
          one("select count(*) from inventory_movements where type='adjustment' and meal_id = any(%s::uuid[])", (meal_ids,)) >= 1)


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
