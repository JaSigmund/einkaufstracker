// Tests fuer resolve.ts und analyze.ts. Lokal und in der CI: `deno test`
import { assertEquals } from "jsr:@std/assert@1";
import { resolveIngredients, type Usage } from "./analyze.ts";
import {
  buildChoosePrompt,
  candidatesOf,
  type ChooseItem,
  type FoodRow,
  MAX_CANDIDATES,
  matchFromRow,
  parseFoodRow,
  pickMatch,
  sanitizeChoices,
  searchQuery,
} from "./resolve.ts";

const row = (over: Partial<FoodRow> & { bls_code: string; name_de: string }): FoodRow => ({
  score: 20,
  method: "search",
  rank: 1,
  confidence: "unsure",
  coverage: 1,
  kcal: 100,
  protein_g: 5,
  fat_g: 2,
  sat_fat_g: 1,
  carbs_g: 15,
  sugar_g: 3,
  fiber_g: 2,
  salt_g: 0.1,
  ...over,
});

Deno.test("parseFoodRow: liest Zahlen als Zahl oder als Text, fehlende Naehrwerte bleiben null", () => {
  const r = parseFoodRow({ bls_code: "F503100", name_de: "Banane roh", score: "29.5", method: "synonym", rank: 1, confidence: "sure", coverage: "1.00", kcal: "79", protein_g: 1.1, fat_g: null })!;
  assertEquals(r.bls_code, "F503100");
  assertEquals(r.score, 29.5);
  assertEquals(r.kcal, 79);
  assertEquals(r.protein_g, 1.1);
  assertEquals(r.fat_g, null);
  assertEquals(r.salt_g, null);
  assertEquals(r.method, "synonym");
  assertEquals(r.confidence, "sure");
});

Deno.test("parseFoodRow: Zeile ohne Code oder Name oder kein Objekt ist ungueltig, unbekannte Werte werden zu search/unsure", () => {
  assertEquals(parseFoodRow(null), null);
  assertEquals(parseFoodRow("x"), null);
  assertEquals(parseFoodRow({ name_de: "ohne Code" }), null);
  assertEquals(parseFoodRow({ bls_code: "X" }), null);
  const r = parseFoodRow({ bls_code: "A", name_de: "B", method: "irgendwas", confidence: "super" })!;
  assertEquals(r.method, "search");
  assertEquals(r.confidence, "unsure");
});

Deno.test("searchQuery: gekocht steht im Text, roh und fertig gekauft nicht", () => {
  assertEquals(searchQuery("Reis", "cooked"), "Reis gekocht");
  assertEquals(searchQuery("  Reis ", "raw"), "Reis");
  assertEquals(searchQuery("Pommes frites", "ready_made"), "Pommes frites");
  assertEquals(searchQuery("Reis", null), "Reis");
});

Deno.test("pickMatch: sicherer und automatischer Treffer gelten, unsicherer nicht", () => {
  const sure = pickMatch([row({ bls_code: "C352000", name_de: "Reis poliert, roh", confidence: "sure", method: "synonym" })])!;
  assertEquals(sure.trust, "sure");
  assertEquals(sure.method, "synonym");
  assertEquals(sure.code, "C352000");
  assertEquals(sure.per100.kcal, 100);
  const auto = pickMatch([row({ bls_code: "F503100", name_de: "Banane roh", confidence: "auto" })])!;
  assertEquals(auto.trust, "auto");
  assertEquals(pickMatch([row({ bls_code: "X", name_de: "Y", confidence: "unsure" })]), null);
  assertEquals(pickMatch([]), null);
});

Deno.test("pickMatch: nur Rang 1 zaehlt, auch wenn die Liste anders sortiert ist", () => {
  const rows = [row({ bls_code: "B", name_de: "zweiter", rank: 2, confidence: "unsure" }), row({ bls_code: "A", name_de: "erster", rank: 1, confidence: "auto" })];
  assertEquals(pickMatch(rows)?.code, "A");
});

Deno.test("candidatesOf: hoechstens acht, ohne doppelte Codes, in Reihenfolge", () => {
  const rows = Array.from({ length: 12 }, (_, i) => row({ bls_code: `C${i}`, name_de: `n${i}`, rank: i + 1 }));
  rows.splice(3, 0, row({ bls_code: "C1", name_de: "doppelt", rank: 4 }));
  const c = candidatesOf(rows);
  assertEquals(c.length, MAX_CANDIDATES);
  assertEquals(c.map((x) => x.code), ["C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7"]);
  assertEquals(c[1].name, "n1");
});

Deno.test("matchFromRow: Verfahren und Vertrauen lassen sich ueberschreiben (KI-Auswahl)", () => {
  const m = matchFromRow(row({ bls_code: "A", name_de: "B" }), "llm", "auto");
  assertEquals(m.method, "llm");
  assertEquals(m.trust, "auto");
});

const items: ChooseItem[] = [
  { index: 0, name: "Quark", state: null, candidates: [{ code: "M713300", name: "Speisequark Halbfettstufe" }, { code: "M713100", name: "Speisequark Magerstufe" }] },
  { index: 2, name: "Reis", state: "cooked", candidates: [{ code: "C352032", name: "Reis poliert, gekocht" }] },
];

Deno.test("buildChoosePrompt: Name, Zustand und Kandidaten je Zutat", () => {
  const p = buildChoosePrompt(items);
  assertEquals(p.includes("0. Quark\n   - M713300: Speisequark Halbfettstufe"), true);
  assertEquals(p.includes("2. Reis (gekocht)\n   - C352032: Reis poliert, gekocht"), true);
  assertEquals(p.includes("submit_choices"), true);
});

Deno.test("sanitizeChoices: nur Codes aus der Kandidatenliste der jeweiligen Zutat", () => {
  const raw = { choices: [{ index: 0, bls_code: "M713100", confidence: 0.9 }, { index: 2, bls_code: "M713100", confidence: 0.9 }] };
  const out = sanitizeChoices(raw, items);
  assertEquals(out.get(0), "M713100");
  assertEquals(out.has(2), false, "ein Code, der bei dieser Zutat nicht zur Auswahl stand, wird verworfen, auch wenn er woanders existiert");
});

Deno.test("sanitizeChoices: erfundene Codes, leerer Code, unbekannter Index, doppelte Antworten und Unlesbares fallen weg", () => {
  const raw = {
    choices: [
      { index: 0, bls_code: "ERFUNDEN", confidence: 1 },
      { index: 2, bls_code: "", confidence: 1 },
      { index: 7, bls_code: "M713300", confidence: 1 },
      { index: "0", bls_code: "M713300" },
      { index: 0, bls_code: 5 },
      null,
      "x",
      { index: 0, bls_code: " M713300 ", confidence: 0.4 },
      { index: 0, bls_code: "M713100", confidence: 0.4 },
    ],
  };
  const out = sanitizeChoices(raw, items);
  assertEquals([...out.entries()], [[0, "M713300"]], "Leerzeichen werden abgeschnitten, die erste gueltige Antwort je Zutat gilt");
  assertEquals(sanitizeChoices(null, items).size, 0);
  assertEquals(sanitizeChoices({ choices: "nein" }, items).size, 0);
  assertEquals(sanitizeChoices({}, items).size, 0);
});

// --- resolveIngredients -----------------------------------------------------------------------------------------------

const usage: Usage = { input_tokens: 700, output_tokens: 90 };

function deps(table: Record<string, FoodRow[]>, choose: (items: ChooseItem[]) => { choices: unknown; usage: Usage } | null | Error = () => null) {
  const calls = { search: [] as string[], choose: [] as ChooseItem[][] };
  return {
    calls,
    search: (q: string) => {
      calls.search.push(q);
      return Promise.resolve(table[q] ?? []);
    },
    choose: (it: ChooseItem[]) => {
      calls.choose.push(it);
      const r = choose(it);
      return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
    },
  };
}

Deno.test("resolveIngredients: sichere und automatische Treffer brauchen keine KI", async () => {
  const d = deps({
    "Reis gekocht": [row({ bls_code: "C352032", name_de: "Reis poliert, gekocht", confidence: "sure", method: "synonym" })],
    "Banane": [row({ bls_code: "F503100", name_de: "Banane roh", confidence: "auto" })],
  });
  const r = await resolveIngredients([{ name: "Reis", state: "cooked" }, { name: "Banane", state: "raw" }], d);
  assertEquals(r.matches.map((m) => m?.code), ["C352032", "F503100"]);
  assertEquals(r.matches.map((m) => m?.trust), ["sure", "auto"]);
  assertEquals(d.calls.search, ["Reis gekocht", "Banane"]);
  assertEquals(d.calls.choose.length, 0, "kein zweiter Aufruf ohne ungeloeste Zutat");
  assertEquals(r.usage, null);
  assertEquals(r.stats, { sure: 1, auto: 1, llm: 0, unknown: 0 });
});

Deno.test("resolveIngredients: ungeloeste Zutaten mit Kandidaten gehen gemeinsam in einen KI-Aufruf, das Ergebnis gilt als automatisch", async () => {
  const quark = [row({ bls_code: "M713300", name_de: "Speisequark Halbfettstufe" }), row({ bls_code: "M713100", name_de: "Speisequark Magerstufe", rank: 2 })];
  const kefir = [row({ bls_code: "M120000", name_de: "Kefir" })];
  const d = deps(
    { "Quark": quark, "Kefir": kefir, "Banane": [row({ bls_code: "F503100", name_de: "Banane roh", confidence: "auto" })] },
    () => ({ choices: { choices: [{ index: 0, bls_code: "M713300", confidence: 0.8 }, { index: 2, bls_code: "M120000", confidence: 0.6 }] }, usage }),
  );
  const r = await resolveIngredients([{ name: "Quark", state: null }, { name: "Banane", state: "raw" }, { name: "Kefir", state: null }], d);
  assertEquals(d.calls.choose.length, 1);
  assertEquals(d.calls.choose[0].map((i) => i.index), [0, 2], "nur die Zutaten ohne Treffer");
  assertEquals(d.calls.choose[0][0].candidates.map((c) => c.code), ["M713300", "M713100"]);
  assertEquals(r.matches.map((m) => m?.code), ["M713300", "F503100", "M120000"]);
  assertEquals(r.matches[0]?.method, "llm");
  assertEquals(r.matches[0]?.trust, "auto");
  assertEquals(r.matches[0]?.per100.kcal, 100, "die Naehrwerte kommen aus der Datenbankzeile, nicht vom Modell");
  assertEquals(r.usage, usage);
  assertEquals(r.stats, { sure: 0, auto: 1, llm: 2, unknown: 0 });
});

Deno.test("resolveIngredients: erfundener Code der KI wird verworfen, die Zutat bleibt unbekannt", async () => {
  const d = deps({ "Quark": [row({ bls_code: "M713300", name_de: "Speisequark" })] }, () => ({ choices: { choices: [{ index: 0, bls_code: "ERFUNDEN", confidence: 1 }] }, usage }));
  const r = await resolveIngredients([{ name: "Quark", state: null }], d);
  assertEquals(r.matches, [null]);
  assertEquals(r.stats.unknown, 1);
  assertEquals(r.usage, usage, "der Aufruf lief trotzdem und wird verrechnet");
});

Deno.test("resolveIngredients: keine Kandidaten: kein KI-Aufruf, unbekannt", async () => {
  const d = deps({});
  const r = await resolveIngredients([{ name: "Gemuesepfanne", state: "cooked" }], d);
  assertEquals(r.matches, [null]);
  assertEquals(d.calls.choose.length, 0);
  assertEquals(r.stats, { sure: 0, auto: 0, llm: 0, unknown: 1 });
});

Deno.test("resolveIngredients: Fehler der Suche oder der KI lassen die Analyse nie scheitern", async () => {
  const failingSearch = {
    search: () => Promise.reject(new Error("db down")),
    choose: () => Promise.resolve(null),
  };
  const r1 = await resolveIngredients([{ name: "Reis", state: null }, { name: "Ei", state: null }], failingSearch);
  assertEquals(r1.matches, [null, null]);

  const d = deps({ "Quark": [row({ bls_code: "M713300", name_de: "Speisequark" })] }, () => new Error("api down"));
  const r2 = await resolveIngredients([{ name: "Quark", state: null }], d);
  assertEquals(r2.matches, [null]);
  assertEquals(r2.usage, null);

  const d2 = deps({ "Quark": [row({ bls_code: "M713300", name_de: "Speisequark" })] }, () => null);
  const r3 = await resolveIngredients([{ name: "Quark", state: null }], d2);
  assertEquals(r3.matches, [null]);
});

Deno.test("resolveIngredients: leere Zutatenliste", async () => {
  const d = deps({});
  const r = await resolveIngredients([], d);
  assertEquals(r.matches, []);
  assertEquals(d.calls.search.length, 0);
});
