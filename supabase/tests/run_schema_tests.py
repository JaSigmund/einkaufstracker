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
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
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

GRANTS = """
grant all on all tables in schema public to authenticated, service_role;
grant all on all tables in schema storage to authenticated, service_role;
grant select on all tables in schema auth to service_role;
grant execute on all functions in schema public, auth, storage to authenticated, service_role;
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
