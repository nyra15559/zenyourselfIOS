#!/usr/bin/env bash
set -euo pipefail

# --- Pfade ermitteln ----------------------------------------------------------
ROOT="$(pwd)"
[[ -f "$ROOT/pubspec.yaml" ]] || { echo "Bitte im Projektroot mit pubspec.yaml ausführen."; exit 1; }

LIB="$ROOT/lib"
GED="$LIB/features/gedankenbuch"
JOUR="$LIB/features/journal"

[[ -d "$GED" ]] || { echo "Ordner fehlt: $GED"; exit 1; }
[[ -d "$JOUR" ]] || { echo "Ordner fehlt: $JOUR"; exit 1; }

# --- Backup -------------------------------------------------------------------
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP="$ROOT/_migration_backups/gedankenbuch_$STAMP"
mkdir -p "$BACKUP"
cp -a "$GED" "$BACKUP/"
echo "🧯 Backup erstellt: $BACKUP"

# --- Mapping: alte → neue Dateien --------------------------------------------
# (Nur die Journal-bezogenen Sachen. Andere Dateien wie emotion_detection/live_waveform bleiben unberührt.)
declare -A MAP=(
  ["gedankenbuch_entry_card.dart"]="journal_entry_card.dart"
  ["gedankenbuch_entry_screen.dart"]="journal_day_screen.dart"
  ["gedankenbuch_timeline.dart"]="journal_screen.dart"
  ["journal_entry_card.dart"]="journal_entry_card.dart"     # Duplikat
  ["journal_entry_view.dart"]="journal_entry_view.dart"     # Duplikat
)

write_stub () {
  local src="$1" tgt="$2"
  cat > "$GED/$src" <<EOF
// GENERATED (V8 migration): legacy re-export to keep old imports working.
// Remove after all imports were switched to features/journal/* .
export '../journal/$tgt';
EOF
  echo "↪  Stub geschrieben: gedankenbuch/$src  →  journal/$tgt"
}

for src in "${!MAP[@]}"; do
  tgt="${MAP[$src]}"
  if [[ -f "$GED/$src" ]]; then
    if [[ -f "$JOUR/$tgt" ]]; then
      # Journal-Version schon vorhanden → im alten Ort nur Re-Export stub lassen
      write_stub "$src" "$tgt"
    else
      echo "→ Verschiebe $src  →  $tgt"
      mv "$GED/$src" "$JOUR/$tgt"
    fi
  fi
done

# --- _legacy_exports.dart Aggregator anlegen ----------------------------------
LEGACY="$GED/_legacy_exports.dart"
{
  echo "// lib/features/gedankenbuch/_legacy_exports.dart"
  echo "// Temporäre Re-Exports für die Migration V8. Nach Umstellung entfernen."
  echo "export '../journal/journal_entry_card.dart';"
  echo "export '../journal/journal_entry_view.dart';"
  echo "export '../journal/journal_screen.dart';"
  [[ -f "$JOUR/journal_entry_editor.dart" ]] && echo "export '../journal/journal_entry_editor.dart';"
  [[ -f "$JOUR/entry_editor.dart" ]] && echo "export '../journal/entry_editor.dart';"
} > "$LEGACY"
echo "📦 $LEGACY geschrieben."

# --- Import-Pfade global umschreiben ------------------------------------------
echo "🔧 Ersetze Importpfade → features/journal/*"
# sed -i (GNU) vs sed -i '' (BSD/macOS)
if sed --version >/dev/null 2>&1; then
  SED_I=(-i)
else
  SED_I=(-i '')
fi

# Ordnerpfad ersetzen
find "$LIB" -name '*.dart' -type f -print0 \
 | xargs -0 sed "${SED_I[@]}" -E 's#(import\s+[\'"][^\'"]*)features/gedankenbuch/#\1features/journal/#g'

# Dateinamen, die umbenannt wurden, nachziehen
declare -A NAME_RENAMES=(
  ["gedankenbuch_entry_card.dart"]="journal_entry_card.dart"
  ["gedankenbuch_entry_screen.dart"]="journal_day_screen.dart"
  ["gedankenbuch_timeline.dart"]="journal_screen.dart"
)
for from in "${!NAME_RENAMES[@]}"; do
  to="${NAME_RENAMES[$from]}"
  find "$LIB" -name '*.dart' -type f -print0 \
   | xargs -0 sed "${SED_I[@]}" -E "s#(features/journal/)${from}#\1${to}#g"
done

# --- Format / Abschluss -------------------------------------------------------
( cd "$ROOT" && dart format lib >/dev/null || true )

echo "✅ Migration abgeschlossen."
echo "• Backup: $BACKUP"
echo "• Temporäre Stubs unter: lib/features/gedankenbuch/*.dart (nur Re-Exports)"
echo "• Bitte CI laufen lassen. Danach kannst du den Ordner gedankenbuch/ komplett entfernen."
