# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A side-view incremental pouring game in Godot 4.5 (Forward Plus), hosted at https://github.com/mihai-molnar/pour-game (branch `master`; the local folder is `pour-prototype/`). Pourer on the right, glass on the left: hold DOWN to tilt and pour, release and the pourer swings back upright while liquid already in the air (plus a little from the lip) keeps landing. The goal is to fill the glass to a fill line drawn on it — close to the line pays coins, exact pays the most, overflowing pays nothing.

**Current state: slice 1 (the round loop) is implemented** — spec `docs/superpowers/specs/2026-10-15-round-loop-design.md`, plan in `docs/superpowers/plans/`. A round is 30 s: serve as many glasses as you can, each scored PERFECT/GOOD/MISS/SPILL, with a streak multiplier (x1 to x3), a "LAST CALL!" phase when the timer hits 0:00 (liquid in the air still lands and the last glass is auto-served), then a summary screen and the next round. One drink (water, `drinks/water.tres`), one tumbler, a coin counter that carries across rounds. No shop and no other drinks yet.

**Next slices:** second drink + mixed rounds, then the between-rounds upgrade shop (the `GameState.stats` seam is already in place for it).

**Known deferred work:**
- Auto-refill triggers only below 1 % of full, so a near-empty pourer must be tipped far before it refills — playtest question.
- `--sweep=<id>` only relabels the header; it always simulates `owned_drinks[0]`.
- The LAST_CALL idle auto-serve bypasses `request_serve`'s refill guard.
- Band levels are unclamped for `good_tol` >= 1.

## Commands

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"   # Godot 4.5.1; quote it — the path has a space

"$GODOT" --path .                                   # play
"$GODOT" --headless --path . --import               # import assets / rebuild the class_name cache
"$GODOT" --headless --path . -- --sweep             # tuning table (or --sweep=<drink_id>): hold length -> fill %, overshoot after release, settle time, spill
"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all   # all checks (or --check=<name>)
"$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --shots=/abs/prefix --shot-every=1.5 --quit=40   # autoplayed round + screenshots
python3 tools/make_background.py                    # regenerate art/background.png (needs Pillow)
```

- Checks: `tools/checks/check_{drinks,scoring,glass,pourer,ui,round,bubbles}.gd`, each `extends CheckBase` (`tools/checks/check_base.gd`) and implementing `run()` with `expect`/`eq`/`near`. Success = one `check_<name>: OK` line per check (bubbles also prints `outside the glass: 0`). A crashed runner still exits 0 under `--quit-after`, so judge by the OK lines, not the exit code. Always keep `--quit-after N` (macOS has no `timeout`; a script error can leave headless Godot running forever).
- Why the runner exists: a `--script` file is compiled before autoloads exist, so it can't reference `GameState` or any class that uses it (verified on 4.5.1). `tools/run_check.gd` therefore loads each check at runtime after autoloads, resets `GameState` before each check, and fails a check on any logged script error (Godot 4.5 `Logger`), not only on failed expectations.
- Dev flags (parsed in `main.gd`): `--sweep[=drink_id]`, `--autoplay` (the `Autopilot` plays rounds), `--shots=PREFIX` (native 640x360 PNGs every `--shot-every=S` seconds, default per `main.gd`), `--quit=S`.
- "Could not find type"/"Identifier not declared" for class_names that exist means a stale `.godot` class cache (scripts added outside the editor): run `--import` first.
- Live tuning: run from the editor (F5), switch the Scene dock to **Remote**, select `Pourer`/`Glass`/`Stream` and edit the exported values; the liquid look is on each vessel's `Liquid` node `ShaderMaterial`. Gameplay tunables (round length, tolerances, multipliers) live in `GameState.stats`.

## Architecture

**Rendering.** 640×360 viewport, `stretch/mode="viewport"` (not `canvas_items`) with integer scaling, nearest filtering, and 2D transform + vertex snapping — so everything, including rotated shapes, shaders and fonts, rasterizes at native pixel resolution. All coordinates, speeds and sizes are in 640×360 pixels; the counter top is y=280. The pourer and glass are drawn procedurally in `_draw` (not sprites) so the rotating pourer stays crisp; their drawing and their physics share the same polygons (`interior`/`outer` arrays), so keep them in sync when changing a vessel's shape.

**Units.** Liquid volume is area in px², shared by pourer and glass. Gameplay truth is these numbers; waves, splashes, bubbles and the stream's look are visual only.

**Data and state.**
- `drink_def.gd` (`DrinkDef`) + `drinks/*.tres` — drinks are data (colors, fill-line fraction, vessel shapes). The shapes drive both drawing and physics.
- `game_state.gd` (autoload `GameState`) — coins, round number, owned drinks, and `stats`, the upgrade seam: `round_duration` 30, `perfect_tol` 0.03, `good_tol` 0.10, `coin_mult` 1.0, `pour_speed_mult` 1.0, `refill_time` 1.0. Gameplay reads these at point of use; never hard-code a value that has a stats key.
- `scoring.gd` (`Scoring`) — pure rules: band from error, coins, streak steps (GOOD +1, PERFECT +2, cap 4 steps = x3, reset on MISS/SPILL/new round). Payout uses the multiplier *before* the glass.

**Simulation loop.** `Main` is a phase machine (INTRO, PLAYING, LAST_CALL, SUMMARY). `main.tick(dt, hold)` is the only place round logic advances (tweens are HUD visuals only); each tick runs the fixed 60 Hz sim in a fixed order: `pourer.step()` returns the volume that left the spout -> `stream.emit(spout, exit_velocity, vol, dt)` -> `stream.step(dt, glass)` -> `glass.step(dt)`. The sweep, the checks and `Autopilot` call `tick()` in tight loops, so gameplay must stay deterministic (randomness only for visuals). `manual` mode stops `_process` from ticking so checks and tools drive `tick()` themselves. Serving: Space queues a serve that fires once `!pourer.is_pouring()` and `stream.is_empty()` (in-flight liquid always counts); serves under 1 % of capacity are ignored; Space is ignored during a glass swap or a refill. After a serve the glass slides out (0.35 s), the next glass slides in (0.5 s). LAST_CALL auto-serves after 3 s idle or once the liquid has landed. Holding DOWN across the round end into the next INTRO does nothing (INTRO ignores input).

- `pourer.gd` (renamed from `pitcher.gd`) — node origin = spout lip = rotation pivot; `rotation = -tilt`. Holding approaches `tilt_speed_deg` until liquid reaches the lip, then the slower `pour_tilt_speed_deg` (careful hands); releasing applies a constant `return_force` plus damping (momentum carries it a little further, then it eases back; small bounce at rest). Pouring is geometric: `excess = volume − area(interior ∩ half-plane below the line through the lip at local angle tilt + slosh)`; that excess drains at `pour_rate` (scaled by `pour_speed_mult`) with exit speed growing with √excess. Slosh angle is driven by tilt acceleration. Auto-refill: below 1 % of full volume the pourer swings upright ignoring DOWN and refills for `refill_time`; liquid already in the air still lands.
- `stream.gd` — one ballistic `Parcel` per pouring tick. Crossing the rim decides inside (clamped to the opening, lands on `glass.surface_y_world_at` -> `glass.receive`) vs missed (falls to `table_y`, counted as spilled). Below `drip_flow` volume accumulates into discrete drops. Drawing joins parcels emitted on consecutive ticks, and joins the spout only while flow is continuous.
- `glass.gd` — the interior polygon is rasterized once into per-column spans and per-row pixel areas, so `level_for(volume)` matches the drawn pixels exactly and capacity = interior pixel count. Liquid is drawn as 1-px column rects. The surface is a 1D wave equation per column, excited by impacts and by the glass's horizontal acceleration. Bubbles must stay within the column spans (`_inside`). Each `reset()` picks a random target; it draws the fill line and the GOOD-band bracket.
- `liquid.gdshader` — on each vessel's `Liquid` `DrawLayer`. Samples `hint_screen_texture` with a lens + wobble offset rounded to whole pixels along the vessel's local x axis (the `axis_x` varying handles rotation), tints by view-path thickness, and uses ordered (Bayer) dithering. Vessel scripts set the geometry uniforms (`center_x`, `half_width`, `surface_y`, `highlight_x`); the look uniforms live in the materials in `main.tscn`. Godot copies the screen texture once, at the first item that reads it, so liquids only refract what was drawn before them (the background).
- `draw_layer.gd` — forwards `_draw` to a callable so a vessel draws its shaded `Liquid` layer and its `Front` layer (glass walls, meniscus, fill line, bracket, bubbles) separately. Scene order: Background, Glass (Liquid, Front), Stream, Pourer (Liquid, Front) — the stream draws before the pourer so it appears from behind the spout.
- `hud.gd` (`Hud`) — built in code (Press Start 2P 8 px theme): coins top left, timer top center (red in the last 5 s), streak `xN` left of the glass, result popups, ROUND/LAST CALL banners, "REFILLING..." hint, key hint, F1 debug readout. Purely visual.
- `round_summary.gd/.tscn` (`RoundSummary`) — end-of-round overlay: GLASSES, PERFECT, BEST STREAK, COINS, TOTAL, NEXT ROUND (Space).
- `autopilot.gd` (`Autopilot`) — scripted player used by `--autoplay` and the round check; returns the hold state per tick and requests serves.
- `main.gd` — input (physical DOWN/Space/F1/Esc), builds the HUD, owns the phase machine and dev flags.

**Current tuning baseline** (from `--sweep`, water, full pourer, `pour_tilt_speed_deg = 11.5`): pouring starts with a 0.6 s hold; the hold nearest the fill line is 3.0 s (−1.0 %); 12.4–12.7 % of glass capacity lands after release for fills of 72–89 % (the overshoot the player learns to anticipate); a full pourer is 2.47 glasses at the 90 % line. Half-full pourer: pouring starts ~1.4 s, nearest-line hold 2.6 s. PERFECT (±3 %) is about ±1.5 pixel rows on this glass, so tolerances are effectively set in pixels.

## Visual identity

- Colors are an ENDESGA 32 subset defined in `palette.gd` (`class_name Palette`); reference `Palette.*` rather than color literals (alpha variants are fine). `tools/make_background.py` uses the same hex values; `.tscn` shader params repeat them verbatim.
- Fill line and band: a white line with a dark outline across the glass at the target level (the glass is drawn over tiles and water, so it needs the outline), plus a bracket at the left end spanning the GOOD band. Floating popup text has a dark outline so red/green stay readable over the brick wall.
- Font: Press Start 2P (`fonts/`, SIL OFL), antialiasing off, sizes in multiples of 8.

## Gotchas

- GDScript `const` can't hold `PackedVector2Array(...)` (not a constant expression) — vessel shapes are member `var`s.
- `Geometry2D.clip_polyline_with_polygon` returns the part *outside* the polygon; use `intersect_polyline_with_polygon` for the inside.
- `.godot/` is editor cache — never edit or commit it. Commit Godot's `.uid` sidecars; `main.tscn` will gain `uid=` attributes on first editor save — commit that rewrite too.

## Conventions

- GDScript; snake_case for files, functions and variables; PascalCase for node and class names.
- Design specs go in `docs/superpowers/specs/`, implementation plans in `docs/superpowers/plans/`.
