#!/usr/bin/env bash
# Baut die PWA und veroeffentlicht sie auf GitHub Pages (kostenlose iOS-Distribution, siehe
# ClaudeBrain 02 Projekte/Einkaufstracker/14 iOS-Strategie und Kosten.md, Option D).
#
# Das GitHub-Pages-Ziel ist ein SEPARATES OEFFENTLICHES Repo (wie bei der Datenschutzerklaerung),
# weil GitHub Pages fuer private Repos ein bezahltes GitHub-Pro-Konto braucht. Der App-Quellcode
# bleibt im privaten Haupt-Repo, hier landet nur das fertig kompilierte, ohnehin oeffentlich
# ausgelieferte Web-Bundle (der Supabase-Anon-Key darin ist bewusst oeffentlich, siehe Doku 09 §2).
#
# Einmalig vorher: gh repo create einkaufstracker-web --public
#                  (und in der Play/GitHub-Console GitHub Pages dafuer aktivieren, siehe Skript unten)
#
# Nutzung: tools/deploy_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DEPLOY_REPO="JaSigmund/einkaufstracker-web"
DEPLOY_DIR="$(mktemp -d)"

echo "Baue Web-App..."
# --base-href: GitHub Pages liefert unter einem Unterpfad aus (github.io/<repo>/), nicht unter "/".
# MSYS2_ARG_CONV_EXCL verhindert, dass Git-Bash den Pfad faelschlich in einen Windows-Pfad umwandelt.
(cd app && MSYS2_ARG_CONV_EXCL="*" "/c/Users/jakob/dev/flutter/bin/flutter.bat" build web --release --dart-define-from-file=dart_defines.local.json --base-href "/einkaufstracker-web/")

echo "Klone Ziel-Repo ($DEPLOY_REPO)..."
gh repo clone "$DEPLOY_REPO" "$DEPLOY_DIR" -- -q 2>/dev/null || git clone "https://github.com/$DEPLOY_REPO.git" "$DEPLOY_DIR" -q

echo "Kopiere Build-Ausgabe..."
find "$DEPLOY_DIR" -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +
cp -r app/build/web/. "$DEPLOY_DIR/"
# Ohne .nojekyll verarbeitet GitHub Pages den Inhalt mit Jekyll und liefert eine Jekyll-Seite statt
# unserer index.html aus (live so erlebt beim ersten Deploy, 2026-09-30).
touch "$DEPLOY_DIR/.nojekyll"

cd "$DEPLOY_DIR"
git add -A
if git diff --cached --quiet; then
  echo "Keine Aenderungen, nichts zu veroeffentlichen."
  exit 0
fi
git commit -q -m "Deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -q

echo ""
echo "Fertig. Live in 1-2 Minuten unter der GitHub-Pages-URL des Repos."
