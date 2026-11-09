#!/usr/bin/env bash
# Rebuilds assets/fonts/noto_color_emoji/NotoColorEmoji-Subset.ttf: Noto Color
# Emoji cut down to the emoji written in lib/, so the web build bundles them
# instead of fetching the whole font from Google when one first appears.
# Run it after adding an emoji to the code; test/design checks the coverage.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=assets/fonts/noto_color_emoji/NotoColorEmoji-Subset.ttf
work=$(mktemp -d)

# The emoji in the code, as U+XXXX, with the joiner and the emoji selector.
unicodes=$(python3 - <<'PY'
import pathlib
points = {0x200D, 0xFE0F}
for p in pathlib.Path('lib').rglob('*.dart'):
    for line in p.read_text(encoding='utf-8').splitlines():
        if line.lstrip().startswith('//'):
            continue
        for ch in line:
            o = ord(ch)
            if 0x1F000 <= o <= 0x1FAFF or 0x2300 <= o <= 0x23FF or 0x2600 <= o <= 0x27BF or 0x2B00 <= o <= 0x2BFF:
                points.add(o)
print(','.join('U+%04X' % o for o in sorted(points)))
PY
)
echo "emoji: $unicodes"

# The same file the web engine would otherwise fetch at runtime.
url=$(curl -sS -A curl "https://fonts.googleapis.com/css2?family=Noto+Color+Emoji" \
  | grep -oE 'https://fonts.gstatic.com/[^)]+' | head -1)
curl -sSL -o "$work/full.ttf" "$url"

uvx --from fonttools pyftsubset "$work/full.ttf" --unicodes="$unicodes" \
  --output-file="$out" --layout-features='*' --drop-tables+=SVG \
  --no-hinting --notdef-outline

# Noto maps no glyph to the emoji selector (U+FE0F); the web engine still
# wants it covered, so it gets the joiner's empty glyph.
uv run --with fonttools python - "$out" <<'PY'
import sys
from fontTools.ttLib import TTFont
font = TTFont(sys.argv[1])
empty = font.getBestCmap()[0x200D]
for table in font['cmap'].tables:
    if 0x200D in table.cmap:
        table.cmap[0xFE0F] = empty
font.save(sys.argv[1])
print('mapped', len(font.getBestCmap()), 'code points ->', sys.argv[1])
PY
rm -rf "$work"
