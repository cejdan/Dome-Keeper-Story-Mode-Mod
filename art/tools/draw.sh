#!/usr/bin/env bash
# Draw one sprite with LibreSprite in batch mode (no UI).
# Usage: art/tools/draw.sh <script-name-without-.js> <template-size>
#   e.g. art/tools/draw.sh gold_drop 8
# Writes art/src/<name>.ase (editable) and art/export/real/<name>.png (real colors).
# Templates are named canvas_<size>px.png: LibreSprite opens files whose names end in a
# number as an animation sequence (blank8.png + blank9.png = 2 frames), so never end them in a digit.
set -euo pipefail
ART="$(cd "$(dirname "$0")/.." && pwd)"
LS="$ART/../../tools/libresprite/libresprite.exe"
name="$1"; size="$2"
tmp="$ART/.build"; mkdir -p "$tmp"
outdir="$(cygpath -m "$ART" 2>/dev/null || echo "$ART")"
minerals="{}"; [ -f "$ART/palette/mineral_cells.json" ] && minerals="$(cat "$ART/palette/mineral_cells.json")"
{ echo "var OUTDIR = \"$outdir\";"; echo "var MINERALS = $minerals;"; cat "$ART/scripts/lib.js" "$ART/scripts/shapes.js" "$ART/scripts/$name.js"; } > "$tmp/$name.js"
"$LS" -b "$(cygpath -m "$ART/templates/canvas_${size}px.png")" --script "$(cygpath -m "$tmp/$name.js")" 2>&1 \
  | grep -vE '^(Loading file|Using loader|Reading file|Invalid default)' || true
rm -f "$tmp/$name.js"
