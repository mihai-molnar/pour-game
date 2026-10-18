#!/bin/bash
# Renders the painted backgrounds through headless Chrome:
#   bar  -> art/background.png       (tools/background/bar.html; 2660x1540: the
#           world rect main.gd's BACKGROUND_RECT names, at 7 image px per world px)
#   shop -> art/shop_background.png  (tools/background/shop.html; 2560x1440: the
#           whole 640x360 HUD screen at 4 image px per unit)
# Needs Google Chrome; it loads each page headless with ?export, which writes
# the canvas as a PNG data URL into the DOM, and decodes that.
#
# Run from anywhere:  tools/make_background.sh [bar] [shop]   (no argument = both)
# Then re-import in Godot (or: "$GODOT" --headless --path . --import).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
	echo "Google Chrome not found at $CHROME (set CHROME=/path/to/chrome)" >&2
	exit 1
fi

render() {  # render <page name> <output png>
	local dom
	dom="$(mktemp)"
	"$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 --dump-dom \
		"file://$ROOT/tools/background/$1.html?export" > "$dom" 2>/dev/null
	python3 - "$dom" "$2" "$1" <<'EOF'
import base64, re, sys
dom = open(sys.argv[1]).read()
m = re.search(r"PNGSTARTdata:image/png;base64,([A-Za-z0-9+/=]+)PNGEND", dom)
if not m:
    sys.exit(f"{sys.argv[3]}.html produced no PNG (open it in a browser and check the console)")
png = base64.b64decode(m.group(1))
open(sys.argv[2], "wb").write(png)
w, h = int.from_bytes(png[16:20], "big"), int.from_bytes(png[20:24], "big")
print(f"wrote {sys.argv[2]} ({w}x{h}, {len(png) // 1024} KB)")
EOF
	rm -f "$dom"
}

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(bar shop)
for t in "${targets[@]}"; do
	case "$t" in
		bar) render bar "$ROOT/art/background.png" ;;
		shop) render shop "$ROOT/art/shop_background.png" ;;
		*) echo "unknown target $t (bar, shop)" >&2; exit 1 ;;
	esac
done
