#!/usr/bin/env bash
set -euo pipefail

# Usage: bash analyze_gedankenbuch.sh
# Scans lib/ for Gedankenbuch/Journal related files and emits a structured report.

ROOT="${1:-.}"
LIB="$ROOT/lib"
TS="$(date +%F_%H%M%S)"
OUT="reports/gedankenbuch_audit_$TS"
mkdir -p "$OUT"

echo "▶️  Scanning under: $LIB"
echo "📂 Reports will be in: $OUT"
echo

# 1) Alle Treffer (Master-Liste)
grep -rilE 'gedankenbuch|journal|JournalEntry|ReflectionEntry' "$LIB" | sort > "$OUT/all_hits.txt" || true

# 2) Cluster bilden
#    Kern (behalten) – Journal neues System
grep -rilE '^' "$LIB"/features/journal 2>/dev/null | sort > "$OUT/keep_core_journal.txt" || true
{ \
  [ -f "$LIB/models/journal_entry.dart" ] && echo "$LIB/models/journal_entry.dart"; \
  [ -f "$LIB/providers/journal_entries_provider.dart" ] && echo "$LIB/providers/journal_entries_provider.dart"; \
  [ -f "$LIB/features/journal/widgets/journal_entry_card.dart" ] && echo "$LIB/features/journal/widgets/journal_entry_card.dart"; \
} | sort -u >> "$OUT/keep_core_journal.txt"

#    Legacy (ersetzen/migrieren) – altes Gedankenbuch
grep -rilE '^' "$LIB"/features/gedankenbuch 2>/dev/null | sort > "$OUT/legacy_gedankenbuch.txt" || true
[ -f "$LIB/models/gedankenbuch_entry.dart" ] && echo "$LIB/models/gedankenbuch_entry.dart" >> "$OUT/legacy_gedankenbuch.txt" || true
sort -u -o "$OUT/legacy_gedankenbuch.txt" "$OUT/legacy_gedankenbuch.txt"

#    Indirekte Abhängigkeiten / Services
grep -rilE 'persistence_|local_storage|backup_export_service|reflection_repository|guidance_service|analytics' "$LIB" | sort > "$OUT/indirect_services.txt" || true

#    Weitere Feature-Nutzer (Reflection/Story/Mood/Search/Therapist/Journey/Impulse)
grep -rilE '^' "$LIB"/features/reflection "$LIB"/features/story "$LIB"/features/mood "$LIB"/features/search "$LIB"/features/therapist "$LIB"/features/journey "$LIB"/features/impulse 2>/dev/null \
  | sort > "$OUT/consumers_features.txt" || true

# 3) Duplikate (gleicher Basis-Dateiname in verschiedenen Pfaden)
awk -F/ '{print $NF}' "$OUT/all_hits.txt" | sort | uniq -c | awk '$1>1{print $2}' > "$OUT/duplicate_basenames.txt" || true
> "$OUT/duplicate_files_expanded.txt"
if [ -s "$OUT/duplicate_basenames.txt" ]; then
  while read -r base; do
    echo "### $base" >> "$OUT/duplicate_files_expanded.txt"
    grep -F "/$base" "$OUT/all_hits.txt" >> "$OUT/duplicate_files_expanded.txt"
    echo >> "$OUT/duplicate_files_expanded.txt"
  done < "$OUT/duplicate_basenames.txt"
fi

# 4) Fremd-Imports, die noch aufs alte Gedankenbuch zeigen
#    (Zeigt dir, wo du Referenzen migrieren musst)
> "$OUT/cross_references_to_gedankenbuch.txt"
while read -r f; do
  grep -HnE 'gedankenbuch' "$f" || true
done < <(grep -rilE '^' "$LIB" | sort) >> "$OUT/cross_references_to_gedankenbuch.txt" || true

# 5) Dry-Run Migrationsplan (nur Text!)
#    Vorschlag: Legacy → lib/features/_legacy_gedankenbuch/, Model → lib/models/_legacy/
MIG="$OUT/migration_plan_dry_run.txt"
echo "# Dry-Run Migration Plan (nur Vorschläge – prüfe manuell!)" > "$MIG"
echo "# Ziel: Legacy ins _legacy_ verschieben und Journal als Kanon behalten." >> "$MIG"
echo >> "$MIG"

LEGACY_DIR_FEATURES="$LIB/features/_legacy_gedankenbuch"
LEGACY_DIR_MODELS="$LIB/models/_legacy"

echo "mkdir -p \"$LEGACY_DIR_FEATURES\" \"$LEGACY_DIR_MODELS\"" >> "$MIG"

if [ -s "$OUT/legacy_gedankenbuch.txt" ]; then
  while read -r f; do
    if [[ "$f" == *"/features/gedankenbuch/"* ]]; then
      echo "mv \"$f\" \"$LEGACY_DIR_FEATURES/\"" >> "$MIG"
    elif [[ "$f" == *"/models/gedankenbuch_entry.dart" ]]; then
      echo "mv \"$f\" \"$LEGACY_DIR_MODELS/\"" >> "$MIG"
    fi
  done < "$OUT/legacy_gedankenbuch.txt"
fi

# 6) Zusammenfassung
KEEP_CNT=$(wc -l < "$OUT/keep_core_journal.txt" 2>/dev/null || echo 0)
LEG_CNT=$(wc -l < "$OUT/legacy_gedankenbuch.txt" 2>/dev/null || echo 0)
ALL_CNT=$(wc -l < "$OUT/all_hits.txt" 2>/dev/null || echo 0)
DUP_CNT=$(wc -l < "$OUT/duplicate_basenames.txt" 2>/dev/null || echo 0)

cat > "$OUT/SUMMARY.txt" <<EOF
Gedankenbuch/Journal Audit – $TS

Gesamt-Treffer:         $ALL_CNT
Kern (behalten):        $KEEP_CNT   -> keep_core_journal.txt
Legacy (migrieren):     $LEG_CNT    -> legacy_gedankenbuch.txt
Duplikate (Basename):   $DUP_CNT    -> duplicate_basenames.txt / duplicate_files_expanded.txt
Services/Storage:                  -> indirect_services.txt
Feature-Consumer:                   -> consumers_features.txt
Cross-Refs -> Gedankenbuch:        -> cross_references_to_gedankenbuch.txt
Migrationsplan (Dry-Run):          -> migration_plan_dry_run.txt

Nächste Schritte:
1) Prüfe Duplikate und Cross-Refs.
2) Migriere Legacy-Screens schrittweise auf Journal-Widgets.
3) Vereinheitliche Provider (nur providers/journal_entries_provider.dart als Kanon).
4) Erst wenn alles grün: Legacy-Ordner wirklich verschieben/löschen.
EOF

echo "✅ Fertig. Schau dir die Report-Dateien an:"
ls -1 "$OUT"
