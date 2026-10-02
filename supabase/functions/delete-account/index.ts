// Edge Function: delete-account
//
// Loescht das Konto des aufrufenden Nutzers unwiderruflich (Play-Store-Pflicht "Account Deletion",
// siehe Datenschutzerklaerung: "Konto samt aller Daten loeschen").
//
// Ablauf: JWT pruefen -> Haushalte des Nutzers ermitteln -> ist er das einzige Mitglied eines
// Haushalts, wird der ganze Haushalt geloescht (cascade loescht Bons, Inventar, Kategorien etc.,
// siehe Migration 0001) und dessen Dateien in den Storage-Buckets "receipts" (Bon-Fotos, PDFs) und
// "meals" (Essensfotos, Phase 7) entfernt; ist er nicht
// alleiniges Mitglied, wird nur seine Mitgliedschaft entfernt, die Haushaltsdaten bleiben fuer die
// anderen Mitglieder bestehen. Zuletzt wird der Auth-Nutzer selbst geloescht.
//
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Nur der Storage-Bucket wird gebraucht -- als Parameter statt des ganzen Clients, weil der Typ des Clients von den
// Datenbank-Generics abhaengt und `deno check` den Client aus createClient() sonst nicht als Parameter akzeptiert.
type StorageBucket = ReturnType<ReturnType<typeof createClient>["storage"]["from"]>;

// Eine Seite der Storage-Auflistung. Mehr als diese Anzahl Eintraege je Ordner kommen nur ueber weitere Seiten.
const PAGE = 1000;

/// Alle Eintraege eines Ordners, seitenweise (die Auflistung liefert hoechstens PAGE je Aufruf).
async function listAll(bucket: StorageBucket, folder: string): Promise<{ name: string }[]> {
  const all: { name: string }[] = [];
  for (let offset = 0;; offset += PAGE) {
    const { data, error } = await bucket.list(folder, { limit: PAGE, offset });
    if (error || !data) break;
    all.push(...data);
    if (data.length < PAGE) break;
  }
  return all;
}

async function removeInChunks(bucket: StorageBucket, paths: string[]) {
  for (let i = 0; i < paths.length; i += PAGE) await bucket.remove(paths.slice(i, i + PAGE));
}

/// Bon-Dateien liegen als {haushalt}/{bon}/{datei}, also eine Ordnerebene tiefer.
async function purgeReceiptFiles(bucket: StorageBucket, householdId: string) {
  const paths: string[] = [];
  for (const folder of await listAll(bucket, householdId)) {
    for (const f of await listAll(bucket, `${householdId}/${folder.name}`)) paths.push(`${householdId}/${folder.name}/${f.name}`);
  }
  await removeInChunks(bucket, paths);
}

/// Essensfotos liegen flach als {haushalt}/{mahlzeit}.jpg (Phase 7b, MealPhotoService).
async function purgeMealPhotos(bucket: StorageBucket, householdId: string) {
  const files = await listAll(bucket, householdId);
  await removeInChunks(bucket, files.map((f) => `${householdId}/${f.name}`));
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
      await purgeReceiptFiles(admin.storage.from("receipts"), household_id);
      await purgeMealPhotos(admin.storage.from("meals"), household_id);
      await admin.from("households").delete().eq("id", household_id); // cascade: alle Fachdaten
    } else {
      await admin.from("household_members").delete().eq("household_id", household_id).eq("user_id", userId);
    }
  }

  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) return json({ error: "user_delete_failed", message: delErr.message }, 500);

  return json({ deleted: true });
});
