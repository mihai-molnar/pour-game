#!/bin/bash
# Renders tools/background/bar.html to art/background.png (2800x1610: the
# world rect main.gd's BACKGROUND_RECT names, at 7 image px per world px).
# Needs Google Chrome; it loads the page headless with ?export, which writes
# the canvas as a PNG data URL into the DOM, and decodes that.
#
# Run from anywhere:  tools/make_background.sh
# Then re-import in Godot (or: "$GODOT" --headless --path . --import).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
	echo "Google Chrome not found at $CHROME (set CHROME=/path/to/chrome)" >&2
	exit 1
fi

DOM="$(mktemp)"
trap 'rm -f "$DOM"' EXIT
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 --dump-dom \
	"file://$ROOT/tools/background/bar.html?export" > "$DOM" 2>/dev/null

python3 - "$DOM" "$ROOT/art/background.png" <<'EOF'
import base64, re, sys
dom = open(sys.argv[1]).read()
m = re.search(r"PNGSTARTdata:image/png;base64,([A-Za-z0-9+/=]+)PNGEND", dom)
if not m:
    sys.exit("bar.html produced no PNG (open it in a browser and check the console)")
png = base64.b64decode(m.group(1))
open(sys.argv[2], "wb").write(png)
w, h = int.from_bytes(png[16:20], "big"), int.from_bytes(png[20:24], "big")
print(f"wrote {sys.argv[2]} ({w}x{h}, {len(png) // 1024} KB)")
EOF
