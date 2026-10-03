// Ablauf der Zuordnung nach dem Foto-Aufruf (Phase N1, ADR-031), mit eingesteckten Abhaengigkeiten, damit er ohne Netz und
// Datenbank mit `deno test` pruefbar ist (analyze_test.ts). index.ts setzt die echten Aufrufe ein.

import {
  candidatesOf,
  type ChooseItem,
  type FoodRow,
  type Match,
  matchFromRow,
  pickMatch,
  sanitizeChoices,
  searchQuery,
  type State,
} from "./resolve.ts";

export type Usage = { input_tokens: number; output_tokens: number };

export type Deps = {
  /// Ruft search_bls_foods auf. Ein Fehler zaehlt als "keine Treffer" (die Analyse scheitert nie daran).
  search(query: string): Promise<FoodRow[]>;
  /// Zweiter KI-Aufruf (nur Text): liefert die rohe Tool-Antwort und den Verbrauch, oder `null`, wenn er scheitert.
  choose(items: ChooseItem[]): Promise<{ choices: unknown; usage: Usage } | null>;
};

export type Resolution = {
  /// Treffer je Zutat in der Reihenfolge der Eingabe, `null` = unbekannt.
  matches: (Match | null)[];
  /// Verbrauch des KI-Aufrufs, `null`, wenn keiner noetig war oder er scheiterte.
  usage: Usage | null;
  /// Fuer das Protokoll: wie viele Zutaten ueber welchen Weg gefunden wurden.
  stats: { sure: number; auto: number; llm: number; unknown: number };
};

/// Ordnet die erkannten Zutaten Eintraegen der Lebensmitteldatenbank zu: erst die Suche (sichere und automatische Treffer
/// gelten), dann fuer den Rest die KI-Auswahl aus den Kandidaten, sonst unbekannt.
export async function resolveIngredients(
  ingredients: { name: string; state: State | null }[],
  deps: Deps,
): Promise<Resolution> {
  const rows: FoodRow[][] = await Promise.all(
    ingredients.map(async (i) => {
      try {
        return await deps.search(searchQuery(i.name, i.state));
      } catch (e) {
        console.error("search_failed", i.name, e);
        return [];
      }
    }),
  );

  const matches: (Match | null)[] = rows.map((r) => pickMatch(r));
  const stats = { sure: 0, auto: 0, llm: 0, unknown: 0 };

  // Fuer alle ohne sicheren Treffer, aber mit Kandidaten: eine gemeinsame KI-Auswahl
  const items: ChooseItem[] = [];
  rows.forEach((r, index) => {
    if (matches[index] !== null) return;
    const candidates = candidatesOf(r);
    if (candidates.length > 0) items.push({ index, name: ingredients[index].name, state: ingredients[index].state, candidates });
  });

  let usage: Usage | null = null;
  if (items.length > 0) {
    try {
      const result = await deps.choose(items);
      if (result) {
        usage = result.usage;
        for (const [index, code] of sanitizeChoices(result.choices, items)) {
          const row = rows[index].find((r) => r.bls_code === code);
          if (row) {
            matches[index] = matchFromRow(row, "llm", "auto");
            stats.llm++;
          }
        }
      }
    } catch (e) {
      console.error("choose_failed", e);
    }
  }

  for (const m of matches) {
    if (m === null) stats.unknown++;
    else if (m.method === "llm") continue;
    else if (m.trust === "sure") stats.sure++;
    else stats.auto++;
  }
  return { matches, usage, stats };
}
