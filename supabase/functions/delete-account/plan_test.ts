// Tests fuer plan.ts. Lokal und in der CI: `deno test plan_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import { planDeletion } from "./plan.ts";

Deno.test("planDeletion: einziges Mitglied -> Haushalt loeschen, sonst nur austreten", () => {
  assertEquals(planDeletion([{ household_id: "a", members: 1 }, { household_id: "b", members: 3 }]), {
    ok: true,
    deleteHouseholds: ["a"],
    leaveHouseholds: ["b"],
  });
});

Deno.test("planDeletion: ohne Mitgliedschaft wird nur das Konto geloescht", () => {
  assertEquals(planDeletion([]), { ok: true, deleteHouseholds: [], leaveHouseholds: [] });
});

Deno.test("planDeletion: unbekannte Mitgliederzahl loescht NICHTS (vorher: ganzer gemeinsamer Haushalt weg)", () => {
  assertEquals(planDeletion([{ household_id: "a", members: 1 }, { household_id: "b", members: null }]), {
    ok: false,
    error: "lookup_failed",
  });
});

Deno.test("planDeletion: unplausible Zaehlung (0, negativ, keine ganze Zahl) gilt ebenfalls als unbekannt", () => {
  for (const members of [0, -1, 1.5, Number.NaN]) {
    assertEquals(planDeletion([{ household_id: "a", members }]).ok, false, String(members));
  }
});
