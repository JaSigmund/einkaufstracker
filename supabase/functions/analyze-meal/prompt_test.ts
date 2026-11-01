// Tests fuer prompt.ts. Lokal und in der CI: `deno test`
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildUserText, TOOL } from "./prompt.ts";
import { EMPTY_CONTEXT } from "./sanitize.ts";

Deno.test("buildUserText: ohne Angaben nur die Produkte, wie bisher", () => {
  assertEquals(buildUserText(EMPTY_CONTEXT, []), "Produkte im Vorrat des Haushalts:\n(keine Produkte im Vorrat)\n\nRufe submit_meal auf.");
});

Deno.test("buildUserText: alle Angaben des Nutzers stehen vor den Produkten", () => {
  const text = buildUserText(
    { title: "Pizzabrötchen", note: "mit Sauerrahm", meal_type: "dinner", servings_made: 4, known_ingredients: ["Paprika", "Hüttenbrot"] },
    [{ id: "p1", name: "Reis" }],
  );
  assertStringIncludes(text, "Titel: Pizzabrötchen");
  assertStringIncludes(text, "Notiz: mit Sauerrahm");
  assertStringIncludes(text, "Mahlzeit: dinner");
  assertStringIncludes(text, "Portionen gekocht: 4");
  assertStringIncludes(text, "Schon eingetragene Zutaten: Paprika, Hüttenbrot");
  assertStringIncludes(text, "- p1: Reis");
  assertEquals(text.indexOf("Angaben des Nutzers") < text.indexOf("Produkte im Vorrat"), true);
});

Deno.test("TOOL: strenges Schema verlangt jedes Feld, sonst lehnt die API es ab", () => {
  const item = TOOL.input_schema.properties.ingredients.items;
  assertEquals(TOOL.strict, true);
  assertEquals(TOOL.input_schema.additionalProperties, false);
  assertEquals(item.additionalProperties, false);
  assertEquals([...item.required].sort(), Object.keys(item.properties).sort());
  assertEquals([...TOOL.input_schema.required].sort(), Object.keys(TOOL.input_schema.properties).sort());
});
