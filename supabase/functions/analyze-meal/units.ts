// Stueckzahlen aus dem Foto in Gramm umrechnen (Phase N2, ADR-033).
//
// "2 Eier", "1 Banane", "3 Scheiben Brot": die KI zaehlt, die Function rechnet mit den Gewichten aus der Datenbank. Die KI schaetzt
// kein Stueckgewicht. Reihenfolge der Gewichte (wie in der App): eigenes Gewicht des Haushalts > Tabelle `food_units` (USDA,
// auf den essbaren Anteil bezogen). Gibt es keines, bleibt es bei der Gramm-Schaetzung der KI.
//
// Reine Logik ohne Netz- und Datenbankzugriff (units_test.ts).

export const UNIT_KEYS = ["piece", "slice", "tbsp", "tsp", "clove", "head", "stalk"] as const;
export type UnitKey = typeof UNIT_KEYS[number];
export type Size = "" | "small" | "medium" | "large";

/// Eine Zeile aus `food_units`.
export type UnitRow = { bls_code: string; unit_key: UnitKey; size: Size; grams_edible: number; source: string };

/// Die Stueckangabe zu einer Zutat, wie sie die App bekommt.
export type UnitInfo = {
  /// Anzahl der Einheiten (auch halbe).
  count: number;
  unit_key: UnitKey;
  /// Gewicht einer Einheit in Gramm (essbarer Anteil).
  unit_weight_g: number;
  /// `household` (eigenes Gewicht) oder die Quelle der Tabelle (`usda`, `off`, `curated`, `llm_estimate`).
  unit_source: string;
  size: Size;
};

const SIZE_ORDER: Size[] = ["medium", "", "small", "large"];

/// Waehlt aus den Zeilen einer Einheit die passende Groesse: mittel, sonst ohne Angabe, sonst die mittlere der vorhandenen.
export function pickSize(rows: UnitRow[]): UnitRow | null {
  if (rows.length === 0) return null;
  for (const s of SIZE_ORDER) {
    const hit = rows.find((r) => r.size === s);
    if (hit) return hit;
  }
  return null;
}

/// Die Zeile der gezaehlten Einheit (nur genau diese: aus Scheiben werden keine Stuecke). `null`, wenn die Tabelle sie nicht kennt.
export function pickUnit(rows: UnitRow[], wanted: UnitKey): UnitRow | null {
  return pickSize(rows.filter((r) => r.unit_key === wanted));
}

/// Rechnet eine Zaehlung in Gramm um. `householdWeightG` ist das eigene Gewicht von 1 Stueck des Haushalts und gilt nur fuer
/// Stueck. `null`, wenn kein Gewicht bekannt ist: dann behaelt die Zutat die Gramm-Schaetzung der KI.
export function unitInfoFor(
  count: number | null,
  wanted: UnitKey,
  rows: UnitRow[],
  householdWeightG: number | null,
): UnitInfo | null {
  if (count === null || !(count > 0)) return null;
  if (wanted === "piece" && householdWeightG !== null && householdWeightG > 0) {
    return { count, unit_key: "piece", unit_weight_g: householdWeightG, unit_source: "household", size: "" };
  }
  const row = pickUnit(rows, wanted);
  if (!row) return null;
  return { count, unit_key: row.unit_key, unit_weight_g: row.grams_edible, unit_source: row.source, size: row.size };
}

/// Gesamtmenge in Gramm, auf ganze Gramm gerundet (bei Kleinstmengen wie Mandeln auf eine Nachkommastelle).
export function totalGrams(info: UnitInfo): number {
  const g = info.count * info.unit_weight_g;
  return g >= 20 ? Math.round(g) : Math.round(g * 10) / 10;
}
