// Edge Function: refresh-online-prices
// STATUS: neu (ADR-019 "Online-Preisquellen", Umsetzung 2026-10-02).
//
// Holt taeglich die Preise von Billa und Spar aus dem oeffentlichen Feed von heisse-preise.io (Projekt badlogic/heissepreise,
// MIT-Lizenz; kein eigenes Scraping) und schreibt sie in die schlanke Tabelle `online_prices`. Die App liest nie den
// Feed, nur diese Tabelle.
//
// Aufbau (siehe feed.ts, warum so): Der Feed ist 216 MB gross, eine Edge Function hat nur ca. 2 s CPU-Zeit je Aufruf.
//   * Koordinator (POST ohne Koerper, vom pg_cron-Job angestossen): prueft per HEAD, ob der Feed neu ist, zerlegt die
//     Datei in 10-MB-Abschnitte und ruft je Abschnitt einen Worker auf.
//   * Worker (POST mit run/start/end/signature, vom Koordinator): liest den Abschnitt per HTTP-Range, filtert Billa und
//     Spar, schreibt die Zeilen per Upsert.
//   * Am Ende: je Haendler pruefen, ob die Menge plausibel ist, nur dann dessen veraltete Zeilen loeschen, und
//     `online_feed_status` aktualisieren. Faellt ein Haendler aus, bleiben seine alten Preise mit altem `seen_at` stehen
//     (die App zeigt sie nach Ablauf der Frist als "zuletzt bekannt"), steht in `last_error`, und die anderen laufen normal.
//
// Die Function braucht keine Anmeldung (`--no-verify-jwt`, der Cron-Job hat keinen Nutzer). Das ist ungefaehrlich: ein
// Aufruf macht hoechstens einen HEAD-Request, solange der Feed unveraendert ist oder gerade ein Lauf laeuft; die
// Abschnitts-Worker verlangen eine Signatur mit dem Service-Schluessel.
//
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Keine eigenen Secrets noetig.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import {
  checkStores,
  extractSlice,
  FEED_URL,
  fetchWindow,
  planSlices,
  type PriceRow,
  signSlice,
  verifySlice,
  WANTED_STORES,
} from "./feed.ts";

// EdgeRuntime.waitUntil laesst die Arbeit nach der Antwort weiterlaufen (nur in der Supabase-Laufzeit vorhanden).
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const SOURCE = "heisse_preise";
const RUN_TIMEOUT_MINUTES = 20; // ein steckengebliebener Lauf blockiert nicht laenger
const UPSERT_BATCH = 500;
const CONCURRENCY = 3;
const USER_AGENT = "Einkaufstracker/1.0 (privates Projekt; taeglicher Abruf von latest-canonical.json)";

function admin(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  let body: Record<string, unknown> = {};
  try {
    const text = await req.text();
    if (text.trim() !== "") body = JSON.parse(text);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  return typeof body.signature === "string" ? await handleSlice(body) : await handleCoordinator();
});

// --- Worker ------------------------------------------------------------------------------------------------------

async function handleSlice(body: Record<string, unknown>): Promise<Response> {
  const { run, start, end, size, started_at: startedAt, signature } = body;
  if (typeof run !== "string" || typeof start !== "number" || typeof end !== "number" || typeof size !== "number" ||
    typeof startedAt !== "string" || typeof signature !== "string") {
    return json({ error: "invalid_slice" }, 400);
  }
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!(await verifySlice(secret, run, start, end, signature))) return json({ error: "forbidden" }, 403);

  try {
    const w = fetchWindow(start, end, size);
    const resp = await fetch(FEED_URL, { headers: { Range: `bytes=${w.from}-${w.to}`, "User-Agent": USER_AGENT } });
    if (resp.status !== 206) return json({ error: "range_not_supported", status: resp.status }, 502);
    const buf = new Uint8Array(await resp.arrayBuffer());
    const result = extractSlice(buf, w.from, start, end, w.isEof);

    const db = admin();
    for (let i = 0; i < result.rows.length; i += UPSERT_BATCH) {
      const batch = result.rows.slice(i, i + UPSERT_BATCH).map((r: PriceRow) => ({ ...r, seen_at: startedAt }));
      const { error } = await db.from("online_prices").upsert(batch, { onConflict: "store,external_id" });
      if (error) throw new Error(`upsert: ${error.message}`);
    }
    return json({ rows: result.rows.length, owned: result.owned, parse_errors: result.parseErrors });
  } catch (e) {
    console.error("slice_failed", start, end, e);
    return json({ error: "slice_failed", message: String(e instanceof Error ? e.message : e) }, 500);
  }
}

// --- Koordinator -------------------------------------------------------------------------------------------------

async function handleCoordinator(): Promise<Response> {
  const db = admin();

  // 1) Feed ansehen (HEAD, ohne Kompression, damit der ETag stabil ist)
  let size: number, etag: string, lastModified: string;
  try {
    const head = await fetch(FEED_URL, { method: "HEAD", headers: { "User-Agent": USER_AGENT, "Accept-Encoding": "identity" } });
    if (!head.ok) throw new Error(`HEAD ${head.status}`);
    size = Number(head.headers.get("content-length"));
    etag = head.headers.get("etag") ?? "";
    lastModified = head.headers.get("last-modified") ?? "";
    if (!Number.isFinite(size) || size <= 0) throw new Error("keine Dateigroesse");
  } catch (e) {
    await db.from("online_feed_status").upsert({ source: SOURCE, last_attempt_at: new Date().toISOString(), last_error: `Feed nicht erreichbar: ${e}`.slice(0, 300) });
    return json({ status: "feed_unreachable" }, 502);
  }

  // 2) Unveraendert und schon verarbeitet: nichts zu tun. `feed_etag` wird erst am Ende eines Laufs geschrieben, ein
  // abgebrochener Lauf wird also wiederholt; ein ausgefallener Haendler (`last_error` gesetzt) wird es erst mit neuem Feed.
  const { data: status } = await db.from("online_feed_status").select("*").eq("source", SOURCE).maybeSingle();
  if (status && etag !== "" && status.feed_etag === etag && status.last_success_at) {
    return json({ status: "up_to_date", feed_last_modified: status.feed_last_modified });
  }

  // 3) Lauf beanspruchen: ein laufender Lauf (juenger als 20 Minuten) wird nicht doppelt gestartet
  const startedAt = new Date();
  const staleBefore = new Date(startedAt.getTime() - RUN_TIMEOUT_MINUTES * 60_000).toISOString();
  if (!status) await db.from("online_feed_status").upsert({ source: SOURCE }, { ignoreDuplicates: true });
  const { data: claimed } = await db
    .from("online_feed_status")
    .update({ running_since: startedAt.toISOString(), last_attempt_at: startedAt.toISOString() })
    .eq("source", SOURCE)
    .or(`running_since.is.null,running_since.lt.${staleBefore}`)
    .select("source");
  if (!claimed || claimed.length === 0) return json({ status: "busy" }, 202);

  const run = crypto.randomUUID();
  const work = runAll(db, run, startedAt, size, etag, lastModified);
  if (typeof EdgeRuntime !== "undefined") {
    EdgeRuntime.waitUntil(work);
    return json({ status: "started", run, slices: planSlices(size).length }, 202);
  }
  await work; // lokal ohne EdgeRuntime: synchron abwarten
  return json({ status: "done", run });
}

async function runAll(db: SupabaseClient, run: string, startedAt: Date, size: number, etag: string, lastModified: string): Promise<void> {
  const started = startedAt.toISOString();
  const selfUrl = `${Deno.env.get("SUPABASE_URL")!}/functions/v1/refresh-online-prices`;
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  try {
    // Vorher-Stand je Haendler fuer die Plausibilitaetspruefung
    const before: Record<string, number> = {};
    for (const s of WANTED_STORES) {
      const { count } = await db.from("online_prices").select("external_id", { count: "exact", head: true }).eq("store", s);
      before[s] = count ?? 0;
    }

    const slices = planSlices(size);
    let parseErrors = 0;
    let next = 0;
    const runWorker = async () => {
      while (next < slices.length) {
        const [start, end] = slices[next++];
        const payload = JSON.stringify({ run, start, end, size, started_at: started, signature: await signSlice(secret, run, start, end) });
        let lastError = "";
        for (let attempt = 0; attempt < 2; attempt++) {
          const resp = await fetch(selfUrl, { method: "POST", headers: { "Content-Type": "application/json" }, body: payload });
          const result = await resp.json().catch(() => ({}));
          if (resp.ok) {
            parseErrors += Number(result.parse_errors ?? 0);
            lastError = "";
            break;
          }
          lastError = `Abschnitt ${start}-${end}: ${result.error ?? resp.status} ${result.message ?? ""}`.trim();
        }
        if (lastError) throw new Error(lastError);
      }
    };
    await Promise.all(Array.from({ length: Math.min(CONCURRENCY, slices.length) }, runWorker));

    // Veraltete Zeilen (diesmal nicht mehr verfuegbar) nur bei Haendlern loeschen, deren Menge plausibel ist
    const after: Record<string, number> = {};
    for (const s of WANTED_STORES) {
      const { count } = await db.from("online_prices").select("external_id", { count: "exact", head: true }).eq("store", s).gte("seen_at", started);
      after[s] = count ?? 0;
    }
    const { ok, failed } = checkStores(WANTED_STORES, before, after);
    const storeError = failed.map((s) => `${s}: nur ${after[s]} Eintraege statt ${before[s]} (Feed geaendert?), alte Preise bleiben stehen`).join("; ");
    if (ok.length === 0) throw new Error(storeError);
    for (const s of ok) {
      const { error } = await db.from("online_prices").delete().eq("store", s).lt("seen_at", started);
      if (error) throw new Error(`delete: ${error.message}`);
    }

    const modified = lastModified ? new Date(lastModified).toISOString() : started;
    await db.from("online_feed_status").upsert({
      source: SOURCE,
      feed_etag: etag,
      feed_last_modified: modified,
      last_success_at: new Date().toISOString(),
      running_since: null,
      last_error: storeError === "" ? null : storeError.slice(0, 300),
      row_counts: { ...after, parse_errors: parseErrors },
    });
    console.log("refresh_done", run, after, "parse_errors", parseErrors, "failed", failed);
  } catch (e) {
    console.error("refresh_failed", run, e);
    await db.from("online_feed_status").upsert({
      source: SOURCE,
      running_since: null,
      last_error: String(e instanceof Error ? e.message : e).slice(0, 300),
    });
  }
}
