// Ablauf der Zuordnung nach dem Foto-Aufruf (Phase N1, ADR-031), mit eingesteckten Abhaengigkeiten, damit er ohne Netz und
// Datenbank mit `deno test` pruefbar ist (analyze_test.ts). index.ts setzt die echten Aufrufe ein.

import {
  candidatesOf,
  effectiveState,
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

/// Sucht unter dem Namen der Zutat und, solange es keinen Treffer gibt, unter ihren anderen Namen ("Rote Beete" findet die Suche nicht,
/// "Rote Bete" schon). Ein Treffer ueber einen anderen Namen gilt nur als automatisch: So hiess die Zutat ja nicht. Er zaehlt auch nur, wenn er den
/// ganzen anderen Namen abdeckt und kein genauerer Name schon Kandidaten brachte: Die Namen werden allgemeiner, und fuer ein Wassereis fand
/// "Eis am Stiel" und "Speiseeis" das Vanilleeis (194 kcal), obwohl "Fruchteis" (128 kcal) schon gefunden war. Dann entscheidet die KI-Auswahl.
/// Enthaelt ein Kandidat alle Woerter des Namens selbst ("Tomatensauce"), bleibt es bei diesen Kandidaten ("Tomatenmark" kommt nicht dazu).
async function searchAll(name: string, terms: string[], state: State | null, deps: Deps): Promise<{ rows: FoodRow[]; match: Match | null }> {
  const rows: FoodRow[] = [];
  let sawCandidates = false;
  for (const [i, term] of [name, ...terms].entries()) {
    let found: FoodRow[] = [];
    try {
      found = await deps.search(searchQuery(term, effectiveState(term, state)));
    } catch (e) {
      console.error("search_failed", term, e);
    }
    rows.push(...found);
    const match = pickMatch(found, effectiveState(term, state));
    if (match && (i === 0 || (!sawCandidates && found.find((r) => r.bls_code === match.code)!.coverage >= 1))) {
      return { rows, match: i === 0 ? match : { ...match, method: "search", trust: "auto" } };
    }
    if (i === 0 && found.some((r) => r.coverage >= 1)) break;
    sawCandidates ||= found.length > 0;
  }
  return { rows, match: null };
}

/// Ordnet die erkannten Zutaten Eintraegen der Lebensmitteldatenbank zu: erst die Suche (sichere und automatische Treffer
/// gelten, wenn sie zum Zustand passen), dann fuer den Rest die KI-Auswahl aus den Kandidaten, sonst unbekannt.
export async function resolveIngredients(
  ingredients: { name: string; state: State | null; search_terms?: string[] }[],
  deps: Deps,
): Promise<Resolution> {
  const found = await Promise.all(ingredients.map((i) => searchAll(i.name, i.search_terms ?? [], i.state, deps)));
  const rows: FoodRow[][] = found.map((f) => f.rows);

  const matches: (Match | null)[] = found.map((f) => f.match);
  const stats = { sure: 0, auto: 0, llm: 0, unknown: 0 };

  // Fuer alle ohne sicheren Treffer, aber mit Kandidaten: eine gemeinsame KI-Auswahl
  const items: ChooseItem[] = [];
  rows.forEach((r, index) => {
    if (matches[index] !== null) return;
    const state = effectiveState(ingredients[index].name, ingredients[index].state);
    const candidates = candidatesOf(r, state);
    if (candidates.length > 0) items.push({ index, name: ingredients[index].name, state, candidates });
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
