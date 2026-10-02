// Reine Logik fuer die Online-Preise (ADR-019): Normalisierung eines Feed-Eintrags und das Herauslesen einzelner
// Eintraege aus einem Byte-Abschnitt des 216-MB-Feeds von heisse-preise.io, ohne die Datei je ganz zu laden.
//
// Warum Abschnitte: Edge Functions haben nur ca. 2 Sekunden CPU-Zeit je Aufruf. Der Feed ist ein einziges, eingerueckt
// geschriebenes JSON-Array (`JSON.stringify(..., null, 2)`), nach Haendler sortiert. Jeder Eintrag beginnt in der Datei
// genau mit "\n  {\n    \"store\": \"". Diese Marke steht nie innerhalb eines JSON-Strings (dort sind Zeilenumbrueche
// als \n maskiert). Ein Abschnitt [start, end) "gehoert" deshalb allen Eintraegen, deren Marke darin beginnt; den
// Schluss des letzten Eintrags findet man in einem etwas laengeren Lesefenster (Ueberlappung).

export const FEED_URL = "https://heisse-preise.io/data/latest-canonical.json";

/** Haendler, die der Feed aktuell pflegt (Stand 2026-10-02, ADR-019). Die uebrigen liefern veraltete Daten. */
export const WANTED_STORES = ["billa", "spar"];

/** Abschnittsgroesse und Ueberlappung in Byte. Kein Eintrag ist groesser als die Ueberlappung (Eintraege haben im Mittel 2,6 KB). */
export const SLICE_BYTES = 10 * 1024 * 1024;
export const OVERLAP_BYTES = 2 * 1024 * 1024;

const ITEM_MARKER = '\n  {\n    "store": "';

/** Roher Eintrag, nur die Felder, die wir brauchen (der echte hat zusaetzlich description, priceHistory, url, category). */
export interface RawEntry {
  store?: unknown;
  id?: unknown;
  name?: unknown;
  price?: unknown;
  unit?: unknown;
  quantity?: unknown;
  isWeighted?: unknown;
  bio?: unknown;
  unavailable?: unknown;
}

export interface PriceRow {
  store: string;
  external_id: string;
  name: string;
  price_cents: number;
  quantity: number | null;
  unit: string | null;
  base_unit: "kg" | "l" | "stk" | null;
  unit_price_norm_cents: number | null;
  is_weighted: boolean;
  bio: boolean;
}

// Nur die am Feed real beobachteten, eindeutigen Einheiten. Alles andere (Waschgaenge "wg", kaputte Kodierung, leere
// Strings) ergibt einen Preis ohne Grundpreis statt eines falschen Werts.
const UNITS: Record<string, ["kg" | "l" | "stk", number]> = {
  g: ["kg", 0.001],
  kg: ["kg", 1],
  ml: ["l", 0.001],
  l: ["l", 1],
  stk: ["stk", 1],
  "stück": ["stk", 1],
};

const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);

/**
 * Normalisiert einen Feed-Eintrag, oder `null`, wenn er nicht (mehr) im Sortiment ist oder unlesbar.
 *
 * Wichtig (an den echten Daten gesehen, 2026-10-02): Der Feed schreibt `"unavailable": true` nur bei nicht mehr
 * verfuegbaren Artikeln und **laesst das Feld sonst ganz weg**. Verfuegbar heisst also `unavailable !== true`. Gegen
 * eine Aenderung des Feldnamens schuetzt `sanityOk` (Mengenpruefung vor dem Loeschen).
 */
export function normalizeEntry(e: RawEntry): PriceRow | null {
  if (e.unavailable === true) return null;
  if (typeof e.store !== "string" || e.store === "") return null;
  if (typeof e.id !== "string" && !isNum(e.id)) return null;
  if (typeof e.name !== "string") return null;
  const name = e.name.replace(/\s+/g, " ").trim();
  if (name === "" || !isNum(e.price) || e.price < 0) return null;

  const priceCents = Math.round(e.price * 100);
  const unitKey = typeof e.unit === "string" ? e.unit.trim().toLowerCase() : "";
  const resolved = UNITS[unitKey];
  const quantity = isNum(e.quantity) && e.quantity > 0 ? e.quantity : null;

  let baseUnit: PriceRow["base_unit"] = null;
  let unitPrice: number | null = null;
  if (resolved) {
    baseUnit = resolved[0];
    if (quantity !== null) unitPrice = Math.round(priceCents / (quantity * resolved[1]));
  }
  return {
    store: e.store,
    external_id: String(e.id),
    name,
    price_cents: priceCents,
    quantity,
    unit: typeof e.unit === "string" && e.unit.trim() !== "" ? e.unit.trim() : null,
    base_unit: baseUnit,
    unit_price_norm_cents: unitPrice,
    is_weighted: e.isWeighted === true,
    bio: e.bio === true,
  };
}

export class SliceTooShort extends Error {
  constructor(start: number) {
    super(`Ueberlappung zu kurz: Ende des Eintrags ab Byte ${start} nicht gefunden`);
  }
}

export interface SliceResult {
  /** Alle verfuegbaren Eintraege der gewuenschten Haendler, deren Marke im Abschnitt beginnt. */
  rows: PriceRow[];
  /** Eintraege (aller Haendler), die diesem Abschnitt gehoeren. */
  owned: number;
  /** Eintraege der gewuenschten Haendler, die nicht als JSON lesbar waren. */
  parseErrors: number;
}

/**
 * Liest die Eintraege eines Abschnitts aus [buf]. [bufStart] ist die Byte-Position von buf[0] in der Datei,
 * [sliceStart, sliceEnd) der Abschnitt, dem die Eintraege gehoeren, [isEof] sagt, ob buf bis ans Dateiende reicht
 * (dann endet der letzte Eintrag mit "\n  }\n]" statt mit der naechsten Marke).
 *
 * Es wird nur der Haendlername jedes Eintrags gelesen. Nur Eintraege der gewuenschten Haendler werden als UTF-8
 * dekodiert und geparst, das haelt die CPU-Zeit klein.
 */
export function extractSlice(
  buf: Uint8Array,
  bufStart: number,
  sliceStart: number,
  sliceEnd: number,
  isEof: boolean,
  wanted: ReadonlySet<string> = new Set(WANTED_STORES),
): SliceResult {
  // "latin1" bildet jedes Byte auf genau ein Zeichen ab, Zeichenposition = Byte-Position. Die Marke ist reines ASCII.
  const s = new TextDecoder("latin1").decode(buf);
  const starts: number[] = [];
  for (let i = s.indexOf(ITEM_MARKER); i !== -1; i = s.indexOf(ITEM_MARKER, i + 1)) starts.push(i);

  const utf8 = new TextDecoder("utf-8");
  const rows: PriceRow[] = [];
  let owned = 0;
  let parseErrors = 0;

  for (let k = 0; k < starts.length; k++) {
    const itemStart = starts[k] + 1; // hinter dem fuehrenden Zeilenumbruch
    const absolute = bufStart + itemStart;
    if (absolute < sliceStart) continue;
    if (absolute >= sliceEnd) break;
    owned++;

    const storeFrom = starts[k] + ITEM_MARKER.length;
    const storeTo = s.indexOf('"', storeFrom);
    const store = s.slice(storeFrom, storeTo);
    if (!wanted.has(store)) continue;

    let end: number;
    if (k + 1 < starts.length) end = starts[k + 1];
    else if (isEof) end = s.length;
    else throw new SliceTooShort(absolute);

    const text = utf8.decode(buf.subarray(itemStart, end));
    try {
      const entry = JSON.parse(text.slice(0, text.lastIndexOf("}") + 1)) as RawEntry;
      const row = normalizeEntry(entry);
      if (row) rows.push(row);
    } catch {
      parseErrors++;
    }
  }
  return { rows, owned, parseErrors };
}

/** Byte-Bereiche [start, end), in die die Datei zerlegt wird. */
export function planSlices(size: number, sliceBytes = SLICE_BYTES): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  for (let start = 0; start < size; start += sliceBytes) out.push([start, Math.min(start + sliceBytes, size)]);
  return out;
}

/** Lesefenster (Range-Header) fuer einen Abschnitt: ein Byte davor (die Marke beginnt mit einem Zeilenumbruch) und die Ueberlappung dahinter. */
export function fetchWindow(start: number, end: number, size: number, overlap = OVERLAP_BYTES): { from: number; to: number; isEof: boolean } {
  const from = Math.max(0, start - 1);
  const to = Math.min(size - 1, end + overlap - 1);
  return { from, to, isEof: to >= size - 1 };
}

/**
 * Plausibilitaetspruefung vor dem Loeschen veralteter Zeilen: Weicht die Menge stark vom letzten erfolgreichen Lauf
 * ab (Schema geaendert, Teilausfall), bleiben die alten Zeilen stehen und der Lauf gilt als fehlgeschlagen.
 */
export function sanityOk(previousCount: number, newCount: number): boolean {
  if (newCount <= 0) return false;
  if (previousCount < 100) return true;
  // Nach unten: Teilausfall oder geaendertes Schema. Nach oben: z.B. umbenanntes Feld `unavailable`, dann stuenden
  // ploetzlich auch alle nicht mehr verfuegbaren Artikel als verfuegbar da (bei Billa +67 %).
  return newCount >= previousCount * 0.5 && newCount <= previousCount * 1.35;
}

// --- Signatur der Abschnitts-Aufrufe -----------------------------------------------------------------------------
// Der Koordinator ruft die Abschnitts-Worker ueber das oeffentliche Function-URL auf. Die Signatur (HMAC mit dem
// Service-Schluessel, der nur serverseitig existiert) verhindert, dass Dritte Abschnitte anstossen.

const hex = (buf: ArrayBuffer) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

async function hmacKey(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function signSlice(secret: string, run: string, start: number, end: number): Promise<string> {
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), new TextEncoder().encode(`${run}:${start}:${end}`));
  return hex(sig);
}

export async function verifySlice(secret: string, run: string, start: number, end: number, signature: string): Promise<boolean> {
  const expected = await signSlice(secret, run, start, end);
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}
