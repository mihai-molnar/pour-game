# Pour prototype (spike — throwaway)

Answers two questions before designing the real game: does the pour *feel* good, and does the liquid *look* good as pixel art at 640×360?

## Controls

- **Hold ↓** — tilt the pitcher. It swings fast until the water reaches the lip, then slowly while pouring.
- **Release** — it eases back upright; liquid already in the air (and a little more from the lip) still lands.
- **Space** — serve. Waits for the stream to finish, scores the glass, slides in a new one with a new gold fill line.
- **F1** debug readout · **R** reset coins · **Esc** quit

Scoring: within ±3% of the line = PERFECT (10), within ±10% = GOOD (8→2), else MISS; overflowing = SPILLED.

## Tuning live

Run from the editor (F5), then in the Scene dock switch to **Remote**, select `Pitcher` / `Glass` / `Stream` and edit the exported values in the Inspector — changes apply immediately. The liquid look lives in each vessel's `Liquid` node material (tint, refraction, lens, dither).

Key knobs: `Pitcher.tilt_speed_deg`, `pour_tilt_speed_deg`, `return_force` (lower = more momentum), `pour_rate`, `start_fill`; `Glass.perfect_tol`, `good_tol`, `target_min/max`; `Stream.gravity`.

## How it works

- `pitcher.gd` — tilt dynamics; pouring is geometric (whatever no longer fits below the line through the spout lip leaves), with a slosh term.
- `stream.gd` — one ballistic parcel per tick of pouring; drawn as a joined stream or drops; splashes.
- `glass.gd` — rasterized interior (exact volume→level), 1D spring surface waves, bubbles, scoring.
- `liquid.gdshader` — screen-space refraction (lens + wobble, whole-pixel offsets), thickness tint, ordered dithering, highlight stripe.
- `main.gd` — input, serving, HUD; dev flags: `-- --sweep` (headless tuning table), `-- --hold=S --shots=PREFIX --quit=S` (autopilot screenshots).
- `tools/make_background.py` — regenerates `art/background.png`.

Godot: `"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .`
