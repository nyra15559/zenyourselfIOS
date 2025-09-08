#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
LIB="$ROOT/lib"

latest_report="$(ls -td "$ROOT"/reports/gedankenbuch_audit_* | head -1)"
plan="$latest_report/migration_plan_dry_run.txt"

if [ ! -f "$plan" ]; then
  echo "❌ Kein Migrationsplan gefunden: $plan"
  exit 1
fi

echo "📄 Gefundener Plan: $plan"
echo "--------------------------------------"
sed -n '1,200p' "$plan"
echo "--------------------------------------"
read -rp "⚠️  Plan anwenden? (yes/NO): " ans
if [ "$ans" != "yes" ]; then
  echo "Abgebrochen."
  exit 0
fi

# Git-Schutz
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add -A
  git commit -m "chore: pre-migration snapshot (Gedankenbuch→Legacy)" || true
  branch="feat/gb-journal-migration-$(date +%F-%H%M)"
  git checkout -b "$branch"
  echo "🌿 Neuer Branch: $branch"
fi

# Verzeichnisse anlegen (aus Plan lesen)
grep -E '^mkdir -p ' "$plan" | bash

# Moves ausführen
grep -E '^mv ' "$plan" | while read -r cmd rest; do
  echo "▶️  $cmd $rest"
  $cmd $rest || true
done

# Imports anpassen (nur Pfade, keine Symbole)
#   features/gedankenbuch/ → features/_legacy_gedankenbuch/
#   models/gedankenbuch_entry.dart → models/_legacy/gedankenbuch_entry.dart
echo "🛠  Imports umschreiben…"
grep -rilE 'features/gedankenbuch/|models/gedankenbuch_entry\.dart' "$LIB" | while read -r f; do
  sed -i \
    -e 's#features/gedankenbuch/#features/_legacy_gedankenbuch/#g' \
    -e 's#models/gedankenbuch_entry\.dart#models/_legacy/gedankenbuch_entry.dart#g' \
    "$f"
done

# Aufräumen & Hinweise
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add -A
  git commit -m "refactor: move old Gedankenbuch to _legacy + fix import paths"
fi

echo "✅ Migration angewendet."
echo "Nächste Schritte:"
echo "1) flutter analyze"
echo "2) flutter test   (falls Tests vorhanden)"
echo "3) flutter run    (Smoke-Test, Journal/Timeline öffnen)"
