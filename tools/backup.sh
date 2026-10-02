#!/usr/bin/env bash
# Sichert Schema und Daten des Supabase-Projekts als SQL-Dump (Doku 09 Sicherheit und Datenschutz §6).
# Ablage lokal unter backups/ (gitignored) -- kein automatischer Cloud-Upload, das entscheidet Jakob selbst.
#
# Nutzung: tools/backup.sh   (aus dem Repo-Root, npx supabase muss verlinkt sein: `npx supabase link`)
set -euo pipefail
cd "$(dirname "$0")/.."

stamp="$(date +%Y-%m-%dT%H-%M-%S)"
mkdir -p backups

echo "Schema-Dump..."
npx supabase db dump --linked -f "backups/schema_${stamp}.sql"

echo "Daten-Dump (COPY-Format, kompakter als INSERTs)..."
npx supabase db dump --linked --data-only --use-copy -f "backups/data_${stamp}.sql"

echo ""
echo "Fertig: backups/schema_${stamp}.sql, backups/data_${stamp}.sql"
echo "Wiederherstellung testen: siehe tools/RESTORE_DRILL.md (manueller Schritt, nicht Teil dieses Skripts)."
