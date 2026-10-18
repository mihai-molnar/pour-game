# Smooth Art Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pixel-art rendering with a smooth, stylized look (closer camera, evening-bar background, glassware with light, see-through refracting liquid, rounded HUD) without changing any gameplay.

**Architecture:** Rendering switches to `canvas_items` stretch at window resolution with 2D MSAA and a static `Camera2D` (zoom ≈ 1.8) over the unchanged 640×360 world. A new `VesselArt` helper owns the smooth-drawing geometry (rounded copies of the physics polygons, open-top walls, gradient fills, streaks, soft shadows); `glass.gd`, `pourer.gd`, `stream.gd` and `effects.gd` keep their simulation and only replace their `_draw` code. `liquid.gdshader` is rewritten to refract and absorb smoothly; the background becomes a high-resolution PNG generated from an HTML canvas page by headless Chrome.

**Tech Stack:** Godot 4.5.1 (Forward Plus, GDScript, canvas_item shaders), HTML canvas + headless Google Chrome for the background, Fredoka (OFL) font.

**Spec:** `docs/superpowers/specs/2026-10-18-smooth-art-style-design.md` (visual reference: `docs/superpowers/specs/2026-10-18-smooth-art-style-mockup.html`)

## Global Constraints

- Godot 4.5.1 at `"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"` (quote it: the path has a space). Every headless check run keeps `--quit-after N`.
- World units stay 640×360 game pixels: counter top y = 280, every `DrinkDef` shape, speed and volume unchanged; `GLASS_POS` stays (256, 280).
- No gameplay change: `--sweep` and `--sweep=wine` output must be byte-identical to the baselines recorded before the change (`sweep_water_before.txt`, `sweep_wine_before.txt` in the session scratchpad; regenerate from `master` with `git stash`/worktree if lost).
- The sim stays deterministic; randomness only in visuals.
- All checks print their `check_<name>: OK` line (`--check=all`); judge by the OK lines, not the exit code.
- Scene order stays: Background, Glass (Liquid, Front), Stream, Pourer (Liquid, Front), Effects, Hud, RoundSummary.
- Physics polygons are never modified; rounding is a draw-time copy.
- Named colours live in `Palette` (`palette.gd`); new colours are added there. Alpha variants and gradients between them are fine.
- Fonts are OFL and bundled in `fonts/` with their licence.
- New and changed GDScript follows the codebase's style: typed, snake_case, `##` doc comments on classes and public functions, tabs.

## Review Focus

1. **Other window sizes** (1920×1080 fullscreen, 4:3, a Retina Mac at 2560×1600): letterboxed, crisp, and the background must cover the whole camera view with no gaps. Pinned by `check_view` (background covers the view) in Task 1/2; looked at in Task 10's screenshots.
2. **Tiny and huge liquid amounts** (first drops, a near-empty pourer, a brim-full or overflowing glass): every drawn liquid polygon must triangulate (no "triangulation failed" errors) and stay inside the vessel. Pinned in Task 4 (glass) and Task 5 (pourer).
3. **Steep tilts:** the pourer at its common pouring tilts must stay in frame and clear of the HUD. Pinned by `check_view` in Task 1.
4. **Drawn level vs. scored level:** at 1.8× zoom a row is 3–6 screen pixels; the drawn calm surface and fill line must sit exactly where `rows_from_line` measures. Pinned in Task 4.
5. **Arrivals, vanishing and the cork** (lean, puff, corked bottle, flying cork) must still look right with the new drawing. Checked in Task 10's autoplay screenshots at the arrival moments.

---

### Task 1: Smooth rendering, camera, HUD positions from world

**Files:**
- Modify: `project.godot` (display + rendering sections)
- Modify: `main.tscn` (add `Camera2D` node `Camera` after `Background`)
- Modify: `main.gd` (camera constants, `view_rect()`, `world_to_hud()`, popup position)
- Create: `tools/checks/check_view.gd`

**Interfaces:**
- Produces: `Main.CAMERA_CENTER: Vector2`, `Main.CAMERA_ZOOM: float`, `static func Main.view_rect() -> Rect2` (the world rect the camera shows, base 640×360 divided by zoom), `func Main.world_to_hud(p: Vector2) -> Vector2` (world → HUD/viewport base coordinates via `get_viewport().get_canvas_transform()`).

- [ ] **Step 1: Write `check_view.gd`** (`extends CheckBase`, header comment in the style of the other checks). Assertions:

```gdscript
var view := Main.view_rect()
near(view.size.x, 640.0 / Main.CAMERA_ZOOM, "view width follows the zoom", 0.01)
expect(Glass.OFFSCREEN_X + 26.0 < view.position.x, "an arriving glass starts fully left of the view")
expect(Pourer.OFFSCREEN_X - 25.0 > view.end.x, "an arriving pourer starts fully right of the view")
# Every vessel fits at rest and at its common pouring tilts (outer polygon, world space):
#   water glass + wine glass at GLASS_POS; pitcher at tilts 0..85°; bottle at tilts 0..35° past its rest.
# Margin: 2 world px inside the view; the top 22 px (HUD row) may only be entered above tilt 60°.
expect(view.end.y >= 286.0, "the counter's front edge is in view")
var hud := main.world_to_hud(Vector2(256, 206))   # water glass rim
expect(Rect2(0, 0, 640, 360).has_point(hud), "a point on the glass maps onto the screen")
```

(Write the vessel-extent loop with `Transform2D(-deg_to_rad(rest + tilt), lip)` applied to `pourer_outer`, matching `pourer.gd`'s `rotation = -(rest + tilt)`.)

- [ ] **Step 2: Run it, expect FAIL** (`Main.view_rect` doesn't exist).

Run: `"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=view`

- [ ] **Step 3: Rendering settings.** In `project.godot`: `window/stretch/mode="canvas_items"`, `window/stretch/aspect="keep"`, remove `scale_mode="integer"` (fractional), remove both `2d/snap/*` lines, `textures/canvas_textures/default_texture_filter=1` (linear), `anti_aliasing/quality/msaa_2d=2` (4×). Keep viewport 640×360 and the 1280×720 window override.

- [ ] **Step 4: Camera.** `main.gd`: `const CAMERA_CENTER := Vector2(300, 186)`, `const CAMERA_ZOOM := 1.8`, `view_rect()`. `main.tscn`: a `Camera2D` named `Camera` with `position = CAMERA_CENTER` and `zoom = Vector2(1.8, 1.8)` (Main asserts they agree in `_ready` or sets them from the constants). Tune centre/zoom only if Step 1's extents fail.

- [ ] **Step 5: Popups at the glass.** Replace `POPUP_POS` with `world_to_hud(Vector2(GLASS_POS.x, glass rim y − 14))` at serve time (the rim from `glass.rim_y_world()`), so popups stay on the glass under the camera.

- [ ] **Step 6: Run `--check=view` and `--check=all`, expect all OK.** Run the sweep for water and wine and `diff` against the baselines: identical.

- [ ] **Step 7: Look.** `"$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --seed=11 --shots=$SCRATCH/t1 --shot-every=2 --quit=12`; read two PNGs: they must be 1280×720 (not 640×360), smooth, zoomed. (The old art will look soft and wrong — expected until later tasks.)

- [ ] **Step 8: Commit** `feat: smooth canvas_items rendering and a closer camera`.

---

### Task 2: The bar background

**Files:**
- Create: `tools/background/bar.html` (canvas drawing; seeded RNG)
- Create: `tools/make_background.sh` (renders `bar.html` to `art/background.png` with headless Chrome)
- Delete: `tools/make_background.py`
- Replace: `art/background.png` (+ its `.import`: mipmaps on)
- Modify: `main.tscn` (Background sprite placement), `palette.gd` (bar colours)
- Modify: `tools/checks/check_view.gd`

**Interfaces:**
- Consumes: `Main.view_rect()`.
- Produces: `Main.BACKGROUND_RECT: Rect2` — the world rect the image covers — `Rect2(110, 76, 380, 220)`; the image is `380 × PPU` by `220 × PPU` with `PPU = 7` (2660×1540). `bar.html` hard-codes the same three numbers plus `COUNTER_Y = 280` in a commented constants block; `main.tscn`'s sprite: `position = (110, 76)`, `centered = false`, `scale = (1/7, 1/7)`, `texture_filter = linear mipmap`.

- [ ] **Step 1: Extend `check_view`:** the Background sprite's world rect (position, texture size × scale) contains `Main.view_rect()` grown by 1 px, and equals `Main.BACKGROUND_RECT` within 0.5 px. Run: FAIL (old 640×360 sprite).

- [ ] **Step 2: `bar.html`.** Start from the mockup's `drawBg` + `drawCounter` (spec mockup file), redrawn at `PPU` with world-unit coordinates, then make it a bar per the spec's Background section: two or three backlit shelves of varied bottles with labels and glints, dark wood back-bar cabinet / mirror strip, pendant lamp light pools, the neon cocktail sign, a few bokeh lights, the polished counter (top surface band whose front holds y = 280, bright front edge, warm light pool around x ≈ 256–330). Far layers get `ctx.filter = 'blur(…)'` worth about 1–1.5 px at 1280×720 (≈ 2.5–3.5 image px at PPU 7); the counter stays sharp. Behind the play area (x 225–420, y 160–280) keep mid-detail at reduced contrast; a gentle darker band/vignette there is allowed. The page sizes its canvas to the full image and does nothing else.

- [ ] **Step 3: `make_background.sh`.** Usage comment at the top; runs `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=2660,1540 --screenshot=<abs path>/art/background.png file://<abs path>/tools/background/bar.html`; fails loudly if Chrome is missing.

- [ ] **Step 4: Generate, import, place.** Run the script; `"$GODOT" --headless --path . --import`; set `mipmaps/generate=true` in `art/background.png.import`; update the sprite as in Interfaces; add the bar colours used in `bar.html` to `palette.gd` as named constants (e.g. `BAR_WALL`, `BAR_WOOD`, `COUNTER_TOP`, `COUNTER_EDGE`, `NEON_PINK`).

- [ ] **Step 5: Run `--check=view` and `--check=all`: OK.**

- [ ] **Step 6: Look** (shots as in Task 1 Step 7): the counter's top surface lines up with where the glass and pitcher stand; the bar reads as a bar; nothing behind the vessels is brighter than their highlights. Iterate on `bar.html` until it does.

- [ ] **Step 7: Commit** `feat: evening bar background, generated from a canvas page`.

---

### Task 3: VesselArt drawing helpers

**Files:**
- Create: `vessel_art.gd` (`class_name VesselArt`, `extends RefCounted`, static functions only)
- Create: `tools/checks/check_vessel_art.gd`
- Modify: `draw_layer.gd` (remove `draw_outline` and `wall_polygons` once Tasks 4–5 stop using them — in Task 5)

**Interfaces:**
- Produces (all static):
  - `rounded(poly: PackedVector2Array, radius: float, keep_top := false) -> PackedVector2Array` — corners (convex and concave) replaced by arcs of `radius` (clamped to half the shorter adjacent edge), about one point per 15° of turn; `keep_top` leaves vertices within 0.5 px of the polygon's top sharp (a vessel's opening).
  - `walls(outer: PackedVector2Array, interior: PackedVector2Array) -> Array[PackedVector2Array]` — the wall area between them with the top left open: `outer` minus (`interior` merged with a rectangle rising 50 px above the interior's top span). No hole polygons.
  - `draw_hgradient(ci: CanvasItem, poly: PackedVector2Array, x0: float, x1: float, tex: GradientTexture1D) -> void` — fills `poly` with `tex` mapped across x0..x1 (UV.x = (x − x0)/(x1 − x0)) via `draw_polygon(points, [Color.WHITE], uvs, tex)`.
  - `gradient(stops: Array) -> GradientTexture1D` — from `[[offset, Color], …]`, cached by the caller.
  - `inner_streak(interior: PackedVector2Array, y0: float, y1: float, inset: float) -> PackedVector2Array` — points following the interior's left wall `inset` px inside it, one per 1.5 px of y.
  - `draw_soft_ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void` — a radial falloff (a fan of triangles with per-vertex colour: `color` at the centre, transparent at the rim).

- [ ] **Step 1: Write `check_vessel_art.gd`** using the water and wine `DrinkDef` shapes:

```gdscript
var w: DrinkDef = GameState.WATER
var r := VesselArt.rounded(w.glass_outer, 2.0)
near(Pourer.poly_area(r) / Pourer.poly_area(w.glass_outer), 1.0, "rounding keeps the area", 0.02)
expect(r.size() > w.glass_outer.size(), "rounded corners add points")
expect(_within(r, w.glass_outer, 0.01), "a rounded convex shape stays inside the original")
var kept := VesselArt.rounded(w.glass_interior, 2.0, true)
expect(kept.has(Vector2(-19, -74)) and kept.has(Vector2(19, -74)), "keep_top leaves the opening's corners sharp")
for d in [GameState.WATER, GameState.ROUND_UNLOCKS[2]]:
	for pair in [[d.glass_outer, d.glass_interior], [d.pourer_outer, d.pourer_interior]]:
		var walls := VesselArt.walls(pair[0], pair[1])
		var a := 0.0
		for p in walls: a += Pourer.poly_area(p)
		var expected := Pourer.poly_area(pair[0]) - Pourer.poly_area(pair[1])
		expect(a <= expected + 1.0 and a > expected * 0.8, "%s walls: open-top wall area (%.0f of %.0f)" % [d.id, a, expected])
		expect(not _covers(walls, _centroid(pair[1])), "%s walls leave the inside clear" % d.id)
		for p in walls: expect(not Geometry2D.triangulate_polygon(p).is_empty(), "%s wall polygon triangulates" % d.id)
var s := VesselArt.inner_streak(w.glass_interior, -68.0, -12.0, 2.3)
expect(s.size() > 30 and Geometry2D.is_point_in_polygon(s[0], w.glass_interior), "the streak runs inside the left wall")
```

- [ ] **Step 2: Run, expect FAIL** (`VesselArt` missing).
- [ ] **Step 3: Implement `vessel_art.gd`** per Interfaces (`Geometry2D.merge_polygons` / `clip_polygons`; drop clockwise results as holes, as `DrawLayer.wall_polygons` does today).
- [ ] **Step 4: Run `--check=vessel_art`: OK.**
- [ ] **Step 5: Commit** `feat: VesselArt helpers for smooth vessels`.

---

### Task 4: The glass, drawn smooth

**Files:**
- Modify: `glass.gd` (drawing only; the simulation, `level_for`, `rows_from_line`, `band_rows`, wave and bubble logic stay)
- Create: `shadows.gd` (`class_name Shadows`, `extends Node2D`; node `Shadows` between `Background`/`Camera` and `Glass` in `main.tscn`)
- Modify: `tools/checks/check_glass.gd`, `tools/checks/check_bubbles.gd` if it reads removed helpers
- Modify: `palette.gd` (glass colours if new)

**Interfaces:**
- Consumes: `VesselArt.*` (Task 3).
- Produces: `Glass.liquid_polygon() -> PackedVector2Array` (local; the per-column wave surface across column centres down to the interior bottom, intersected with `rounded(interior, r, true)`; empty below 0.5 px²), `Glass.band_edges(rows: int) -> Vector2` (local y top/bottom of "within `rows` rows of the line": `round(target_y) ∓ (rows + 0.5)`, clamped to the interior's top and bottom), `Glass.bracket_x() -> float` (now float: 3 px left of the outer wall's leftmost point across `band_edges(ok_rows)`), `Glass.line_y() -> float` (= `round(target_y)`, where the fill line is drawn). `left_tick()` is removed.

- [ ] **Step 1: Update `check_glass.gd`:** replace the `left_tick` assertions and `_tint_clear` (use `VesselArt.walls`) and add:

```gdscript
eq(glass.line_y(), -68.0, "water: the fill line is drawn on row -68")
eq(glass.band_edges(1), Vector2(-69.5, -66.5), "PERFECT spans ±1.5 rows around the line")
eq(glass.band_edges(3), Vector2(-71.5, -64.5), "GOOD ticks at ±3.5")
eq(glass.band_edges(6), Vector2(-74.0, -61.5), "GOOD ENOUGH reaches the rim and is cut there")
expect(glass.bracket_x() <= glass.outer_x_at(-68.0).x - 2.0, "the bracket clears the wall")
# drawn level == scored level: a calm glass's liquid top sits on level_for(volume)
for vol in [0.6, 3.0, 400.0, glass.target, glass.capacity]:
	glass.reset(); glass.volume = vol; glass.step(1.0 / 60.0)
	var poly := glass.liquid_polygon()
	expect(poly.is_empty() or not Geometry2D.triangulate_polygon(poly).is_empty(), "liquid at %.1f triangulates" % vol)
	if vol >= 3.0:
		near(_top(poly), glass.level_for(vol), "calm liquid top at %.0f is the scored level" % vol, 0.05)
		near(Pourer.poly_area(poly) / vol, 1.0, "drawn liquid area matches the volume at %.0f" % vol, 0.04)
		expect(_bounds(poly).position.y >= -74.0 - 0.01, "liquid never draws above the rim")
```

and the same `line_y`/`band_edges`/`bracket_x` checks for wine (line at `round(wine target_y)`, bracket left of the bowl's bulge).

- [ ] **Step 2: Run `--check=glass`: FAIL.**
- [ ] **Step 3: Implement the drawing** per the spec's Vessels section and the mockup's `drawGlass`/`drawFillLine`:
  - `Shadows` (Main sets `shadows.glass = glass` in `_ready`; redraws every frame): the glass's contact shadow, `draw_soft_ellipse` at its foot, radii ≈ (outer half-width × 1.3, 2.5), none while the glass is hidden. Drawn in world space so it doesn't lean with the arrival lean.
  - `_draw_liquid`: `draw_colored_polygon(liquid_polygon(), Color.WHITE)` (the shader colours it).
  - `_draw_front`: faint back fill of the rounded outer; soft dark outline; walls (`walls()` of the rounded shapes, `draw_hgradient` with the mockup's wall stops); surface line + sheen along the wave (antialiased polylines); bubbles as small circles (fill + ring); drips as small rounded drops; streaks (`inner_streak`, wide + thin); rim light (right-side gradient stroke); rim line + faint rim ellipse; then the fill line and bracket: line centred on `line_y()` from `bracket_x()` to 1.5 px past the right wall, dark outline spanning `band_edges(perfect_rows)`, bracket spine at `bracket_x()` from `band_edges(ok_rows)` top to bottom with end ticks, inner ticks at `band_edges(good_rows)`; all dark-underlaid so they read on the background.
  - Corner radii: water 2.5 outer / 2 inner; wine 5 / 5 (bowl); `keep_top` on the interior.
- [ ] **Step 4: Run `--check=glass` and `--check=all`: OK.**
- [ ] **Step 5: Look** (shots): both glasses read as glass on the bar; the line and bracket read clearly.
- [ ] **Step 6: Commit** `feat: smooth glass drawing`.

---

### Task 5: The pourers, drawn smooth

**Files:**
- Modify: `pourer.gd` (drawing only), `drink_def.gd`, `drinks/wine.tres`, `palette.gd`
- Modify: `draw_layer.gd` (remove `draw_outline`, `wall_polygons`), `tools/checks/check_pourer.gd`

**Interfaces:**
- Consumes: `VesselArt.*`.
- Produces: `DrinkDef.pourer_label: Rect2` and `DrinkDef.pourer_foil: Rect2` (local, upright; zero size = none; wine: label `Rect2(-19, 78, 44, 42)`, foil `Rect2(-3, 4, 12, 17)`); `Pourer.drawn_liquid_polygons() -> Array[PackedVector2Array]` (`liquid_polygons()` each intersected with the rounded interior, slivers < 0.5 px² dropped).

- [ ] **Step 1: Update `check_pourer.gd`:** `_walls_cover_interior` uses `VesselArt.walls`; `_check_drawable_liquid` also runs on `drawn_liquid_polygons()`; add a sweep — for each drink, volumes `[0.6, 5, 50, full × 0.5, full]` × tilts `[0, 20, 45, 80, max_tilt]` — asserting every drawn polygon triangulates and lies inside the interior's bounds (+0.5 px).
- [ ] **Step 2: Run `--check=pourer`: FAIL.**
- [ ] **Step 3: Implement** per the spec and the mockup's `drawPourer`: rounded outline/back fill (pitcher faint blue, bottle `pourer_glass_color` green), liquid via `drawn_liquid_polygons()` (white; the shader colours it), wall gradient (bottle in greens), surface line + sheen along the clipped surface, streaks, rim light, top rim line (pitcher), handle as a thick antialiased glassy polyline with a highlight, bottle label (cream gradient, thin burgundy rules, small emblem), foil (dark-red gradient), lip ring, and the cork while `corked` as a small rounded cork. `Shadows` (Task 4) also gets `pourer` and draws its contact shadow under the pourer's lowest outer point (world space), fading out as that point lifts toward 45 px above the counter.
- [ ] **Step 4: Remove `DrawLayer.draw_outline` and `wall_polygons`; run `--check=all`: OK.**
- [ ] **Step 5: Look** (shots incl. a wine round at ~35 s): pitcher and bottle read as glass, label/foil/cork look right while tilting.
- [ ] **Step 6: Commit** `feat: smooth pourer drawing and contact shadows`.

---

### Task 6: See-through liquid shader

**Files:**
- Modify: `liquid.gdshader` (rewrite), `main.tscn` (material look values), `drink_def.gd`, `drinks/water.tres`, `drinks/wine.tres`, `glass.gd`/`pourer.gd` `setup()` (pass the new per-drink values)

**Interfaces:**
- Produces: `DrinkDef.liquid_absorb: Color` (rgb absorption per world px of view path; water ≈ (0.010, 0.004, 0.002), wine ≈ (0.022, 0.095, 0.085)), `DrinkDef.liquid_scatter: float` (0–1, how much `liquid_color` the liquid adds by itself; water ≈ 0.3, wine ≈ 0.15). Shader uniforms: `screen_tex` (hint_screen_texture, filter_linear), `tint`, `absorb`, `scatter`, `lens_strength`, `wobble_px`, `edge_glow`, plus the existing geometry uniforms `center_x`, `half_width`, `surface_y` (kept; `highlight_x` dropped — the Front layers draw the streak).

- [ ] **Step 1: Rewrite the shader.** Per fragment (local position from `VERTEX`, local x axis in screen px from `CANVAS_MATRIX * MODEL_MATRIX` as today):
  - `rel = (x − center_x) / half_width`, chord `c = sqrt(1 − rel²)`, path `L = 2 · half_width · c` (world px).
  - Refraction: local shift `(center_x − x) · lens_strength · (0.6 + 0.4·rel²) + wobble_px · wobble(y, t)`, converted with the axis vector to a screen offset, no rounding; sample `screen_tex` at `SCREEN_UV + offset · SCREEN_PIXEL_SIZE`.
  - Absorption: `trans = exp(−absorb.rgb · L · mix(1.0, 1.25, depth))` with `depth = clamp((y − surface_y)/70, 0, 1)`; `col = behind · trans + tint.rgb · scatter · (1 − avg(trans))`.
  - Edge: a thin brighter rim where `|rel| > 0.9` scaled by `edge_glow` (light catching the curved wall).
  - No dithering, no `round`/`floor`.
- [ ] **Step 2: Wire it.** Setup passes `tint`, `absorb`, `scatter` from the `DrinkDef`; both materials in `main.tscn` get the look values (`lens_strength` ≈ 0.35 glass / 0.3 pourer, `wobble_px` ≈ 0.6, `edge_glow` ≈ 0.25); add the new fields to both `.tres` files.
- [ ] **Step 3: Verify it compiles and looks right.** Windowed run with shots (headless doesn't compile shaders); grep the run's stderr for `SHADER ERROR`: none. Read shots of water and wine pouring and settled: through water the bar is plainly visible and bent, blue tint, level obvious; through wine the bar shows only faintly near the walls, deep red in the middle. Tune values until both read at a glance.
- [ ] **Step 4: `--check=all` OK; sweeps identical.**
- [ ] **Step 5: Commit** `feat: see-through refracting liquid shader`.

---

### Task 7: Stream and effects, drawn smooth

**Files:**
- Modify: `stream.gd` (drawing; `Parcel.width` becomes `float`, plus `speed0: float` set at spawn), `effects.gd` (drawing), `tools/checks/check_ui.gd` (effects wording only if needed)
- Create: assertions in a new `tools/checks/check_stream.gd`

**Interfaces:**
- Produces: `static func Stream.ribbon(points: PackedVector2Array, widths: PackedFloat32Array) -> PackedVector2Array` — a closed outline (left side forward, right side back, offsets along per-point normals by width/2); `2 × points.size()` points.

- [ ] **Step 1: Write `check_stream.gd`:**

```gdscript
var pts := PackedVector2Array([Vector2(0, 0), Vector2(-2, 10), Vector2(-3, 30)])
var r := Stream.ribbon(pts, PackedFloat32Array([3.0, 2.0, 1.0]))
eq(r.size(), 6, "two points per input point")
near(r[0].distance_to(r[5]), 3.0, "full width at the spout", 0.01)
near(r[2].distance_to(r[3]), 1.0, "tapers to the last width", 0.01)
expect(not Geometry2D.triangulate_polygon(r).is_empty(), "the ribbon triangulates")
```

- [ ] **Step 2: Run: FAIL.** **Step 3: Implement.** Width at spawn from flow as a float (same formula as today, unclamped to ints: `clampf(1.0 + sqrt(flow) / 14.0, 1.0, 4.0)` × 0.9), drawn width `width · sqrt(speed0 / max(speed, speed0))` (thins as it accelerates). Each continuous run (the existing joining rules: consecutive ticks, the landing point, the spout while streaming) becomes one `ribbon` filled with the drink colour at alpha ≈ 0.75 plus a bright core polyline (width × 0.35, `liquid_highlight`); lone drops and splash droplets as `draw_circle` (r ≈ 0.6–0.9). `Effects._draw`: puffs as soft white discs, dust as small sand discs, spray as drink-coloured discs, the cork as a small rounded brown capsule; counts, lifetimes and `MAX_BITS` unchanged.
- [ ] **Step 4: `--check=all` OK; sweeps identical; look at pour shots** (stream attached to the spout, tapering, landing in the liquid).
- [ ] **Step 5: Commit** `feat: smooth stream and effects`.

---

### Task 8: HUD and round summary restyle

**Files:**
- Add: `fonts/Fredoka.ttf`, `fonts/Fredoka-OFL.txt` (from the scratchpad download: google/fonts `ofl/fredoka`); delete `fonts/PressStart2P-*`
- Modify: `hud.gd`, `round_summary.gd`, `main.gd` (`HINT`), `palette.gd`, `tools/checks/check_ui.gd`

**Interfaces:**
- Produces: `Hud.FONT` (a `FontVariation` of Fredoka at weight 600), `Hud.pill_style() -> StyleBoxFlat` (dark translucent, fully rounded, reused by the summary panel with a smaller radius), `coins_label.text` = the number only (a drawn coin icon precedes it), `streak_label` in the same pill after a thin divider.

- [ ] **Step 1: Update `check_ui.gd`:** `coins_label.text` is `"42"`; the multiplier rule becomes `streak_label.position.x >= coins_label.position.x + coins_label.get_minimum_size().x` and moves right when coins go from 42 to 1234 (strictly greater x), and lands back at that position after the shake; popup texts/colours unchanged; summary `body_text()` still contains `GLASSES`, `7`, `PERFECT`, `2`, `x1.7`, `+55`, `120`; banner, debug and effects assertions unchanged (puff count 4–6 stays).
- [ ] **Step 2: Run `--check=ui`: FAIL.**
- [ ] **Step 3: Implement** per the spec's HUD section and the mockup's CSS: font sizes in base units (HUD 12–14, popups 20–24 with a soft dark outline, banners 28–32, summary title 24 / body 13); coin icon a small gold gradient disc drawn by a tiny `Control` in the coins pill; timer pill centred (red in the last 5 s); hint pill bottom-left with `HINT := "HOLD DOWN  pour   ·   SPACE  serve   ·   F1  debug"` (use ↓ only if Fredoka has the glyph); the streak flyer keeps its pop-and-fly; the summary is a rounded dark panel with two right/left-aligned columns (labels / values) — `body_text()` joins them per row.
- [ ] **Step 4: `--check=all` OK. Look** at shots incl. a banner, a popup and the summary (autoplay reaches the summary at ~31 s): crisp at 1280×720.
- [ ] **Step 5: Commit** `feat: rounded HUD and summary in Fredoka`.

---

### Task 9: Counter reflection (optional — drop if it costs real complexity)

**Files:**
- Modify: `shadows.gd` (or a sibling `reflection.gd` under the same parent), `main.tscn`

- [ ] **Step 1:** A node between Background and Glass draws a mirrored, low-alpha (≈ 0.15) copy of the glass's and pourer's Front drawing about y = 280, clipped to the counter's top band (y 280–286) with a parent that draws the band and sets `clip_children = CLIP_CHILDREN_ONLY`; it calls the vessels' existing `_draw_front(ci)` with `draw_set_transform_matrix` set to the mirrored transform, liquid as a flat drink-coloured polygon.
- [ ] **Step 2:** If this needs changes to the vessels' draw functions beyond an optional flag, stop and skip the task (note it in the final report).
- [ ] **Step 3: `--check=all` OK; look; commit** `feat: faint vessel reflections on the counter`.

---

### Task 10: Docs, cleanup, final verification

**Files:**
- Modify: `CLAUDE.md` (Project Overview current state, Commands — `make_background.sh`, `--shots` at window resolution —, Architecture: Rendering, the vessel/stream/effects/HUD/shader descriptions, `VesselArt`, `Shadows`, Visual identity, Gotchas), `README.md` if it mentions the pixel look
- Modify: the spec's Status line

- [ ] **Step 1:** Remove dead pixel-art code (`Hud.CHAR_W`, unused helpers, comments that describe pixel rows as screen pixels).
- [ ] **Step 2: Final verification.** `--check=all` (every OK line), both sweeps `diff`-identical to the baselines, autoplay shots at 1280×720 covering: round 1 pouring water, a serve popup, the summary, round 2 intro banner, a wine pour, a corked bottle arriving; one run at `--resolution 1920x1080` and one at `1024x768` (letterbox) — read them and fix what looks wrong.
- [ ] **Step 3: Commit** `docs: smooth art style in CLAUDE.md`.
- [ ] **Step 4:** Whole-branch review by a fresh reviewer (superpowers:requesting-code-review), fix what it finds, then hand over for the user's playtest (do not merge to `master` without the user).
