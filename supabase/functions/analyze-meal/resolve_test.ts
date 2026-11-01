// Tests fuer resolve.ts und analyze.ts. Lokal und in der CI: `deno test`
import { assertEquals } from "jsr:@std/assert@1";
import { resolveIngredients, type Usage } from "./analyze.ts";
import {
  buildChoosePrompt,
  candidatesOf,
  type ChooseItem,
  effectiveState,
  type FoodRow,
  MAX_CANDIDATES,
  matchFromRow,
  parseFoodRow,
  parseNutrients,
  pickMatch,
  sanitizeChoices,
  searchQuery,
  stateFits,
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
  nutrients: null,
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

Deno.test("candidatesOf: begrenzt, ohne doppelte Codes, in Reihenfolge", () => {
  const rows = Array.from({ length: MAX_CANDIDATES + 4 }, (_, i) => row({ bls_code: `C${i}`, name_de: `n${i}`, rank: i + 1 }));
  rows.splice(3, 0, row({ bls_code: "C1", name_de: "doppelt", rank: 4 }));
  const c = candidatesOf(rows);
  assertEquals(c.length, MAX_CANDIDATES);
  assertEquals(c.map((x) => x.code), Array.from({ length: MAX_CANDIDATES }, (_, i) => `C${i}`));
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

Deno.test("parseNutrients: nur Zahlen, nicht negativ, Text-Zahlen gelesen; leer oder falscher Typ ist null", () => {
  assertEquals(parseNutrients({ vit_c_mg: 11, iron_mg: "0,4", zinc_mg: -1, x: "viel", y: null, z: NaN }), { vit_c_mg: 11, iron_mg: 0.4 });
  assertEquals(parseNutrients({}), null);
  assertEquals(parseNutrients(null), null);
  assertEquals(parseNutrients([1, 2]), null);
  assertEquals(parseNutrients("{}"), null);
  assertEquals(parseNutrients({ a: 0 }), { a: 0 }, "eine echte 0 bleibt");
});

Deno.test("parseFoodRow und Treffer: die Naehrstoffe werden mitgenommen", () => {
  const r = parseFoodRow({ bls_code: "F503100", name_de: "Banane roh", confidence: "sure", method: "synonym", rank: 1, nutrients: { vit_c_mg: 11, potassium_mg: 334 } })!;
  assertEquals(r.nutrients, { vit_c_mg: 11, potassium_mg: 334 });
  assertEquals(matchFromRow(r).nutrients, { vit_c_mg: 11, potassium_mg: 334 });
  assertEquals(parseFoodRow({ bls_code: "A", name_de: "B" })!.nutrients, null);
  assertEquals(pickMatch([row({ bls_code: "F503100", name_de: "Banane roh", confidence: "sure", method: "synonym", nutrients: { vit_c_mg: 11 } })])!.nutrients, { vit_c_mg: 11 });
});

// Echte Faelle aus der Produktionsdatenbank (2026-11-01): die Suche lieferte sie als "sicher"
Deno.test("pickMatch: sicherer Treffer im falschen Zustand zaehlt nicht", () => {
  const linse = row({ bls_code: "H725100", name_de: "Linse reif", method: "synonym", confidence: "sure", kcal: 323 });
  assertEquals(pickMatch([linse], "cooked"), null);
  const rind = row({ bls_code: "U202000", name_de: "Rind Fleisch, fett- und sehnenfrei (R I) roh", method: "synonym", confidence: "sure" });
  assertEquals(pickMatch([rind], "cooked"), null);
  const schnitzel = row({ bls_code: "U541100", name_de: "Schwein Schnitzel (Oberschale) roh", method: "synonym", confidence: "sure" });
  assertEquals(pickMatch([schnitzel], "ready_made"), null);
});

Deno.test("pickMatch: passender Zustand und Gedaechtnis des Haushalts gelten weiter", () => {
  const reis = row({ bls_code: "C352032", name_de: "Reis poliert, gekocht", method: "synonym", confidence: "sure" });
  assertEquals(pickMatch([reis], "cooked")?.code, "C352032");
  const schinken = row({ bls_code: "W424000", name_de: "Schwein Kochschinken, Kochpökelware", method: "synonym", confidence: "sure" });
  assertEquals(pickMatch([schinken], "cooked")?.code, "W424000");
  const gemerkt = row({ bls_code: "H725100", name_de: "Linse reif", method: "memory", confidence: "sure" });
  assertEquals(pickMatch([gemerkt], "cooked")?.code, "H725100");
  const apfel = row({ bls_code: "F110100", name_de: "Apfel roh", method: "synonym", confidence: "sure" });
  assertEquals(pickMatch([apfel], "raw")?.code, "F110100");
  assertEquals(pickMatch([apfel])?.code, "F110100");
});

Deno.test("stateFits: roh passt nie zu gekocht oder fertig, Gerichte sind immer zubereitet", () => {
  assertEquals(stateFits("Avocado roh", "F502100", "ready_made"), false);
  assertEquals(stateFits("Rohkost", "G100000", "ready_made"), true);
  assertEquals(stateFits("Pizza Margherita", "X912033", "cooked"), true);
  assertEquals(stateFits("Kidneybohne reif, Konserve, abgetropft", "H742902", "cooked"), true);
  assertEquals(stateFits("Kidneybohne reif", "H742100", "cooked"), false);
});

Deno.test("effectiveState: Reis, Nudeln und Huelsenfruechte sind nie trocken auf dem Teller", () => {
  assertEquals(effectiveState("Kidneybohnen", "ready_made"), "cooked");
  assertEquals(effectiveState("Basmatireis", null), "cooked");
  assertEquals(effectiveState("Linsen", "raw"), "cooked");
  assertEquals(effectiveState("Schwarze Bohnen", null), "cooked");
  assertEquals(effectiveState("Reiswaffel", "ready_made"), "ready_made");
  assertEquals(effectiveState("Wassereis", "ready_made"), "ready_made");
  assertEquals(effectiveState("Tomate", "raw"), "raw");
});

Deno.test("candidatesOf: Eintraege im passenden Zustand zuerst", () => {
  const rows = [
    row({ bls_code: "H725100", name_de: "Linse reif" }),
    row({ bls_code: "H730132", name_de: "Linse reif, gekocht" }),
  ];
  assertEquals(candidatesOf(rows, "cooked").map((c) => c.code), ["H730132", "H725100"]);
  assertEquals(candidatesOf(rows).map((c) => c.code), ["H725100", "H730132"]);
});

Deno.test("buildChoosePrompt: nennt das Gericht, wenn es eines gibt", () => {
  const items = [{ index: 0, name: "Teig", state: null, candidates: [{ code: "A", name: "Hefeteig" }] }];
  assertEquals(buildChoosePrompt(items, "Pizzabrötchen").startsWith("Gericht: Pizzabrötchen\n\n"), true);
  assertEquals(buildChoosePrompt(items).startsWith("Zutaten und Kandidaten"), true);
});


Deno.test("resolveIngredients: findet der Name nichts, helfen die anderen Namen, der Treffer gilt dann nur als automatisch", async () => {
  const queries: string[] = [];
  const res = await resolveIngredients([{ name: "Rote Beete", state: "raw", search_terms: ["Rote Bete"] }], {
    search: (q) => {
      queries.push(q);
      return Promise.resolve(q === "Rote Bete" ? [row({ bls_code: "G613100", name_de: "Rote Rübe/Rote Bete, roh", method: "synonym", confidence: "sure" })] : []);
    },
    choose: () => Promise.reject(new Error("nicht noetig")),
  });
  assertEquals(queries, ["Rote Beete", "Rote Bete"]);
  assertEquals(res.matches[0]?.code, "G613100");
  assertEquals(res.matches[0]?.trust, "auto");
  assertEquals(res.matches[0]?.method, "search");
});

Deno.test("resolveIngredients: gekochte Linsen landen ueber die KI-Auswahl beim gekochten Eintrag", async () => {
  const linse = row({ bls_code: "H725100", name_de: "Linse reif", method: "synonym", confidence: "sure", kcal: 323 });
  const gekocht = row({ bls_code: "H730132", name_de: "Linse reif, gekocht", rank: 2, kcal: 119 });
  const seen: ChooseItem[][] = [];
  const res = await resolveIngredients([{ name: "Linsen", state: "cooked" }], {
    search: () => Promise.resolve([linse, gekocht]),
    choose: (items) => {
      seen.push(items);
      return Promise.resolve({ choices: { choices: [{ index: 0, bls_code: "H730132", confidence: 0.9 }] }, usage });
    },
  });
  assertEquals(seen[0][0].candidates[0].code, "H730132");
  assertEquals(res.matches[0]?.code, "H730132");
  assertEquals(res.matches[0]?.method, "llm");
});

Deno.test("resolveIngredients: Kidneybohnen aus der Dose werden als gekocht gesucht", async () => {
  const queries: string[] = [];
  await resolveIngredients([{ name: "Kidneybohnen", state: "ready_made" }], {
    search: (q) => {
      queries.push(q);
      return Promise.resolve([]);
    },
    choose: () => Promise.resolve(null),
  });
  assertEquals(queries, ["Kidneybohnen gekocht"]);
});

Deno.test("resolveIngredients: ein anderer Name zaehlt nur, wenn er ganz abgedeckt ist (echter Fall Wassereis)", async () => {
  const vanille = row({ bls_code: "S241000", name_de: "Vanilleeis", method: "synonym", confidence: "auto", coverage: 0.99, kcal: 194 });
  const frucht = row({ bls_code: "S300000", name_de: "Fruchteis", rank: 1, coverage: 1 });
  const seen: ChooseItem[][] = [];
  const res = await resolveIngredients([{ name: "Wassereis", state: "ready_made", search_terms: ["Eis am Stiel", "Fruchteis"] }], {
    search: (q) => Promise.resolve(q === "Eis am Stiel" ? [vanille] : q === "Fruchteis" ? [frucht] : []),
    choose: (items) => {
      seen.push(items);
      return Promise.resolve({ choices: { choices: [{ index: 0, bls_code: "S300000", confidence: 0.8 }] }, usage });
    },
  });
  assertEquals(seen[0][0].candidates.map((c) => c.code).sort(), ["S241000", "S300000"]);
  assertEquals(res.matches[0]?.code, "S300000");
});

Deno.test("resolveIngredients: passt ein Kandidat zum ganzen Namen, gewinnt kein anderer Name (echter Fall Tomatensauce)", async () => {
  const queries: string[] = [];
  const sauce = row({ bls_code: "X331353", name_de: "Tomatensauce italienische Art", confidence: "unsure", coverage: 1, kcal: 55 });
  const res = await resolveIngredients([{ name: "Tomatensauce", state: "ready_made", search_terms: ["Tomatenmark"] }], {
    search: (q) => {
      queries.push(q);
      return Promise.resolve([sauce]);
    },
    choose: () => Promise.resolve({ choices: { choices: [{ index: 0, bls_code: "X331353", confidence: 0.8 }] }, usage }),
  });
  assertEquals(queries, ["Tomatensauce"]);
  assertEquals(res.matches[0]?.code, "X331353");
});
