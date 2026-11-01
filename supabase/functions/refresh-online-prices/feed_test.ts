// Tests fuer feed.ts. Lokal und in der CI: `deno test feed_test.ts`
import { assertEquals, assertNotEquals, assertThrows } from "jsr:@std/assert@1";
import {
  checkStores,
  extractSlice,
  fetchWindow,
  normalizeEntry,
  planSlices,
  type RawEntry,
  sanityOk,
  signSlice,
  SliceTooShort,
  verifySlice,
} from "./feed.ts";

// --- normalizeEntry: Faelle aus echten Feed-Daten (Stand 2026-10-01/02) -------------------------------------------

const entry = (over: RawEntry): RawEntry => ({ store: "billa", id: "00-600283", name: "Testprodukt", price: 1, unit: "stk", quantity: 1, isWeighted: false, unavailable: false, ...over });

Deno.test("Billa, Packware in g: Grundpreis in Cent je kg", () => {
  // Echter Eintrag: "11er 11 Minuten Pommes", 3,99 EUR / 600 g
  const r = normalizeEntry(entry({ name: "11er 11 Minuten Pommes", price: 3.99, unit: "g", quantity: 600 }))!;
  assertEquals(r.price_cents, 399);
  assertEquals(r.base_unit, "kg");
  assertEquals(r.unit_price_norm_cents, 665); // 399 / 0,6
});

Deno.test("Wiegeware (isWeighted) rechnet wie Packware", () => {
  // Echter Eintrag: "Ablinger Pikantwurst", 21,90 EUR / 1000 g
  const r = normalizeEntry(entry({ id: "00-32218", name: "Ablinger Pikantwurst", price: 21.9, unit: "g", quantity: 1000, isWeighted: true }))!;
  assertEquals(r.price_cents, 2190);
  assertEquals(r.unit_price_norm_cents, 2190);
  assertEquals(r.is_weighted, true);
});

Deno.test("Spar, Liter: Grundpreis in Cent je l", () => {
  const r = normalizeEntry(entry({ store: "spar", id: "2020002600662", name: "A-zwei Vollmilch laenger frisch", price: 2.08, unit: "l", quantity: 1 }))!;
  assertEquals(r.base_unit, "l");
  assertEquals(r.unit_price_norm_cents, 208);
});

Deno.test("ml und Stueck", () => {
  assertEquals(normalizeEntry(entry({ price: 1.5, unit: "ml", quantity: 500 }))!.unit_price_norm_cents, 300);
  const stk = normalizeEntry(entry({ price: 0.99, unit: "stk", quantity: 6 }))!;
  assertEquals(stk.base_unit, "stk");
  assertEquals(stk.unit_price_norm_cents, 17); // 99 / 6 = 16,5 -> 17
});

Deno.test("unbekannte Einheit (Waschgaenge 'wg'): Preis ohne Grundpreis statt falschem Wert", () => {
  const r = normalizeEntry(entry({ id: "00-771098", name: "Ariel All in One Color Waschmittelpods", price: 8.49, unit: "wg", quantity: 19 }))!;
  assertEquals(r.price_cents, 849);
  assertEquals(r.base_unit, null);
  assertEquals(r.unit_price_norm_cents, null);
  assertEquals(r.unit, "wg");
});

Deno.test("kaputt kodierte Einheit ergibt keinen Grundpreis", () => {
  assertEquals(normalizeEntry(entry({ unit: "st�ck" }))!.base_unit, null);
});

Deno.test("nicht im Sortiment: kein Ergebnis; das Feld fehlt bei verfuegbaren Artikeln im echten Feed ganz", () => {
  assertEquals(normalizeEntry(entry({ unavailable: true })), null);
  assertEquals(normalizeEntry(entry({ unavailable: false }))?.external_id, "00-600283");
  // Echter Feed (2026-10-02): verfuegbare Artikel tragen das Feld gar nicht
  const { unavailable: _u, ...ohne } = entry({});
  assertEquals(normalizeEntry(ohne)?.external_id, "00-600283");
});

Deno.test("numerische IDs (Hofer) werden zu Strings", () => {
  const r = normalizeEntry(entry({ store: "hofer", id: 547270, name: "HOFER MARKTPLATZ Knoblauch 400g", price: 2.29, unit: "g", quantity: 400 }))!;
  assertEquals(r.external_id, "547270");
});

Deno.test("Menge fehlt oder 0: Preis bleibt, kein Grundpreis", () => {
  assertEquals(normalizeEntry(entry({ price: 1.5, quantity: null }))!.unit_price_norm_cents, null);
  assertEquals(normalizeEntry(entry({ price: 1.5, quantity: 0 }))!.unit_price_norm_cents, null);
});

Deno.test("Name wird bereinigt (Tab, doppelte Leerzeichen); leere oder fehlende Namen und Preise fallen weg", () => {
  assertEquals(normalizeEntry(entry({ name: "\tVivoy  bei   Blasenschwaeche " }))!.name, "Vivoy bei Blasenschwaeche");
  assertEquals(normalizeEntry(entry({ name: "   " })), null);
  assertEquals(normalizeEntry(entry({ name: 5 })), null);
  assertEquals(normalizeEntry(entry({ price: "2,50" })), null);
  assertEquals(normalizeEntry(entry({ price: -1 })), null);
  assertEquals(normalizeEntry(entry({ price: Number.NaN })), null);
  assertEquals(normalizeEntry(entry({ id: undefined })), null);
});

// --- extractSlice: Zerlegen im echten Dateiformat ------------------------------------------------------------------

/** Baut einen Feed im echten Format (JSON.stringify mit Einrueckung 2, "store" als erstes Feld). */
function makeFeed(): { bytes: Uint8Array; expected: string[] } {
  const stores = ["billa", "billa", "billa", "dm", "dm", "spar", "spar", "spar", "spar", "sparSi"];
  const items = stores.map((store, i) => ({
    store,
    id: store === "spar" ? `20200${i}` : `00-${i}`,
    name: `Artikel ${i} äöüß € \u{1F95B}`, // Umlaute, Euro, Emoji: Mehrbyte-Zeichen in der Naehe der Abschnittsgrenzen
    description: "Beschreibung\nmit Zeilenumbruch und \"Anfuehrungszeichen\" und {Klammern} " + "x".repeat(150 + i * 37),
    price: 1 + i / 10,
    priceHistory: [{ date: "2024-01-04", price: 1 }, { date: "2023-04-06", price: 2 }],
    isWeighted: false,
    unit: "stk",
    quantity: 1,
    bio: false,
    url: `artikel-${i}`,
    category: "71",
    // wie im echten Feed: nur "true" wird geschrieben, sonst fehlt das Feld (undefined wird von stringify weggelassen);
    // Eintrag 2 hat es zusaetzlich ausdruecklich als false
    unavailable: i === 1 ? true : i === 2 ? false : undefined,
  }));
  const text = JSON.stringify(items, null, 2) + "\n";
  const expected = items.filter((it) => (it.store === "billa" || it.store === "spar") && !it.unavailable).map((it) => `${it.store}/${it.id}`);
  return { bytes: new TextEncoder().encode(text), expected };
}

/** Wie der Worker: Abschnitt planen, Fenster lesen, extrahieren. */
function runAllSlices(bytes: Uint8Array, sliceBytes: number, overlap: number): string[] {
  const out: string[] = [];
  for (const [start, end] of planSlices(bytes.length, sliceBytes)) {
    const w = fetchWindow(start, end, bytes.length, overlap);
    const window = bytes.subarray(w.from, w.to + 1);
    for (const r of extractSlice(window, w.from, start, end, w.isEof).rows) out.push(`${r.store}/${r.external_id}`);
  }
  return out;
}

Deno.test("Abschnitte: jeder verfuegbare Eintrag von Billa und Spar kommt genau einmal vor, egal wo die Grenzen liegen", () => {
  const { bytes, expected } = makeFeed();
  // viele verschiedene Abschnittsgroessen, damit Grenzen mitten in Eintraegen, in Mehrbyte-Zeichen und genau an Marken liegen
  for (const sliceBytes of [137, 256, 300, 411, 500, 777, 1024, 1500, 2048, 4096, bytes.length, bytes.length + 10]) {
    const got = runAllSlices(bytes, sliceBytes, 4000).sort();
    assertEquals(got, [...expected].sort(), `Abschnittsgroesse ${sliceBytes}`);
  }
});

Deno.test("Abschnitte: Eintraege anderer Haendler werden gezaehlt, aber nicht gelesen; Ergebnis stimmt auch bei einem Abschnitt", () => {
  const { bytes } = makeFeed();
  const r = extractSlice(bytes, 0, 0, bytes.length, true);
  assertEquals(r.owned, 10);
  assertEquals(r.rows.length, 6); // 2 billa (einer nicht verfuegbar) + 4 spar
  assertEquals(r.parseErrors, 0);
  assertEquals(r.rows.every((x) => x.store === "billa" || x.store === "spar"), true);
});

Deno.test("Mehrbyte-Zeichen im Namen bleiben erhalten", () => {
  const { bytes } = makeFeed();
  const r = extractSlice(bytes, 0, 0, bytes.length, true);
  assertEquals(r.rows[0].name, "Artikel 0 äöüß € \u{1F95B}");
});

Deno.test("zu kurze Ueberlappung wird gemeldet statt still falsch gelesen", () => {
  const { bytes } = makeFeed();
  // Fenster ohne Dateiende und mit einer Marke, deren Ende nicht im Fenster liegt
  const cut = bytes.subarray(0, 300);
  assertThrows(() => extractSlice(cut, 0, 0, 300, false), SliceTooShort);
});

Deno.test("ein unlesbarer Eintrag verwirft nicht den Rest", () => {
  const good = JSON.stringify([{ store: "billa", id: "1", name: "A", price: 1, unit: "stk", quantity: 1, unavailable: false }, { store: "billa", id: "2", name: "B", price: 2, unit: "stk", quantity: 1, unavailable: false }], null, 2);
  // beim zweiten Eintrag ein Komma zu viel, sonst gleiche Form
  const broken = good.replace('"id": "2",', '"id": "2",,');
  const bytes = new TextEncoder().encode(broken + "\n");
  const r = extractSlice(bytes, 0, 0, bytes.length, true);
  assertEquals(r.rows.map((x) => x.external_id), ["1"]);
  assertEquals(r.parseErrors, 1);
});

Deno.test("fetchWindow und planSlices", () => {
  assertEquals(planSlices(25, 10), [[0, 10], [10, 20], [20, 25]]);
  assertEquals(planSlices(0, 10), []);
  assertEquals(fetchWindow(0, 10, 100, 5), { from: 0, to: 14, isEof: false });
  assertEquals(fetchWindow(10, 20, 100, 5), { from: 9, to: 24, isEof: false });
  assertEquals(fetchWindow(90, 100, 100, 5), { from: 89, to: 99, isEof: true });
});

Deno.test("sanityOk: kein Loeschen bei Einbruch der Menge", () => {
  assertEquals(sanityOk(0, 100), true);
  assertEquals(sanityOk(0, 0), false);
  assertEquals(sanityOk(11848, 11000), true);
  assertEquals(sanityOk(11848, 3000), false);
  assertEquals(sanityOk(11848, 0), false);
  assertEquals(sanityOk(11848, 19793), false); // Feld "unavailable" umbenannt: alle Artikel wirkten verfuegbar
  assertEquals(sanityOk(50, 10), true); // kleine Bestaende: keine Schwelle
});

Deno.test("checkStores: der Ausfall eines Haendlers reisst die anderen nicht mit", () => {
  // Echter Fall 2026-11-01: Spar im Feed komplett unavailable, Billa normal
  assertEquals(checkStores(["billa", "spar"], { billa: 10707, spar: 22364 }, { billa: 10659, spar: 0 }), { ok: ["billa"], failed: ["spar"] });
  assertEquals(checkStores(["billa", "spar"], { billa: 10707, spar: 22364 }, { billa: 10659, spar: 22000 }), { ok: ["billa", "spar"], failed: [] });
  assertEquals(checkStores(["billa", "spar"], { billa: 10707, spar: 22364 }, { billa: 0, spar: 0 }), { ok: [], failed: ["billa", "spar"] });
});

Deno.test("Signatur: stimmt nur fuer dieselben Werte", async () => {
  const sig = await signSlice("geheim", "run-1", 0, 100);
  assertEquals(await verifySlice("geheim", "run-1", 0, 100, sig), true);
  assertEquals(await verifySlice("geheim", "run-1", 0, 101, sig), false);
  assertEquals(await verifySlice("geheim", "run-2", 0, 100, sig), false);
  assertEquals(await verifySlice("anderes", "run-1", 0, 100, sig), false);
  assertEquals(await verifySlice("geheim", "run-1", 0, 100, "zu kurz"), false);
  assertNotEquals(sig, await signSlice("geheim", "run-1", 0, 101));
});
