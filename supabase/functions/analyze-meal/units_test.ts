// Tests fuer units.ts. Lokal und in der CI: `deno test units_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import { pickSize, pickUnit, totalGrams, unitInfoFor, type UnitRow } from "./units.ts";

const row = (unit_key: UnitRow["unit_key"], size: UnitRow["size"], grams: number, source = "usda"): UnitRow => ({
  bls_code: "F503100",
  unit_key,
  size,
  grams_edible: grams,
  source,
});

const banane = [row("piece", "small", 101), row("piece", "medium", 118), row("piece", "large", 136)];

Deno.test("pickSize: mittel zuerst, sonst ohne Groesse, sonst klein, sonst gross", () => {
  assertEquals(pickSize(banane)?.grams_edible, 118);
  assertEquals(pickSize([row("piece", "", 50), row("piece", "large", 60)])?.grams_edible, 50);
  assertEquals(pickSize([row("piece", "small", 30), row("piece", "large", 60)])?.grams_edible, 30);
  assertEquals(pickSize([row("piece", "large", 60)])?.grams_edible, 60);
  assertEquals(pickSize([]), null);
});

Deno.test("pickUnit: nur die genannte Einheit, aus Scheiben werden keine Stuecke", () => {
  const brot = [row("slice", "", 28)];
  assertEquals(pickUnit(brot, "slice")?.grams_edible, 28);
  assertEquals(pickUnit(brot, "piece"), null);
  assertEquals(pickUnit(banane, "slice"), null);
});

Deno.test("unitInfoFor: 2 Bananen aus der Tabelle (mittel), Quelle usda", () => {
  const info = unitInfoFor(2, "piece", banane, null)!;
  assertEquals(info, { count: 2, unit_key: "piece", unit_weight_g: 118, unit_source: "usda", size: "medium" });
  assertEquals(totalGrams(info), 236);
});

Deno.test("unitInfoFor: das eigene Gewicht des Haushalts geht der Tabelle vor, nur fuer Stueck", () => {
  assertEquals(unitInfoFor(1, "piece", banane, 135), { count: 1, unit_key: "piece", unit_weight_g: 135, unit_source: "household", size: "" });
  const brot = [row("slice", "", 28), row("piece", "", 500)];
  assertEquals(unitInfoFor(3, "slice", brot, 90)?.unit_weight_g, 28, "Scheiben rechnen mit der Tabelle, nicht mit dem Stueckgewicht");
});

Deno.test("unitInfoFor: ohne Gewicht oder ohne Anzahl null (die KI-Schaetzung in Gramm bleibt)", () => {
  assertEquals(unitInfoFor(2, "piece", [], null), null);
  assertEquals(unitInfoFor(2, "tbsp", banane, null), null);
  assertEquals(unitInfoFor(null, "piece", banane, null), null);
  assertEquals(unitInfoFor(0, "piece", banane, null), null);
  assertEquals(unitInfoFor(1, "piece", banane, 0), unitInfoFor(1, "piece", banane, null), "Gewicht 0 zaehlt nicht");
});

Deno.test("totalGrams: ganze Gramm, bei Kleinstmengen eine Nachkommastelle", () => {
  assertEquals(totalGrams({ count: 1.5, unit_key: "piece", unit_weight_g: 118, unit_source: "usda", size: "medium" }), 177);
  assertEquals(totalGrams({ count: 10, unit_key: "piece", unit_weight_g: 1.2, unit_source: "usda", size: "" }), 12);
  assertEquals(totalGrams({ count: 5, unit_key: "piece", unit_weight_g: 1.4, unit_source: "usda", size: "" }), 7);
  assertEquals(totalGrams({ count: 3, unit_key: "piece", unit_weight_g: 1.4, unit_source: "usda", size: "" }), 4.2);
  assertEquals(totalGrams({ count: 2, unit_key: "tbsp", unit_weight_g: 13.5, unit_source: "usda", size: "" }), 27);
});
