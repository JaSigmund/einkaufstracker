// Gemeinsame Helfer aller Edge Functions (Codereview 2026-10-16, Fund A4: dieselben Zeilen standen in jeder Function).

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
