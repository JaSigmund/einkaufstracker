// Entscheidung, was beim Loeschen eines Kontos mit seinen Haushalten passiert.
//
// Eigenes Modul ohne Netz- und Datenbankzugriff, damit es mit `deno test` pruefbar ist (plan_test.ts).
// Codereview-Fund 2026-10-16: Die Mitgliederzahl wurde ohne Fehlerpruefung gelesen (`count ?? 0`). Schlug die Zaehlung
// fehl, galt der Nutzer als einziges Mitglied, und der GANZE Haushalt wurde geloescht -- samt der Daten aller anderen
// Mitglieder. Eine unbekannte Mitgliederzahl ist jetzt ein Abbruch, bevor irgendetwas geloescht wird.

export type Membership = { household_id: string; members: number | null };
export type DeletionPlan =
  | { ok: true; deleteHouseholds: string[]; leaveHouseholds: string[] }
  | { ok: false; error: "lookup_failed" };

export function planDeletion(memberships: Membership[]): DeletionPlan {
  const deleteHouseholds: string[] = [];
  const leaveHouseholds: string[] = [];
  for (const m of memberships) {
    if (m.members === null || !Number.isInteger(m.members) || m.members < 1) return { ok: false, error: "lookup_failed" };
    if (m.members === 1) {
      deleteHouseholds.push(m.household_id);
    } else {
      leaveHouseholds.push(m.household_id);
    }
  }
  return { ok: true, deleteHouseholds, leaveHouseholds };
}
