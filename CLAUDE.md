# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A side-view incremental pouring game in Godot 4.5 (Forward Plus), hosted at https://github.com/mihai-molnar/pour-game (branch `master`; the local folder is `pour-prototype/`). Pitcher on the right, glass on the left: hold DOWN to tilt and pour, release and the pitcher swings back upright while liquid already in the air (plus a little from the lip) keeps landing. The goal is to fill the glass to a fill line drawn on it — close to the line pays coins, exact pays the most, overflowing pays nothing.

**Current state: a spike/prototype**, built to answer "does the pour feel good, and does the liquid look good as pixel art?" Playtest verdict: it felt good. It has one water pitcher + one tumbler, serve/score/next-glass, and a coin counter — no rounds, no shop, no other drinks. The planned full game (not designed yet — the next step is a spec): ~30 s rounds, several glass/container pairs (water→pitcher, beer→bottle, wine glass→wine bottle, …), and a between-rounds upgrade shop (coin gain, pour speed, wider tolerance margins). Treat prototype code as a reference for the real design, not as a fixed architecture.

## Commands

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"   # Godot 4.5.1; quote it — the path has a space

"$GODOT" --path .                                   # play
"$GODOT" --headless --path . --import               # import assets / rebuild the class_name cache
"$GODOT" --headless --path . -- --sweep             # tuning table: hold length → fill %, overshoot after release, settle time, spill
"$GODOT" --headless --path . --quit-after 600 --script res://tools/check_bubbles.gd   # regression check, exits 1 on failure
"$GODOT" --path . --windowed --resolution 1280x720 -- --hold=2.6 --shots=/abs/prefix --quit=6.6   # autopilot pour + screenshots
python3 tools/make_background.py                    # regenerate art/background.png (needs Pillow)
```

- There is no test framework; the headless `--sweep`, the `tools/check_*.gd` scripts, and autopilot screenshots are the verification tools.
- Screenshot mode opens a real window and saves native 640×360 PNGs at `SHOT_TIMES` (in `main.gd`) as `<prefix>_<n>.png`; autopilot holds DOWN from 0.6 s for `--hold` seconds and serves 0.8 s after release.
- New check scripts: `extends SceneTree`, instantiate `res://main.tscn` in `_initialize`, but run the test from the first `_process` — `@onready` references aren't set yet during `_initialize`. Always pass `--quit-after N`: a script error leaves headless Godot running forever (macOS has no `timeout`).
- "Could not find type"/"Identifier not declared" for class_names that exist means a stale `.godot` class cache (scripts added outside the editor): run `--import` first.
- Live tuning: run from the editor (F5), switch the Scene dock to **Remote**, select `Pitcher`/`Glass`/`Stream` and edit the exported values; the liquid look is on each vessel's `Liquid` node `ShaderMaterial`.

## Architecture

**Rendering.** 640×360 viewport, `stretch/mode="viewport"` (not `canvas_items`) with integer scaling, nearest filtering, and 2D transform + vertex snapping — so everything, including rotated shapes, shaders and fonts, rasterizes at native pixel resolution. All coordinates, speeds and sizes are in 640×360 pixels; the counter top is y=280. The pitcher and glass are drawn procedurally in `_draw` (not sprites) so the rotating pitcher stays crisp; their drawing and their physics share the same polygons (`interior`/`outer` arrays), so keep them in sync when changing a vessel's shape.

**Units.** Liquid volume is area in px², shared by pitcher and glass. Gameplay truth is these numbers; waves, splashes, bubbles and the stream's look are visual only.

**Simulation loop.** Vessels don't run their own physics; `main._step_sim(dt, hold)` drives one fixed 60 Hz tick in a fixed order: `pitcher.step()` returns the volume that left the spout → `stream.emit(spout, exit_velocity, vol, dt)` → `stream.step(dt, glass)` → `glass.step(dt)`. The sweep and check scripts call the same function in tight loops, so the sim must stay deterministic in gameplay terms (randomness only for visuals and the per-glass target).

- `pitcher.gd` — node origin = spout lip = rotation pivot; `rotation = -tilt`. Holding approaches `tilt_speed_deg` until liquid reaches the lip, then the slower `pour_tilt_speed_deg` (careful hands); releasing applies a constant `return_force` plus damping (momentum carries it a little further, then it eases back; small bounce at rest). Pouring is geometric: `excess = volume − area(interior ∩ half-plane below the line through the lip at local angle tilt + slosh)`; that excess drains at `pour_rate` with exit speed growing with √excess. The slosh angle is driven by tilt acceleration (braking surges liquid toward the spout). The drawn surface comes from a binary search for the line offset that holds the current volume.
- `stream.gd` — one ballistic `Parcel` per pouring tick. Crossing the rim decides inside (clamped to the opening, lands on `glass.surface_y_world_at` → `glass.receive`) vs missed (falls to `table_y`, counted as spilled). Below `drip_flow` volume accumulates into discrete drops. Drawing joins parcels emitted on consecutive ticks, and joins the spout only while flow is continuous.
- `glass.gd` — the interior polygon is rasterized once into per-column spans and per-row pixel areas, so `level_for(volume)` matches the drawn pixels exactly and capacity = interior pixel count. Liquid is drawn as 1-px column rects (no polygon triangulation). The surface is a 1D wave equation per column, excited by impacts and by the glass's horizontal acceleration (slide in/out). Bubbles must stay within the column spans (`_inside`). `evaluate()` returns `{band, coins, error}`; each `reset()` picks a random target between `target_min`/`target_max` of capacity.
- `liquid.gdshader` — on each vessel's `Liquid` `DrawLayer`. Samples `hint_screen_texture` with a lens + wobble offset rounded to whole pixels along the vessel's local x axis (the `axis_x` varying handles rotation), tints by view-path thickness, and uses ordered (Bayer) dithering. Vessel scripts set the geometry uniforms (`center_x`, `half_width`, `surface_y`, `highlight_x`); the look uniforms live in the materials in `main.tscn`. Godot copies the screen texture once, at the first item that reads it, so liquids only refract what was drawn before them (the background).
- `draw_layer.gd` — forwards `_draw` to a callable so a vessel draws its shaded `Liquid` layer and its `Front` layer (glass walls, meniscus, fill line, bubbles) separately. Scene order: Background, Glass (Liquid, Front), Stream, Pitcher (Liquid, Front) — the stream draws before the pitcher so it appears from behind the spout.
- `main.gd` — input (physical DOWN/Space/F1/R/Esc), HUD built in code (Press Start 2P 8 px theme), and serving: Space queues a serve that fires once `!pitcher.is_pouring()` and `stream.is_empty()`, so in-flight liquid always counts; the glass slides out, resets offscreen, the pitcher refills (`refill_on_serve`), the glass slides back. Also parses the dev flags (`--sweep`, `--hold`, `--shots`, `--quit`).

**Current tuning baseline** (from `--sweep`, before playtest tweaks): pouring starts ~0.5 s into a hold; 55–85 % targets are reached with ~2.2–2.9 s holds; a steady ~11–14 % of glass capacity lands after release — that's the overshoot the player learns to anticipate. PERFECT (±3 %) is about ±1.5 pixel rows on this glass, so tolerances are effectively set in pixels.

## Visual identity

- Colors are an ENDESGA 32 subset defined in `palette.gd` (`class_name Palette`); reference `Palette.*` rather than color literals (alpha variants are fine). `tools/make_background.py` uses the same hex values; `.tscn` shader params repeat them verbatim.
- Font: Press Start 2P (`fonts/`, SIL OFL), antialiasing off, sizes in multiples of 8.

## Gotchas

- GDScript `const` can't hold `PackedVector2Array(...)` (not a constant expression) — vessel shapes are member `var`s.
- `Geometry2D.clip_polyline_with_polygon` returns the part *outside* the polygon; use `intersect_polyline_with_polygon` for the inside.
- `.godot/` is editor cache — never edit or commit it. Commit Godot's `.uid` sidecars; `main.tscn` will gain `uid=` attributes on first editor save — commit that rewrite too.

## Conventions

- GDScript; snake_case for files, functions and variables; PascalCase for node and class names.
- Design specs go in `docs/superpowers/specs/`, implementation plans in `docs/superpowers/plans/`.
