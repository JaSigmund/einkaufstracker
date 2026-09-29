// Edge Function: delete-account
//
// Loescht das Konto des aufrufenden Nutzers unwiderruflich (Play-Store-Pflicht "Account Deletion",
// siehe Datenschutzerklaerung: "Konto samt aller Daten loeschen").
//
// Ablauf: JWT pruefen -> Haushalte des Nutzers ermitteln -> ist er das einzige Mitglied eines
// Haushalts, wird der ganze Haushalt geloescht (cascade loescht Bons, Inventar, Kategorien etc.,
// siehe Migration 0001) und dessen Bon-Dateien im Storage-Bucket "receipts" entfernt; ist er nicht
// alleiniges Mitglied, wird nur seine Mitgliedschaft entfernt, die Haushaltsdaten bleiben fuer die
// anderen Mitglieder bestehen. Zuletzt wird der Auth-Nutzer selbst geloescht.
//
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function purgeReceiptFiles(admin: ReturnType<typeof createClient>, householdId: string) {
  const bucket = admin.storage.from("receipts");
  const { data: receiptFolders, error } = await bucket.list(householdId, { limit: 1000 });
  if (error || !receiptFolders) return;
  const paths: string[] = [];
  for (const folder of receiptFolders) {
    const { data: files } = await bucket.list(`${householdId}/${folder.name}`, { limit: 1000 });
    for (const f of files ?? []) paths.push(`${householdId}/${folder.name}/${f.name}`);
  }
  if (paths.length > 0) await bucket.remove(paths);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: memberships, error: memErr } = await admin
    .from("household_members")
    .select("household_id")
    .eq("user_id", userId);
  if (memErr) return json({ error: "lookup_failed" }, 500);

  for (const { household_id } of memberships ?? []) {
    const { count } = await admin
      .from("household_members")
      .select("user_id", { count: "exact", head: true })
      .eq("household_id", household_id);

    if ((count ?? 0) <= 1) {
      await purgeReceiptFiles(admin, household_id);
      await admin.from("households").delete().eq("id", household_id); // cascade: alle Fachdaten
    } else {
      await admin.from("household_members").delete().eq("household_id", household_id).eq("user_id", userId);
    }
  }

  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) return json({ error: "user_delete_failed", message: delErr.message }, 500);

  return json({ deleted: true });
});
