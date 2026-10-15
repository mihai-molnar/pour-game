# Slice 2 Second Drink and Mixed Rounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add wine (a bottle held over a big stemmed glass) as a second drink that mixes into rounds from round 2, with glasses and pourers that arrive by sliding in, and a bottle that is replaced and uncorked instead of refilled.

**Architecture:** Wine is data (`drinks/wine.tres`) plus three new `DrinkDef` fields (`pourer_glass_color`, `pourer_rest_deg`, `refill_style`). A pure `Arrival` helper computes the slide and lean; `Glass` and `Pourer` each own `arrive()` and step it inside their existing `step()`, applying the lean only to their draw layers. `GameState` gains a round-unlock table, a seeded drink-pick generator and `reset_session()`. `Main` picks each glass's drink, triggers arrivals on serve and at round start (replacing the slide-out/slide-in swap), and wires a new visual-only `Effects` node (puffs, dust, cork).

**Tech Stack:** Godot 4.5.1 (GDScript, Forward Plus), headless checks run by `tools/run_check.gd` (no test framework), Python 3 + Pillow only for optional screenshot sheets.

**Spec:** `docs/superpowers/specs/2026-10-15-second-drink-design.md` (builds on `2026-10-15-round-loop-design.md`)

**Branch:** `feat/second-drink` (merge to `master` when done).

## Global Constraints

- Project root: `/Users/mihai/Godot games/pour-prototype` (or the worktree created for this branch). All paths below are relative to it.
- Every Bash call is a fresh shell: start Godot commands with `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot";` and quote `"$GODOT"` (the path has a space).
- After creating any script with a `class_name` (`arrival.gd`, `effects.gd`), run `"$GODOT" --headless --path . --import` before running checks, or you'll get "Could not find type"/"Identifier not declared" errors from a stale class cache.
- Checks: `tools/checks/check_<name>.gd`, `extends CheckBase`, work in `func run() -> void` with `expect(ok, what)`, `eq(got, want, what)`, `near(got, want, what, tolerance := 1e-4)`. Run one with `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=<name>` (or `--check=all`). Success = a `check_<name>: OK` line per check. The runner fails a check on any failed expectation **or any logged script error**. A crashed runner still exits 0 under `--quit-after`, so judge by the OK lines, never the exit code. Always keep `--quit-after`.
- Inside checks, instantiate the game with `var main: Node = load("res://main.tscn").instantiate()` then `add_child(main)`, and set `main.manual = true` so only the check drives `tick()`.
- GDScript: tabs for indentation; `const` can't hold `PackedVector2Array(...)`; snake_case files/functions/variables, PascalCase classes/nodes; match the surrounding comment density (`##` doc comments on public functions, short `#` comments only where the why isn't obvious).
- Resolution 640×360; all coordinates in 640×360 px; counter top y = 280; glass rest position `Main.GLASS_POS = (256, 280)`.
- Colors only via `Palette.*` in scripts (alpha variants fine); `.tres`/`.tscn` repeat the values verbatim as floats.
- Gameplay reads tunables from `GameState.stats` at point of use (`round_duration` 30, `perfect_tol` 0.03, `good_tol` 0.10, `coin_mult` 1.0, `pour_speed_mult` 1.0, `refill_time` 1.0); never hard-code a value that has a stats key.
- Round logic advances only in `main.tick(dt, hold)`; arrivals, the cork and effects are stepped from it too (no tweens for anything but HUD labels). Gameplay must stay deterministic: randomness only for visuals (`randf` in `Effects`, bubbles, drips) — drink picks use `GameState.rng`.
- Spec numbers: wine glass interior 3 100 px², `fill_fraction` 0.53 (target 1 643 px², line y ≈ −62), PERFECT ≥ ±1 pixel row; wine payout 15 / 12 / 3; bottle held at `pourer_rest_deg` 55, `pourer_offset` (12, −116), 2.5–3.5 glasses per bottle; `ROUND_UNLOCKS = {2: wine}`; first glass after an unlock is the new drink, then uniform picks; `Arrival.ARRIVE_TIME` 0.3 s, overshoot ≤ 3 px, lean peak 6°, wobble ≤ 0.15 s after the slide; glass starts at x = −40, pourer lip at x = 680; `Pourer.POP_TIME` 0.15 s; bottle uncork wiggle `max(refill_time − ARRIVE_TIME, 0.1)`; summary 0.35 s after the last-call glass vanishes.
- The water pitcher must behave exactly as before: `--sweep` (water) output is byte-identical before and after this slice (Tasks 4 and 6 verify it against a saved baseline).
- Commit Godot's `.uid` sidecars; never commit `.godot/`. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Space mashed while the next glass arrives or while a new bottle is still corked** must not serve the next glass — Task 6 `_space_ignored_during_swap_and_refill` (arrival) and Task 4 `_check_wine` (`is_busy()` while corked, which `request_serve` checks).
2. **DOWN held through a drink change** must not tilt the new pourer until it has arrived and (for a bottle) popped its cork, then tilts while still held — Task 4 `_check_wine`, Task 6 `_drink_change_swaps_the_pourer`.
3. **Time running out while the pourer refills** (not holding DOWN): the last-call idle auto-serve must wait for the refill, and the round must still end — Task 6 `_last_call_waits_for_a_refill`.
4. **A faster-refill upgrade that drops `refill_time` below the arrival time** (0.2 s): the bottle refill must still finish (in 0.4 s) — Task 4 refill loop over `[1.0, 0.5, 0.2]`.
5. **Wine poured onto the counter** because the bottle's lip isn't over the opening: drips and streams must land in the glass — Task 1 `check_drinks` (lip over the opening for every drink) and Task 7's sweep criterion (no spill up to the GOOD band).

## Task Dependencies

Sequential: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. Every task leaves `--check=all` green. Tasks 3–5 add `arrive()`/`place()`/`Effects` while `main.gd` still uses the old swap; Task 6 switches `main.gd` over.

---

### Task 1: Wine data, DrinkDef fields, palette, GameState unlocks and seeded picks

**Files:**
- Modify: `palette.gd`, `drink_def.gd`, `game_state.gd`, `tools/run_check.gd`, `tools/checks/check_drinks.gd`
- Create: `drinks/wine.tres`

**Interfaces:**
- Consumes: `Glass.setup(d)`, `Glass.level_for(vol)`, `Glass.target`, `Glass.opening_world()` (existing).
- Produces:
  - `Palette.WINE`, `Palette.WINE_LIGHT`, `Palette.BOTTLE` (`Color`).
  - `DrinkDef.RefillStyle { IN_PLACE, NEW_BOTTLE }`; fields `pourer_glass_color: Color` (default `Color(Palette.FROST, 0.1)`), `pourer_rest_deg: float` (default 0), `refill_style: RefillStyle` (default `IN_PLACE`).
  - `GameState.WATER: DrinkDef` (const), `GameState.ROUND_UNLOCKS: Dictionary` (const, `{2: wine}`), `GameState.rng: RandomNumberGenerator`, `GameState.reset_session(seed_value := -1) -> void`, `GameState.unlock_for_round(n: int) -> DrinkDef` (null when nothing new).
  - The runner calls `GameState.reset_session(1)` before every check.

- [ ] **Step 1: Create the branch**

```bash
git switch -c feat/second-drink
```

- [ ] **Step 2: Write the failing check** — replace `tools/checks/check_drinks.gd` with:

```gdscript
extends CheckBase
## Validates every drink in res://drinks/ and the GameState defaults, unlocks
## and seeded picks.


func run() -> void:
	var expected := {
		"round_duration": 30.0, "perfect_tol": 0.03, "good_tol": 0.10,
		"coin_mult": 1.0, "pour_speed_mult": 1.0, "refill_time": 1.0,
	}
	for key in expected:
		eq(GameState.stats.get(key), expected[key], "stats.%s" % key)
	eq(GameState.BASE_STATS, expected, "BASE_STATS")
	expect(GameState.coins == 0 and GameState.round_number == 1, "session starts at 0 coins, round 1")
	expect(GameState.owned_drinks.size() == 1 and GameState.owned_drinks[0].id == &"water", "owned_drinks is [water]")

	# Typed locals: a preloaded .tres const may only be known as Resource to the analyzer.
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS.get(2)
	expect(wine != null and wine.id == &"wine", "round 2 unlocks wine")
	eq(GameState.unlock_for_round(1), null, "round 1 unlocks nothing")
	eq(GameState.unlock_for_round(2), wine, "round 2 hands out wine")
	eq(GameState.owned_drinks.size(), 2, "...and adds it to owned_drinks")
	eq(GameState.unlock_for_round(2), null, "an owned drink isn't unlocked twice")
	GameState.reset_session(7)
	var first := [GameState.rng.randi(), GameState.rng.randi()]
	GameState.reset_session(7)
	expect(first == [GameState.rng.randi(), GameState.rng.randi()], "reset_session(seed) repeats the picks")
	expect(GameState.owned_drinks.size() == 1 and GameState.owned_drinks[0] == water, "reset_session goes back to water only")
	eq(water.refill_style, DrinkDef.RefillStyle.IN_PLACE, "the pitcher refills in place")
	eq(wine.refill_style, DrinkDef.RefillStyle.NEW_BOTTLE, "the bottle is replaced")
	eq(wine.pourer_rest_deg, 55.0, "the bottle is held at 55°")
	eq(water.pourer_rest_deg, 0.0, "the pitcher stands upright")

	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var checked := 0
	for file in DirAccess.get_files_at("res://drinks"):
		if file.ends_with(".tres"):
			_check_drink(load("res://drinks/" + file), main.glass)
			checked += 1
	expect(checked >= 2, "found water and wine")


func _check_drink(d: DrinkDef, glass: Glass) -> void:
	var n := String(d.id)
	expect(d.id != &"", "%s: has an id" % n)
	expect(d.display_name != "", "%s: has a display name" % n)
	expect(d.glass_interior.size() >= 3 and d.glass_outer.size() >= 3, "%s: glass polygons" % n)
	expect(d.pourer_interior.size() >= 3 and d.pourer_outer.size() >= 3, "%s: pourer polygons" % n)
	expect(d.pourer_interior.has(Vector2.ZERO), "%s: spout lip (0,0) is a pourer_interior vertex" % n)
	expect(d.fill_fraction > 0.0 and d.fill_fraction <= 1.0, "%s: fill_fraction in (0, 1]" % n)
	expect(d.pourer_full_fraction > 0.0 and d.pourer_full_fraction < 1.0, "%s: pourer_full_fraction in (0, 1)" % n)
	expect(d.perfect_coins >= d.good_coins_max and d.good_coins_max >= d.good_coins_min, "%s: coins PERFECT >= GOOD max >= GOOD min" % n)
	for p in d.glass_outer:
		expect(p.y <= 0.0, "%s: the glass sits on its origin (outer y <= 0)" % n)
	_inside(d.glass_interior, d.glass_outer, "%s: glass interior inside outer" % n)
	_inside(d.pourer_interior, d.pourer_outer, "%s: pourer interior inside outer" % n)

	# PERFECT must span at least ±1 pixel row, or it can't be hit by eye.
	glass.setup(d)
	var tol: float = GameState.BASE_STATS.perfect_tol
	var rows := glass.level_for(glass.target * (1.0 - tol)) - glass.level_for(glass.target * (1.0 + tol))
	expect(rows >= 2.0, "%s: PERFECT spans at least ±1 pixel row (%.2f rows)" % [n, rows])
	# Drips leave the spout lip straight down, so it must sit over the opening.
	var opening := glass.opening_world() - Vector2.ONE * glass.global_position.x
	expect(d.pourer_offset.x > opening.x + 1.0 and d.pourer_offset.x < opening.y - 1.0,
		"%s: the spout lip (x %d) is over the glass opening %s" % [n, d.pourer_offset.x, opening])


## Every vertex of `inner`, nudged 5 % toward its centre, lies inside `outer`.
func _inside(inner: PackedVector2Array, outer: PackedVector2Array, what: String) -> void:
	var c := Vector2.ZERO
	for p in inner:
		c += p
	c /= inner.size()
	for p in inner:
		expect(Geometry2D.is_point_in_polygon(p.lerp(c, 0.05), outer), what)
```

- [ ] **Step 3: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=drinks`
Expected: `check_drinks: FAILED` (script errors: `ROUND_UNLOCKS` / `RefillStyle` not declared).

- [ ] **Step 4: Add the palette colors** — in `palette.gd`, after `const WATER_DEEP := Color("124e89")` add:

```gdscript

const WINE := Color("a22633")
const WINE_LIGHT := Color("e43b44")
const BOTTLE := Color("265c42")
```

- [ ] **Step 5: Add the DrinkDef fields** — in `drink_def.gd`:

Replace the header comment and add the enum (the class doc now mentions held pourers):

```gdscript
class_name DrinkDef
extends Resource
## Everything that makes a drink a drink: the glass, the container you pour
## from, the fill line, the payout and the pour feel. One .tres per drink in
## res://drinks/. Shapes are local pixels with y down: the glass origin is its
## bottom center; the pourer origin is the spout lip (the tilt pivot). Pourer
## shapes are authored upright even when the pourer is held tipped
## (pourer_rest_deg).

## IN_PLACE: the pourer fills up where it stands (a pitcher). NEW_BOTTLE: the
## empty one is replaced by a new, corked one that gets uncorked.
enum RefillStyle { IN_PLACE, NEW_BOTTLE }
```

In the `@export_group("Pourer")` block, after the `pourer_handle` line add:

```gdscript
## The pourer's glass: rgb tints it, alpha is the body's tint strength (the
## walls get 3× that, capped at 1).
@export var pourer_glass_color := Color(Palette.FROST, 0.1)
```

and after the `pourer_offset` line add:

```gdscript
## The angle (°) it is held at when not pouring: 0 = standing upright; a bottle
## is held tipped over the glass. Tilt and max_tilt_deg count from here.
@export_range(0.0, 90.0) var pourer_rest_deg := 0.0
## How it comes back full once it runs dry.
@export var refill_style := RefillStyle.IN_PLACE
```

- [ ] **Step 6: Create `drinks/wine.tres`**

```
[gd_resource type="Resource" script_class="DrinkDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://drink_def.gd" id="1_drink"]

[resource]
script = ExtResource("1_drink")
id = &"wine"
display_name = "Wine"
liquid_color = Color(0.635294, 0.14902, 0.2, 1)
liquid_highlight = Color(0.894118, 0.231373, 0.266667, 1)
glass_interior = PackedVector2Array(-14, -26, 14, -26, 19, -28, 22, -32, 23, -40, 24, -52, 24, -62, 23, -72, 21, -84, 18, -96, -18, -96, -21, -84, -23, -72, -24, -62, -24, -52, -23, -40, -22, -32, -19, -28)
glass_outer = PackedVector2Array(-14, 0, 14, 0, 14, -2, 2, -4, 2, -22, 16, -24, 21, -26, 24, -30, 25, -40, 26, -52, 26, -62, 25, -72, 23, -84, 20, -96, -20, -96, -23, -84, -25, -72, -26, -62, -26, -52, -25, -40, -24, -30, -21, -26, -16, -24, -2, -22, -2, -4, -14, -2)
fill_fraction = 0.53
perfect_coins = 15
good_coins_max = 12
good_coins_min = 3
pourer_interior = PackedVector2Array(0, 0, 6, 0, 6, 24, 23, 38, 23, 148, -17, 148, -17, 38, 0, 24)
pourer_outer = PackedVector2Array(-2, -1, 8, -1, 8, 23, 25, 37, 25, 151, -19, 151, -19, 37, -2, 23)
pourer_glass_color = Color(0.14902, 0.360784, 0.258824, 0.35)
spout_dir = Vector2(0, -1)
pourer_offset = Vector2(12, -116)
pourer_rest_deg = 55.0
refill_style = 1
max_tilt_deg = 100.0
rest_bounce = 0.1
pour_tilt_speed_deg = 15.0
max_flow = 1500.0
```

(The glass and bottle shapes were sized while planning: capacity 3 100 px², PERFECT 2.05 rows, opening x 238–274, bottle 4 866 px² inside = 2.67 glasses full. The pour values are starting points; Task 7 tunes them. Don't change the shapes.)

- [ ] **Step 7: Rewrite `game_state.gd`**

```gdscript
extends Node
## Session state (autoload `GameState`): coins, round progress, owned drinks,
## the seeded generator that picks each glass's drink, and `stats` — every
## tunable a future upgrade may change. Gameplay reads `stats` at point of use
## and never hard-codes a value that has a key. Nothing is saved yet (session only).

const BASE_STATS := {
	"round_duration": 30.0,
	"perfect_tol": 0.03,
	"good_tol": 0.10,
	"coin_mult": 1.0,
	"pour_speed_mult": 1.0,
	"refill_time": 1.0,
}
const WATER := preload("res://drinks/water.tres")
## Drinks a round gives you when it starts — a stand-in for the slice 3 shop,
## which replaces this table.
const ROUND_UNLOCKS := {2: preload("res://drinks/wine.tres")}

var coins := 0
var round_number := 1
var owned_drinks: Array[DrinkDef] = [WATER]
var stats: Dictionary = BASE_STATS.duplicate()
## Picks each glass's drink. Seeded randomly at startup; --seed=N and the
## checks seed it so a run repeats exactly.
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## Back to a fresh session: 0 coins, round 1, only water, base stats. A
## `seed_value` >= 0 seeds the drink picks; a negative one picks a random seed.
func reset_session(seed_value := -1) -> void:
	coins = 0
	round_number = 1
	owned_drinks.clear()
	owned_drinks.append(WATER)
	stats = BASE_STATS.duplicate()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Adds the drink ROUND_UNLOCKS gives for round `n` and returns it; null when
## the round unlocks nothing or the drink is already owned.
func unlock_for_round(n: int) -> DrinkDef:
	var d: DrinkDef = ROUND_UNLOCKS.get(n)
	if d == null or owned_drinks.has(d):
		return null
	owned_drinks.append(d)
	return d
```

- [ ] **Step 8: Make the runner reset the whole session** — in `tools/run_check.gd`, replace

```gdscript
		gs.stats = gs.BASE_STATS.duplicate()
		gs.coins = 0
		gs.round_number = 1
```

with

```gdscript
		gs.reset_session(1)
```

- [ ] **Step 9: Run the checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import && "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: seven OK lines (`check_bubbles`, `check_drinks`, `check_glass`, `check_pourer`, `check_round`, `check_scoring`, `check_ui`). If `check_drinks` reports the PERFECT rows or the lip, re-check `wine.tres` against Step 6 — don't change the check.

- [ ] **Step 10: Commit**

```bash
git add palette.gd drink_def.gd game_state.gd drinks/wine.tres tools/run_check.gd tools/checks/check_drinks.gd
git commit -m "$(cat <<'EOF'
feat: wine drink data, held/bottle pourer fields, round unlocks and seeded picks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Arrival curves

**Files:**
- Create: `arrival.gd`, `tools/checks/check_arrival.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `class_name Arrival` (RefCounted, static only): consts `ARRIVE_TIME := 0.3`, `BRAKE_SHARE := 0.7`, `OVERSHOOT_PX := 3.0`, `LEAN_DEG := 6.0`, `WOBBLE_TIME := 0.15`, `WOBBLE_SWINGS := 2.5`; `static func offset(t: float, from: float) -> float`; `static func lean(t: float, dir: float) -> float` (radians; `dir` +1 = moving right); `static func done(t: float) -> bool`; `static func pivot(points: PackedVector2Array, frame_rotation: float, dir: float) -> Vector2`.

- [ ] **Step 1: Write the failing check** — `tools/checks/check_arrival.gd`:

```gdscript
extends CheckBase
## Checks the arrival curves (slice 2 spec, "Arrivals"). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=arrival


func run() -> void:
	for from: float in [-296.0, 412.0]:
		var dir := -signf(from)
		near(Arrival.offset(0.0, from), from, "starts off-screen (%d)" % from)
		near(Arrival.offset(Arrival.ARRIVE_TIME, from), 0.0, "home at ARRIVE_TIME (%d)" % from)
		near(Arrival.offset(5.0, from), 0.0, "stays home (%d)" % from)
		var furthest := -INF
		var t := 0.0
		while t <= Arrival.ARRIVE_TIME + 0.1:
			furthest = maxf(furthest, Arrival.offset(t, from) * dir)
			t += 0.001
		expect(furthest <= Arrival.OVERSHOOT_PX + 1e-6, "overshoot at most %.0f px (%d: %.3f)" % [Arrival.OVERSHOOT_PX, from, furthest])
		expect(furthest >= Arrival.OVERSHOOT_PX - 0.05, "it does overshoot (%d: %.3f)" % [from, furthest])
	for dir: float in [1.0, -1.0]:
		eq(Arrival.lean(0.0, dir), 0.0, "no lean at the start")
		eq(Arrival.lean(Arrival.ARRIVE_TIME + Arrival.WOBBLE_TIME, dir), 0.0, "upright after the wobble")
		var peak := 0.0
		var t := 0.0
		while t < Arrival.ARRIVE_TIME + Arrival.WOBBLE_TIME:
			peak = maxf(peak, absf(Arrival.lean(t, dir)))
			t += 0.001
		expect(peak <= deg_to_rad(Arrival.LEAN_DEG) + 1e-6 and peak > deg_to_rad(Arrival.LEAN_DEG) * 0.9,
			"lean peaks at about LEAN_DEG (%.2f°)" % rad_to_deg(peak))
		eq(signf(Arrival.lean(Arrival.ARRIVE_TIME * 0.5, dir)), dir, "it tips toward its travel while braking")
	expect(not Arrival.done(Arrival.ARRIVE_TIME) and Arrival.done(Arrival.ARRIVE_TIME + Arrival.WOBBLE_TIME), "done() after the wobble")
	var tumbler := PackedVector2Array([Vector2(-17, 0), Vector2(17, 0), Vector2(21, -74), Vector2(-21, -74)])
	eq(Arrival.pivot(tumbler, 0.0, 1.0), Vector2(17, 0), "a glass moving right tips over its right foot")
	eq(Arrival.pivot(tumbler, 0.0, -1.0), Vector2(-17, 0), "...moving left, its left foot")
	var bottle := PackedVector2Array([Vector2(-2, -1), Vector2(8, -1), Vector2(25, 151), Vector2(-19, 151)])
	eq(Arrival.pivot(bottle, -deg_to_rad(55.0), -1.0), Vector2(-19, 151), "a held bottle tips over its lowest corner once turned")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=arrival`
Expected: `check_arrival: FAILED` (`Arrival` not declared).

- [ ] **Step 3: Create `arrival.gd`**

```gdscript
class_name Arrival
## Slide-in motion for a glass or pourer arriving from off-screen: pure
## functions of the time since the arrival started (no state, no tweens), so
## vessels step them from their own step() inside main.tick() and stay
## deterministic. See docs/superpowers/specs/2026-10-15-second-drink-design.md
## ("Arrivals").

## Seconds from off-screen to home.
const ARRIVE_TIME := 0.3
## Share of ARRIVE_TIME spent braking into the overshoot; the rest settles back.
const BRAKE_SHARE := 0.7
## How far past home it overshoots (px).
const OVERSHOOT_PX := 3.0
## Peak lean (°) as it brakes.
const LEAN_DEG := 6.0
## The wobble may run this long after the slide ends.
const WOBBLE_TIME := 0.15
## Half-swings in the wobble (2.5 = forward, back, forward, settle).
const WOBBLE_SWINGS := 2.5


## Offset from home along x at time `t`, starting at `from` (e.g. -296 for a
## glass coming from the left): eases out to OVERSHOOT_PX past home, then
## settles to exactly 0 at ARRIVE_TIME.
static func offset(t: float, from: float) -> float:
	if t >= ARRIVE_TIME:
		return 0.0
	var past := -signf(from) * OVERSHOOT_PX
	var brake := ARRIVE_TIME * BRAKE_SHARE
	if t < brake:
		var s := maxf(t, 0.0) / brake
		return lerpf(from, past, 1.0 - pow(1.0 - s, 3.0))
	var u := (t - brake) / (ARRIVE_TIME - brake)
	return past * (1.0 - u * u * (3.0 - 2.0 * u))


## Lean (radians) at time `t` for travel direction `dir` (+1 = moving right):
## tips toward the travel direction while braking, then wobbles back upright;
## exactly 0 from ARRIVE_TIME + WOBBLE_TIME on.
static func lean(t: float, dir: float) -> float:
	if t <= 0.0:
		return 0.0
	var peak := deg_to_rad(LEAN_DEG) * dir
	var brake := ARRIVE_TIME * BRAKE_SHARE
	if t < brake:
		return peak * sin(t / brake * PI * 0.5)
	var u := (t - brake) / (ARRIVE_TIME + WOBBLE_TIME - brake)
	if u >= 1.0:
		return 0.0
	var fade := 1.0 - u
	return peak * cos(u * WOBBLE_SWINGS * PI) * fade * fade


## True once the slide and its wobble are over.
static func done(t: float) -> bool:
	return t >= ARRIVE_TIME + WOBBLE_TIME


## The point a vessel tips over: its lowest point once turned by
## `frame_rotation` (its rest rotation, radians), ties broken toward the travel
## direction `dir`. Returned in the vessel's own unrotated coordinates.
static func pivot(points: PackedVector2Array, frame_rotation: float, dir: float) -> Vector2:
	var best := points[0]
	var best_key := Vector2(-INF, -INF)
	for p in points:
		var w := p.rotated(frame_rotation)
		var key := Vector2(snappedf(w.y, 0.01), w.x * dir)
		if key > best_key:
			best_key = key
			best = p
	return best
```

- [ ] **Step 4: Import and run the check**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import && "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: eight OK lines, including `check_arrival: OK`.

- [ ] **Step 5: Commit**

```bash
git add arrival.gd arrival.gd.uid tools/checks/check_arrival.gd tools/checks/check_arrival.gd.uid
git commit -m "$(cat <<'EOF'
feat: Arrival slide, lean and pivot curves

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(If Godot didn't create a `.uid` for the check, drop it from `git add`; `git status` shows what exists.)

---

### Task 3: Glass arrivals, vanish/place, and the fill-line fix for narrowing glasses

**Files:**
- Modify: `glass.gd`
- Modify: `tools/checks/check_glass.gd`

**Interfaces:**
- Consumes: `Arrival.*` (Task 2); `GameState.WATER`, `GameState.ROUND_UNLOCKS` (Task 1).
- Produces: on `Glass`: `signal landed(at: Vector2)`; `const OFFSCREEN_X := -40.0`; `var home: Vector2`; `func arrive(d: DrinkDef, at: Vector2) -> void`; `func place(at: Vector2) -> void`; `func vanish() -> void`; `func is_arriving() -> bool`; `func center_global() -> Vector2`; `func bracket_x() -> int`; `func left_tick() -> Vector2i`. `step(dt)` advances an arrival. The node itself never rotates; the lean turns the `Liquid` and `Front` children.

- [ ] **Step 1: Write the failing check** — replace `tools/checks/check_glass.gd` with:

```gdscript
extends CheckBase
## Checks the glass: exact capacity and fixed target per drink, band levels
## following stats.good_tol, geometry helpers, the fill-line tick on a glass
## that narrows toward the rim, setup leaving no state behind, and the
## arrival. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass

const DT := 1.0 / 60.0
const HOME := Vector2(256, 280)


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	glass.place(HOME)
	expect(glass.def == water, "glass is set up with water")
	expect(glass.capacity == 2346.0, "capacity = interior pixel count (got %d)" % glass.capacity)
	var want := 0.9 * glass.capacity
	expect(is_equal_approx(glass.target, want), "target = fill_fraction x capacity")
	for i in 5:
		glass.reset()
	expect(is_equal_approx(glass.target, want), "target stays fixed across resets")
	expect(glass.volume == 0.0 and glass.spilled == 0.0, "reset empties the glass")
	expect(is_equal_approx(glass.level_for(0.0), -5.0), "empty level is the floor")
	expect(is_equal_approx(glass.level_for(glass.capacity), -74.0), "full level is the rim")
	var band := glass.band_levels()
	expect(band.x < glass.target_y() and glass.target_y() < band.y, "band edges straddle the fill line (%s vs %.1f)" % [band, glass.target_y()])
	GameState.stats.good_tol = 0.2
	var wide := glass.band_levels()
	GameState.stats.good_tol = 0.1
	expect(wide.x <= band.x and wide.y > band.y, "a wider good_tol widens the band (%s vs %s)" % [wide, band])
	expect(glass.opening_world() == Vector2(237, 275), "opening at the rim (got %s)" % glass.opening_world())
	expect(is_equal_approx(glass.rim_y_world(), 206.0), "rim at y=206 (got %.1f)" % glass.rim_y_world())
	expect(_tint_clear(glass), "wall tint polygons leave the interior clear")
	var walls := glass.outer_x_at(-37.0)
	expect(walls.is_equal_approx(Vector2(-19, 19)), "outer walls at mid height (got %s)" % walls)
	eq(glass.left_tick(), Vector2i(-25, -23), "water: the fill-line tick is unchanged")

	_check_wine(glass, wine)
	glass.setup(water)
	expect(glass.capacity == 2346.0 and is_equal_approx(glass.target, want), "back to water: same capacity and target")
	expect(glass.opening_world() == Vector2(237, 275), "back to water: same opening (got %s)" % glass.opening_world())
	expect(glass.volume == 0.0 and glass._row_area.size() == 69, "back to water: empty, water's 69 rows (got %d)" % glass._row_area.size())
	_check_arrival(glass, water)


func _check_wine(glass: Glass, wine: DrinkDef) -> void:
	glass.setup(wine)
	expect(glass.capacity == 3100.0, "wine: capacity = interior pixel count (got %d)" % glass.capacity)
	expect(is_equal_approx(glass.target, 0.53 * glass.capacity), "wine: target = fill_fraction x capacity")
	var prev := glass.level_for(0.0)
	var rising := true
	var v := 25.0
	while v <= glass.capacity:
		var y := glass.level_for(v)
		rising = rising and y < prev
		prev = y
		v += 25.0
	expect(rising, "wine: the level rises with every 25 px² poured")
	expect(is_equal_approx(glass.rim_y_world(), 184.0), "wine: rim at y=184 (got %.1f)" % glass.rim_y_world())
	expect(glass.opening_world() == Vector2(238, 274), "wine: opening (got %s)" % glass.opening_world())
	eq(glass.left_tick(), Vector2i(-30, -28), "wine: the tick runs from the bracket to the bulging wall")
	expect(_tint_clear(glass), "wine: wall tint polygons leave the bowl clear")


func _check_arrival(glass: Glass, water: DrinkDef) -> void:
	var landed: Array[Vector2] = []
	glass.landed.connect(func(at: Vector2) -> void: landed.append(at))
	var front: Node2D = glass.get_node("Front")
	glass.receive(HOME.x, 500.0, 0.0)
	glass.arrive(water, HOME)
	expect(glass.volume == 0.0, "an arriving glass is empty")
	near(glass.position.x, Glass.OFFSCREEN_X, "it starts off-screen left")
	expect(glass.is_arriving() and glass.visible, "...visible and arriving")
	var t := 0.0
	var leaned := false
	var node_rotated := false
	while glass.is_arriving() and t < 1.0:
		glass.step(DT)
		t += DT
		leaned = leaned or absf(front.rotation) > 0.01
		node_rotated = node_rotated or glass.rotation != 0.0
	expect(absf(t - Arrival.ARRIVE_TIME) <= DT + 1e-6, "the slide takes ARRIVE_TIME (%.3f s)" % t)
	expect(glass.position == HOME, "it ends exactly at home (%s)" % glass.position)
	eq(landed.size(), 1, "landed fires once")
	if landed.size() == 1:
		expect(landed[0].is_equal_approx(HOME + Vector2(17, 0)), "...at the leading foot corner (%s)" % landed[0])
	while t < 1.0:
		glass.step(DT)
		t += DT
		leaned = leaned or absf(front.rotation) > 0.01
		node_rotated = node_rotated or glass.rotation != 0.0
	expect(leaned and not node_rotated, "the lean turns the drawing, never the node")
	eq(front.rotation, 0.0, "upright after the wobble")
	glass.vanish()
	expect(not glass.visible and not glass.is_arriving(), "vanish hides the glass")
	glass.place(HOME)
	expect(glass.visible and glass.position == HOME, "place shows it at home at once")


func _tint_clear(glass: Glass) -> bool:
	var tint := DrawLayer.wall_polygons(glass.outer, glass.interior)
	var c := Vector2.ZERO
	for p in glass.interior:
		c += p
	c /= glass.interior.size()
	for w in tint:
		if Geometry2D.is_point_in_polygon(c, w):
			return false
	return not tint.is_empty()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass`
Expected: `check_glass: FAILED` (`place`/`left_tick`/`arrive` not found).

- [ ] **Step 3: Add arrival state and API to `glass.gd`**

Extend the class doc (append to the existing `##` block at the top, after the line ending `(fill_fraction × capacity) and the ±good_tol band is drawn beside it.`):

```gdscript
## A new glass arrives by sliding in from the left (arrive()); the lean only
## turns the Liquid and Front layers, never this node, so landing liquid and
## the rim/opening helpers never see it.
```

After the `@export var move_slosh := 0.0012` line add:

```gdscript

## Emitted when an arrival stops sliding; `at` = the foot corner it tips over (global).
signal landed(at: Vector2)

## Where an arriving glass starts: fully off-screen left.
const OFFSCREEN_X := -40.0
```

After `var capacity := 0.0` add:

```gdscript
## Where it rests (in Main's space).
var home := Vector2.ZERO
```

After `var _last_vx := 0.0` add:

```gdscript
var _arrive_t := -1.0  # < 0 when not arriving (covers the slide and the wobble)
var _pivot := Vector2.ZERO
```

After the `reset()` function add:

```gdscript
## Sets the glass up for `d` (empty), puts it off-screen left and starts
## sliding it to `at`.
func arrive(d: DrinkDef, at: Vector2) -> void:
	setup(d)
	home = at
	position = Vector2(OFFSCREEN_X, at.y)
	visible = true
	_last_x = position.x
	_last_vx = 0.0
	_pivot = Arrival.pivot(outer, 0.0, 1.0)
	_arrive_t = 0.0
	_apply_lean(0.0)


## Puts the glass at `at` at once, no arrival — for the sweep and checks.
func place(at: Vector2) -> void:
	home = at
	position = at
	visible = true
	_last_x = at.x
	_last_vx = 0.0
	_arrive_t = -1.0
	_apply_lean(0.0)


## The served glass disappears (Main leaves a puff where it was).
func vanish() -> void:
	visible = false
	_arrive_t = -1.0
	_apply_lean(0.0)


## True while sliding in; the wobble after it doesn't count.
func is_arriving() -> bool:
	return _arrive_t >= 0.0 and _arrive_t < Arrival.ARRIVE_TIME


func center_global() -> Vector2:
	var box := Rect2(outer[0], Vector2.ZERO)
	for p in outer:
		box = box.expand(p)
	return to_global(box.get_center())


func _step_arrival(dt: float) -> void:
	if _arrive_t < 0.0:
		return
	var was_sliding := is_arriving()
	_arrive_t += dt
	position.x = home.x + Arrival.offset(_arrive_t, OFFSCREEN_X - home.x)
	if was_sliding and not is_arriving():
		landed.emit(to_global(_pivot))
	_apply_lean(Arrival.lean(_arrive_t, 1.0))
	if Arrival.done(_arrive_t):
		_arrive_t = -1.0
		_apply_lean(0.0)


## Turns the drawing by `angle` about the arrival pivot (the node stays put).
func _apply_lean(angle: float) -> void:
	for layer: Node2D in [_liquid, _front]:
		layer.rotation = angle
		layer.position = _pivot - _pivot.rotated(angle)
```

- [ ] **Step 4: Step the arrival and stop an empty glass sloshing** — in `glass.gd` `step(dt)`:

Make `_step_arrival(dt)` the first line of `step`:

```gdscript
func step(dt: float) -> void:
	_step_arrival(dt)
	_level = level_for(volume)
```

and replace

```gdscript
			acc -= ax * move_slosh * (i - mid)
```

with

```gdscript
			if volume >= 0.5:  # an empty glass has nothing to slosh (arrivals would leave waves)
				acc -= ax * move_slosh * (i - mid)
```

- [ ] **Step 5: Fix the bracket and the fill-line tick for narrowing glasses** — in `glass.gd`:

Add after `band_levels()`:

```gdscript
## Local x of the band bracket's spine: 4 px left of the outer wall's leftmost
## point across the band rows, so it also clears bowls that narrow toward the rim.
func bracket_x() -> int:
	var band := band_levels()
	var left := INF
	for y in range(int(band.x), int(band.y) + 2):
		left = minf(left, outer_x_at(float(y)).x)
	return floori(left) - 4


## The fill line's left tick as local x (start, end): from the bracket's spine
## to 2 px short of the wall at the line.
func left_tick() -> Vector2i:
	var ty := roundi(_target_y)
	return Vector2i(bracket_x(), floori(outer_x_at(float(ty) + 0.5).x) - 2)
```

In `_draw_band`, replace `var x := floori(outer_x_at(float(y_top)).x) - 4` with `var x := bracket_x()`.

In `_draw_fill_line`, replace

```gdscript
	var walls := outer_x_at(float(ty) + 0.5)
	var bracket_x := floori(outer_x_at(band_levels().x).x) - 4
	var left_end := floori(walls.x) - 2
	ci.draw_rect(Rect2(bracket_x - 1, ty - 1, left_end - bracket_x + 2, 3), Palette.INK)
	ci.draw_rect(Rect2(bracket_x, ty, left_end - bracket_x, 1), Palette.WHITE)
```

with

```gdscript
	var tick := left_tick()
	ci.draw_rect(Rect2(tick.x - 1, ty - 1, tick.y - tick.x + 2, 3), Palette.INK)
	ci.draw_rect(Rect2(tick.x, ty, tick.y - tick.x, 1), Palette.WHITE)
	var walls := outer_x_at(float(ty) + 0.5)
```

(the right tick below keeps using `walls`).

- [ ] **Step 6: Run the checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: eight OK lines. (`main.gd` still swaps the old way; it only moves `glass.position`, which doesn't start an arrival.)

- [ ] **Step 7: Commit**

```bash
git add glass.gd tools/checks/check_glass.gd
git commit -m "$(cat <<'EOF'
feat: glass arrivals with a drawing-only lean; fill-line tick clears narrowing bowls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Pourer rest angle, arrivals, cork and the bottle refill

**Files:**
- Modify: `pourer.gd` (full replacement below)
- Modify: `tools/checks/check_pourer.gd` (full replacement below)

**Interfaces:**
- Consumes: `Arrival.*` (Task 2); `DrinkDef.pourer_glass_color`, `pourer_rest_deg`, `refill_style`, `GameState.WATER`, `GameState.ROUND_UNLOCKS` (Task 1).
- Produces: on `Pourer`: signals `vanished(at: Vector2)`, `landed(at: Vector2)`, `popped(at: Vector2, velocity: Vector2, spray: Color)`; consts `OFFSCREEN_X := 680.0`, `POP_TIME := 0.15`, `MIN_UNCORK := 0.1`; vars `home: Vector2`, `corked: bool`; `func arrive(d: DrinkDef, at: Vector2) -> void`; `func place(at: Vector2) -> void`; `func is_arriving() -> bool`; `func is_busy() -> bool` (refilling, corked or arriving); `func center_global() -> Vector2`. `rotation = -(rest + tilt)`; the lean turns only the `Liquid`/`Front` children.

- [ ] **Step 1: Save the water baseline sweep** (it must not change)

```bash
mkdir -p .superpowers && GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -- --sweep 2>&1 | grep -v '^Godot Engine' > .superpowers/sweep_water_before.txt; tail -3 .superpowers/sweep_water_before.txt
```

Expected: the last rows of the half-full table.

- [ ] **Step 2: Write the failing check** — replace `tools/checks/check_pourer.gd` with:

```gdscript
extends CheckBase
## Checks the pourer: DrinkDef setup, capacity vs the glass, pour_speed_mult,
## the held rest angle, arrivals (DOWN ignored until ready, a bottle's cork)
## and both refill styles. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=pourer

const DT := 1.0 / 60.0
const GLASS_POS := Vector2(256, 280)

var _events := {"vanished": 0, "landed": [], "popped": 0}


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var pourer: Pourer = main.pourer
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	pourer.vanished.connect(func(_at: Vector2) -> void: _events.vanished += 1)
	pourer.landed.connect(func(at: Vector2) -> void: _events.landed.append(at))
	pourer.popped.connect(func(_at: Vector2, _v: Vector2, _c: Color) -> void: _events.popped += 1)

	glass.setup(water)
	glass.place(GLASS_POS)
	pourer.setup(water)
	pourer.place(GLASS_POS + water.pourer_offset)
	expect(pourer.def == water, "pourer is set up with water")
	var glasses := pourer.full_volume / glass.target
	expect(glasses > 2.3 and glasses < 2.7, "a full pitcher holds ~2.5 glasses at the line (got %.2f)" % glasses)
	pourer.reset()
	expect(pourer.volume == pourer.full_volume and not pourer.refilling and not pourer.corked, "reset() = full, upright, not refilling")
	expect(pourer.rotation == 0.0, "a pitcher stands upright at rest")

	# The wall tint must not cover the interior (clip_polygons alone returns the
	# interior as a hole polygon, which fills it with frost).
	_walls_cover_interior(DrawLayer.wall_polygons(pourer.def.pourer_outer, pourer.interior), pourer.interior, "wall_polygons")

	# pour_speed_mult scales the tilt speed (measured before any pouring starts).
	var base_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 2.0
	var fast_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 1.0
	var ratio := fast_tilt / base_tilt
	expect(ratio > 1.8 and ratio < 2.2, "pour_speed_mult 2 doubles the tilt speed (ratio %.2f)" % ratio)

	# Running dry while tilted: DOWN is ignored (same motion held or not), it
	# returns upright, then refills in place over stats.refill_time.
	var held := _drain_and_refill(pourer, true)
	var free := _drain_and_refill(pourer, false)
	expect(held.tilts == free.tilts, "refilling ignores DOWN")
	expect(held.upright_at > 0.0, "it returned upright before refilling")
	expect(absf(held.refill_s - 1.0) < 0.1, "refill takes refill_time once upright (took %.2f s)" % held.refill_s)
	expect(is_equal_approx(pourer.volume, pourer.full_volume) and not pourer.refilling, "refilled to full")
	GameState.stats.refill_time = 0.5
	var quick := _drain_and_refill(pourer, false)
	GameState.stats.refill_time = 1.0
	expect(absf(quick.refill_s - 0.5) < 0.1, "refill_time is read live (took %.2f s)" % quick.refill_s)
	eq(_events.vanished, 0, "a pitcher never vanishes")

	_check_arrival(pourer, water)
	_check_wine(pourer, glass, wine)


func _check_arrival(pourer: Pourer, water: DrinkDef) -> void:
	var home := GLASS_POS + water.pourer_offset
	_events.landed.clear()
	pourer.volume = pourer.full_volume * 0.3
	pourer.arrive(water, home)
	expect(is_equal_approx(pourer.volume, pourer.full_volume), "an arriving pourer is full")
	near(pourer.position.x, Pourer.OFFSCREEN_X, "it starts off-screen right")
	expect(not pourer.corked, "a pitcher has no cork")
	var t := 0.0
	while pourer.is_arriving() and t < 1.0:
		pourer.step(DT, true)  # DOWN held all along
		t += DT
	expect(pourer.tilt == 0.0, "DOWN is ignored while it arrives")
	expect(absf(t - Arrival.ARRIVE_TIME) <= DT + 1e-6, "the slide takes ARRIVE_TIME (%.3f s)" % t)
	expect(pourer.position == home, "it ends exactly at home (%s)" % pourer.position)
	eq(_events.landed.size(), 1, "landed fires once")
	if _events.landed.size() == 1:
		expect(_events.landed[0].is_equal_approx(home + Vector2(11, 105)), "...at the pitcher's leading bottom corner (%s)" % _events.landed[0])
	pourer.step(DT, true)
	expect(pourer.tilt > 0.0, "once it has arrived, DOWN tilts it")


func _check_wine(pourer: Pourer, glass: Glass, wine: DrinkDef) -> void:
	var home := GLASS_POS + wine.pourer_offset
	glass.setup(wine)
	glass.place(GLASS_POS)
	pourer.setup(wine)
	pourer.place(home)
	var glasses := pourer.full_volume / glass.target
	expect(glasses >= 2.5 and glasses <= 3.5, "a full bottle holds 2.5-3.5 glasses at the line (got %.2f)" % glasses)
	near(pourer.rotation, -deg_to_rad(55.0), "the bottle is held at 55°")
	var poured := 0.0
	for i in 60:
		poured += pourer.step(DT, false)
	expect(poured == 0.0, "a full bottle held at rest doesn't pour")
	var t := 0.0
	while poured == 0.0 and t < 3.0:
		poured += pourer.step(DT, true)
		t += DT
	expect(poured > 0.0, "holding DOWN pours from the bottle (after %.2f s)" % t)

	# A drink change or round start: it arrives corked, ignores DOWN, and pops
	# POP_TIME after it lands.
	_events.popped = 0
	pourer.arrive(wine, home)
	expect(pourer.corked and pourer.is_busy(), "a bottle arrives corked")
	t = 0.0
	var tilted_while_corked := false
	while pourer.corked and t < 2.0:
		pourer.step(DT, true)
		t += DT
		tilted_while_corked = tilted_while_corked or (pourer.corked and pourer.tilt > 0.0)
	var want := Arrival.ARRIVE_TIME + Pourer.POP_TIME
	expect(absf(t - want) <= DT + 1e-6, "the cork pops %.2f s after it starts arriving (%.3f s)" % [want, t])
	eq(_events.popped, 1, "popped fires once")
	expect(not tilted_while_corked, "DOWN is ignored until the cork is out")
	pourer.step(DT, true)
	expect(pourer.tilt > 0.0 and not pourer.is_busy(), "then DOWN tilts it")

	# Running dry: the empty bottle vanishes, a new corked one arrives and is
	# uncorked, all within refill_time (never shorter than the slide + 0.1 s).
	for refill_time: float in [1.0, 0.5, 0.2]:
		GameState.stats.refill_time = refill_time
		_events.vanished = 0
		_events.popped = 0
		var held := _drain_and_refill(pourer, true)
		var free := _drain_and_refill(pourer, false)
		var want_s := maxf(refill_time, Arrival.ARRIVE_TIME + Pourer.MIN_UNCORK)
		expect(held.tilts == free.tilts, "a bottle refill ignores DOWN (refill_time %.1f)" % refill_time)
		expect(absf(held.refill_s - want_s) < 0.1, "a bottle refill takes %.1f s once upright (took %.2f s)" % [want_s, held.refill_s])
		eq(_events.vanished, 2, "the empty bottle vanishes once per refill (refill_time %.1f)" % refill_time)
		eq(_events.popped, 2, "the new bottle is uncorked once per refill (refill_time %.1f)" % refill_time)
		expect(is_equal_approx(pourer.volume, pourer.full_volume) and not pourer.corked and not pourer.refilling, "a full, open bottle after the refill")
		expect(pourer.position == home, "back at home after the refill (%s)" % pourer.position)
	GameState.stats.refill_time = 1.0


func _tilt_after_hold(pourer: Pourer, seconds: float) -> float:
	pourer.reset()
	var t := 0.0
	while t < seconds - 1e-6:
		pourer.step(DT, true)
		t += DT
	return pourer.tilt


## Tilts the pourer to 1 rad with an almost empty pourer, then steps until the
## refill ends. Returns {tilts: Array, upright_at: float, refill_s: float}.
func _drain_and_refill(pourer: Pourer, hold: bool) -> Dictionary:
	pourer.reset()
	pourer.tilt = 1.0
	pourer.volume = pourer.full_volume * 0.005
	var tilts: Array[float] = []
	var upright_at := -1.0
	var t := 0.0
	pourer.step(DT, hold)
	t += DT
	while pourer.refilling and t < 10.0:
		tilts.append(pourer.tilt)
		if upright_at < 0.0 and pourer.tilt == 0.0 and pourer.tilt_vel == 0.0:
			upright_at = t
		pourer.step(DT, hold)
		t += DT
	return {"tilts": tilts, "upright_at": upright_at, "refill_s": t - upright_at}


func _walls_cover_interior(walls: Array, interior: PackedVector2Array, what: String) -> void:
	var c := Vector2.ZERO
	for p in interior:
		c += p
	c /= interior.size()
	var covered := false
	for w in walls:
		if Geometry2D.is_point_in_polygon(c, w):
			covered = true
	expect(not covered, "%s: no wall polygon contains the interior centre" % what)
```

- [ ] **Step 3: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=pourer`
Expected: `check_pourer: FAILED` (`vanished`/`place` not found).

- [ ] **Step 4: Replace `pourer.gd`**

```gdscript
class_name Pourer
extends Node2D
## The container you pour from (pitcher, bottle …), configured by a DrinkDef.
## It tilts around its spout lip (this node's origin), counting from the angle
## it is held at (DrinkDef.pourer_rest_deg; its shapes are authored upright).
## Pouring is pure geometry: the liquid surface stays (almost) level in the
## world while the pourer rotates, and whatever volume no longer fits below
## the line through the spout lip leaves through the spout. Volumes are areas
## in px², the same unit the glass uses. It arrives by sliding in from the
## right (arrive()); a bottle arrives corked and can't pour until the cork
## pops. When it runs dry it refills over GameState.stats.refill_time: a
## pitcher fills in place, an empty bottle is replaced by a new one that gets
## uncorked. Input is ignored while it is busy (is_busy()).

## The pourer vanished (an empty bottle being replaced); `at` = its centre (global).
signal vanished(at: Vector2)
## An arrival stopped sliding; `at` = the corner it tips over (global).
signal landed(at: Vector2)
## The cork popped: where (global), its launch velocity, and the spray colour.
signal popped(at: Vector2, velocity: Vector2, spray: Color)

## Excess below this is treated as "not pouring" so the stream can end cleanly.
const MIN_EXCESS := 0.5
## Below this share of full_volume the pourer counts as empty and refills.
const EMPTY_SHARE := 0.01
## Where an arriving pourer's spout lip starts: fully off-screen right.
const OFFSCREEN_X := 680.0
## A bottle arriving on a drink change or at round start pops its cork this
## long after it lands.
const POP_TIME := 0.15
## The shortest uncork in a bottle refill, however low refill_time goes.
const MIN_UNCORK := 0.1
## The refill uncork wiggle: the angle (°) it builds up to by the pop, and its speed (rad/s).
const WIGGLE_DEG := 4.0
const WIGGLE_FREQ := 45.0
## How fast the popped cork leaves the neck (px/s).
const CORK_SPEED := 160.0

var def: DrinkDef
var interior := PackedVector2Array()
## Interior area (px²).
var capacity := 0.0
## What "full" holds: capacity × def.pourer_full_fraction.
var full_volume := 0.0
## Where the spout lip rests (in Main's space).
var home := Vector2.ZERO

var tilt := 0.0
var tilt_vel := 0.0
var slosh := 0.0
var slosh_vel := 0.0
var volume := 0.0
var flow := 0.0
var excess := 0.0
var exit_speed := 0.0
var refilling := false
## A bottle that hasn't been uncorked yet; it can't pour.
var corked := false

var _refill_t := -1.0  # < 0 while still swinging back upright
var _refill_from := 0.0
var _surf_angle := 0.0
var _surf_point := Vector2.ZERO
var _arrive_t := -1.0  # < 0 when not arriving (covers the slide, the wobble and the uncork)
var _uncork_time := 0.0
var _wiggle := false
var _pivot := Vector2.ZERO

@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front


func _ready() -> void:
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front


func setup(d: DrinkDef) -> void:
	def = d
	interior = d.pourer_interior
	capacity = poly_area(interior)
	full_volume = capacity * d.pourer_full_fraction
	var box := _bounds(interior)
	var mat := _liquid.material as ShaderMaterial
	mat.set_shader_parameter("tint", d.liquid_color)
	mat.set_shader_parameter("center_x", box.get_center().x)
	mat.set_shader_parameter("half_width", box.size.x * 0.5)
	mat.set_shader_parameter("surface_y", 0.0)
	mat.set_shader_parameter("highlight_x", box.position.x + 4.0)
	reset()


## At its rest angle, still, not refilling or arriving, holding `fill` × full_volume.
func reset(fill := 1.0) -> void:
	tilt = 0.0
	tilt_vel = 0.0
	slosh = 0.0
	slosh_vel = 0.0
	volume = full_volume * fill
	flow = 0.0
	excess = 0.0
	refilling = false
	corked = false
	_refill_t = -1.0
	_arrive_t = -1.0
	rotation = -_rest()
	_apply_lean(0.0)
	_update_surface()


## Sets the pourer up for `d` (full; corked if it's a bottle), puts it
## off-screen right and starts sliding it to `at`. A bottle pops its cork
## POP_TIME after it lands. Input is ignored until it's ready.
func arrive(d: DrinkDef, at: Vector2) -> void:
	setup(d)
	home = at
	_start_arrival(POP_TIME, false)


## Puts the pourer at `at` at once, ready to pour — for the sweep and checks.
func place(at: Vector2) -> void:
	home = at
	position = at
	corked = false
	_arrive_t = -1.0
	_apply_lean(0.0)


## True while sliding in; the wobble and the uncork after it don't count.
func is_arriving() -> bool:
	return _arrive_t >= 0.0 and _arrive_t < Arrival.ARRIVE_TIME


## True while it can't pour: arriving, corked or refilling. DOWN is ignored
## and Main won't serve.
func is_busy() -> bool:
	return refilling or corked or is_arriving()


func center_global() -> Vector2:
	return to_global(_bounds(def.pourer_outer).get_center())


## Advances one physics tick. Returns the volume that left the spout this tick.
func step(dt: float, hold: bool) -> float:
	if not refilling and volume < full_volume * EMPTY_SHARE:
		refilling = true
		_refill_t = -1.0
	_step_arrival(dt)
	if is_busy():
		hold = false
	var prev_vel := tilt_vel
	var acc: float
	if hold:
		var speed := def.pour_tilt_speed_deg if excess > 0.0 else def.tilt_speed_deg
		acc = (deg_to_rad(speed * GameState.stats.pour_speed_mult) - tilt_vel) * def.tilt_response
	else:
		acc = -def.return_force - def.return_damp * tilt_vel
	tilt_vel += acc * dt
	tilt += tilt_vel * dt
	var max_tilt := deg_to_rad(def.max_tilt_deg)
	if tilt < 0.0:
		tilt = 0.0
		# Clunk back onto the table; small speeds just settle.
		tilt_vel = -tilt_vel * def.rest_bounce if tilt_vel < -0.2 else 0.0
	elif tilt > max_tilt:
		tilt = max_tilt
		tilt_vel = minf(tilt_vel, 0.0)
	rotation = -(_rest() + tilt)

	var tilt_acc := (tilt_vel - prev_vel) / dt
	slosh_vel += (-def.slosh_spring * slosh - def.slosh_damp * slosh_vel - def.slosh_gain * tilt_acc) * dt
	slosh = clampf(slosh + slosh_vel * dt, -def.slosh_max, def.slosh_max)

	if refilling:
		_step_refill(dt)

	excess = volume - _area_below(Vector2.ZERO, _local_surface_angle())
	var out := 0.0
	if excess > MIN_EXCESS:
		exit_speed = def.stream_speed_min + def.stream_speed_k * sqrt(excess)
		out = minf(excess * (1.0 - exp(-def.pour_rate * dt)), def.max_flow * dt)
		volume -= out
	flow = out / dt
	_update_surface()
	return out


func _step_refill(dt: float) -> void:
	var bottle := def.refill_style == DrinkDef.RefillStyle.NEW_BOTTLE
	if _refill_t < 0.0:
		if tilt > 0.0 or tilt_vel != 0.0:
			return  # still swinging back upright
		_refill_t = 0.0
		_refill_from = volume
		if bottle:
			# You don't refill a bottle: this one goes, a new corked one comes and is uncorked.
			vanished.emit(center_global())
			volume = full_volume
			_start_arrival(maxf(GameState.stats.refill_time - Arrival.ARRIVE_TIME, MIN_UNCORK), true)
			return
	if bottle:
		if not corked:
			refilling = false  # the cork just popped
		return
	_refill_t += dt
	var duration: float = GameState.stats.refill_time
	var t := clampf(_refill_t / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	volume = lerpf(_refill_from, full_volume, t)
	if t >= 1.0:
		refilling = false


func _start_arrival(uncork_time: float, wiggle: bool) -> void:
	position = Vector2(OFFSCREEN_X, home.y)
	_arrive_t = 0.0
	_uncork_time = uncork_time
	_wiggle = wiggle
	corked = def.refill_style == DrinkDef.RefillStyle.NEW_BOTTLE
	_pivot = Arrival.pivot(def.pourer_outer, -_rest(), -1.0)
	_apply_lean(0.0)


func _step_arrival(dt: float) -> void:
	if _arrive_t < 0.0:
		return
	var was_sliding := is_arriving()
	_arrive_t += dt
	position.x = home.x + Arrival.offset(_arrive_t, OFFSCREEN_X - home.x)
	if was_sliding and not is_arriving():
		landed.emit(to_global(_pivot))
	var angle := Arrival.lean(_arrive_t, -1.0)
	if corked:
		var uncorking := _arrive_t - Arrival.ARRIVE_TIME
		if _wiggle and uncorking > 0.0:
			angle += deg_to_rad(WIGGLE_DEG) * (uncorking / _uncork_time) * sin(uncorking * WIGGLE_FREQ)
		if uncorking >= _uncork_time - 1e-6:
			corked = false
			var m := _mouth()
			popped.emit(to_global(Vector2(m.x + m.y * 0.5, -2.0)), Vector2(0.0, -CORK_SPEED).rotated(rotation), def.liquid_highlight)
	_apply_lean(angle)
	if not corked and Arrival.done(_arrive_t):
		_arrive_t = -1.0
		_apply_lean(0.0)


## Turns the drawing (not the node: tilt, the spout and the stream don't see
## it) by `angle` about the arrival pivot.
func _apply_lean(angle: float) -> void:
	for layer: Node2D in [_liquid, _front]:
		layer.rotation = angle
		layer.position = _pivot - _pivot.rotated(angle)


## The rest angle (radians); tilt counts from it.
func _rest() -> float:
	return deg_to_rad(def.pourer_rest_deg) if def != null else 0.0


## The interior's top edge — a bottle's mouth — as x = left, y = width.
func _mouth() -> Vector2:
	var top := INF
	for p in interior:
		top = minf(top, p.y)
	var lo := INF
	var hi := -INF
	for p in interior:
		if p.y - top < 0.5:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return Vector2(lo, hi - lo)


func exit_velocity() -> Vector2:
	return def.spout_dir.normalized().rotated(rotation) * exit_speed


func is_pouring() -> bool:
	return flow > 0.0


func at_rest() -> bool:
	return tilt <= 0.0001 and absf(tilt_vel) < 0.01 and not is_pouring()


## Surface angle in local space: world-level (rotated back by rest + tilt) plus slosh.
func _local_surface_angle() -> float:
	return _rest() + tilt + slosh
```

Then copy these functions **unchanged** from the current `pourer.gd` (they follow `_local_surface_angle` in the old file): `_update_surface`, `_liquid_shape`, `_area_below`, `poly_area`, `_bounds`, `_highlight_segment`, `_draw_liquid`. Finally replace `_draw_front` with:

```gdscript
func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	var outer := def.pourer_outer
	var g := def.pourer_glass_color
	ci.draw_colored_polygon(outer, g)
	for wall in DrawLayer.wall_polygons(outer, interior):
		ci.draw_colored_polygon(wall, Color(g, minf(g.a * 3.0, 1.0)))
	# Liquid surface sparkle.
	if volume >= 1.0:
		var u := Vector2.from_angle(_surf_angle)
		var line := PackedVector2Array([_surf_point - u * 200.0, _surf_point + u * 200.0])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, interior):
			ci.draw_polyline(seg, Color(Palette.WHITE, 0.55))
	DrawLayer.draw_outline(ci, outer, Color(g, 1.0), Color(g, 0.45))
	DrawLayer.draw_outline(ci, interior, Color(Palette.MIST, 0.6), Color(0, 0, 0, 0))
	if def.pourer_handle.size() >= 2:
		ci.draw_polyline(def.pourer_handle, Color(Palette.FROST, 0.9), 3.0)
		ci.draw_polyline(def.pourer_handle, Color(Palette.MIST, 0.8))
	var hl := _highlight_segment()
	if hl.size() == 2:
		ci.draw_line(hl[0], hl[1], Color(Palette.WHITE, 0.5))
	# Glint on the outer vertex nearest the spout lip.
	var lip := outer[0]
	for p in outer:
		if p.length() < lip.length():
			lip = p
	ci.draw_rect(Rect2(lip.floor(), Vector2.ONE), Palette.WHITE)
	if corked:
		var m := _mouth()
		ci.draw_rect(Rect2(m.x + 1.0, -3.0, m.y - 2.0, 5.0), Palette.CLAY)
		ci.draw_rect(Rect2(m.x + 1.0, -3.0, m.y - 2.0, 1.0), Palette.TAN)
```

(For the pitcher `pourer_glass_color` defaults to `Color(Palette.FROST, 0.1)`, so its body 0.10, walls 0.30 and FROST outlines are exactly what it drew before.)

- [ ] **Step 5: Run the checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: eight OK lines.

- [ ] **Step 6: Verify the water sweep didn't change**

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -- --sweep 2>&1 | grep -v '^Godot Engine' > .superpowers/sweep_water_after.txt; diff .superpowers/sweep_water_before.txt .superpowers/sweep_water_after.txt && echo SAME
```

Expected: `SAME`.

- [ ] **Step 7: Commit**

```bash
git add pourer.gd tools/checks/check_pourer.gd
git commit -m "$(cat <<'EOF'
feat: held pourers, pourer arrivals, cork and the new-bottle refill

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Effects node and the unlock banner text

**Files:**
- Create: `effects.gd`
- Modify: `hud.gd`, `tools/checks/check_ui.gd`

**Interfaces:**
- Consumes: `DrinkDef.display_name`, `GameState.ROUND_UNLOCKS` (Task 1).
- Produces: `class_name Effects extends Node2D` with `const MAX_BITS := 120`, `func puff(at: Vector2) -> void`, `func dust(at: Vector2) -> void`, `func cork(at: Vector2, velocity: Vector2, spray: Color) -> void` (matches `Pourer.popped`), `func step(dt: float) -> void`, `func count() -> int`. `static func Hud.round_banner(round_number: int, unlocked: DrinkDef) -> String`.

- [ ] **Step 1: Write the failing check** — in `tools/checks/check_ui.gd`, after `eq(Hud.format_mult(9), "x3", "capped at x3")` add:

```gdscript
	eq(Hud.round_banner(1, null), "ROUND 1", "plain round banner")
	eq(Hud.round_banner(2, GameState.ROUND_UNLOCKS[2]), "ROUND 2\nNEW DRINK: WINE", "the unlock banner names the drink")
```

and at the end of `run()` add:

```gdscript

	var fx: Effects = load("res://effects.gd").new()
	add_child(fx)
	fx.puff(Vector2(100, 100))
	expect(fx.count() >= 4 and fx.count() <= 6, "a puff is 4-6 pixels (%d)" % fx.count())
	fx.cork(Vector2(100, 100), Vector2(-100, -100), Palette.WINE_LIGHT)
	fx.dust(Vector2(100, 280))
	for i in 180:
		fx.step(1.0 / 60.0)
	eq(fx.count(), 0, "effects are gone after 3 s")
	for i in 100:
		fx.puff(Vector2(100, 100))
	expect(fx.count() <= Effects.MAX_BITS, "effects are capped (%d)" % fx.count())
```

- [ ] **Step 2: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=ui`
Expected: `check_ui: FAILED` (`round_banner`/`Effects` not found).

- [ ] **Step 3: Create `effects.gd`**

```gdscript
class_name Effects
extends Node2D
## Short-lived pixel effects that outlive what caused them: the puff a
## vanishing glass or pourer leaves, dust where an arrival lands on the
## counter, a popped cork and its spray. Visual only — it uses randf and never
## feeds back into gameplay. Main steps it from tick() so it keeps pace with
## the simulation.

const GRAVITY := 700.0
## The oldest bits are dropped beyond this many.
const MAX_BITS := 120
## Bits fade out over their last this-many seconds.
const FADE := 0.15


class Bit:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var size: Vector2
	var color: Color
	var gravity: float


var _bits: Array[Bit] = []


## A vanishing glass or pourer: 4-6 light pixels bursting out from `at`.
func puff(at: Vector2) -> void:
	for i in randi_range(4, 6):
		var dir := Vector2.from_angle(randf() * TAU)
		_add(at + dir * 4.0, dir * randf_range(30.0, 60.0), randf_range(0.25, 0.4), Vector2.ONE, Palette.WHITE, 0.0)


## Dust where an arrival lands on the counter: 3 sand pixels kicked sideways.
func dust(at: Vector2) -> void:
	for i in 3:
		_add(at + Vector2(randf_range(-3.0, 3.0), -1.0), Vector2(randf_range(-40.0, 40.0), -randf_range(10.0, 30.0)),
			0.3, Vector2.ONE, Palette.SAND, 200.0)


## A popped cork flying off along `velocity`, plus a little spray of `spray` drops.
func cork(at: Vector2, velocity: Vector2, spray: Color) -> void:
	_add(at, velocity, 2.0, Vector2(4, 3), Palette.CLAY, GRAVITY)
	for i in 4:
		_add(at, velocity.rotated(randf_range(-0.6, 0.6)) * randf_range(0.3, 0.6), 0.4, Vector2.ONE, spray, GRAVITY)


func count() -> int:
	return _bits.size()


func step(dt: float) -> void:
	var alive: Array[Bit] = []
	for b in _bits:
		b.life -= dt
		b.vel.y += b.gravity * dt
		b.pos += b.vel * dt
		if b.life > 0.0 and b.pos.y < 400.0:
			alive.append(b)
	_bits = alive
	queue_redraw()


func _add(pos: Vector2, vel: Vector2, life: float, size: Vector2, color: Color, gravity: float) -> void:
	var b := Bit.new()
	b.pos = pos
	b.vel = vel
	b.life = life
	b.size = size
	b.color = color
	b.gravity = gravity
	_bits.append(b)
	if _bits.size() > MAX_BITS:
		_bits.pop_front()


func _draw() -> void:
	for b in _bits:
		var c := b.color
		c.a *= clampf(b.life / FADE, 0.0, 1.0)
		draw_rect(Rect2(b.pos.floor(), b.size), c)
```

- [ ] **Step 4: Add the banner text helper** — in `hud.gd`, after `format_mult`:

```gdscript
## The INTRO banner: "ROUND N", plus a second line naming a drink unlocked this round.
static func round_banner(round_number: int, unlocked: DrinkDef) -> String:
	var text := "ROUND %d" % round_number
	if unlocked != null:
		text += "\nNEW DRINK: %s" % unlocked.display_name.to_upper()
	return text
```

- [ ] **Step 5: Import and run the checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import && "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: eight OK lines.

- [ ] **Step 6: Commit**

```bash
git add effects.gd effects.gd.uid hud.gd tools/checks/check_ui.gd
git commit -m "$(cat <<'EOF'
feat: visual Effects (puff, dust, cork) and the unlock banner text

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Mixed rounds in Main — drink picks, arrivals, last-call fixes, sweep, autopilot

**Files:**
- Modify: `main.gd` (full replacement below), `main.tscn`, `autopilot.gd`
- Modify: `tools/checks/check_round.gd` (full replacement below), `tools/checks/check_bubbles.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `Main` without `OFFSCREEN_X`/`SWAP_OUT_TIME`/`SWAP_IN_TIME`/`_swap_*`; new `const SUMMARY_DELAY := 0.35`, `@onready var effects: Effects`, `var _force_next: DrinkDef`, `func _pick_drink() -> DrinkDef`; `is_swapping()` = glass or pourer arriving; `results` entries carry `"drink"` (StringName id); `request_serve()` refuses while `pourer.is_busy()`; LAST_CALL idle waits while `pourer.is_busy()`; dev flag `--seed=N`; `--sweep=<id>` loads `res://drinks/<id>.tres`. `Autopilot.release_at: Dictionary` keyed by drink id.

- [ ] **Step 1: Write the failing round check** — replace `tools/checks/check_round.gd` with:

```gdscript
extends CheckBase
## Plays rounds headless at full simulation speed and checks the round rules
## from the slice 1 and slice 2 specs (phases, last call, auto-serve, refill,
## resets, arrivals, drink picks). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round

const DT := 1.0 / 60.0
var main: Main


func run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	_intro_ignores_input_and_arrivals_land()
	_full_round_with_autopilot()
	_last_call_auto_serve()
	_last_call_held_down_while_refilling_does_not_serve()
	_last_call_waits_for_a_refill()
	_last_call_tiny_pour_still_ends()
	_time_up_untouched_glass()
	_time_up_mid_swap()
	_empty_serve_ignored()
	_space_ignored_during_swap_and_refill()
	_next_round_resets_and_reads_stats()
	_round_two_unlocks_wine()
	_picks_follow_the_seed()
	_drink_change_swaps_the_pourer()
	_mixed_round_with_autopilot()


func _fresh(round_number := 1, seed_value := 1) -> void:
	GameState.reset_session(seed_value)
	GameState.round_number = round_number
	main.start_round()


func _run(seconds: float, hold := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		main.tick(DT, hold)
		t += DT


func _to_playing() -> void:
	_fresh()
	_run(Main.INTRO_TIME + DT)


## Lets the autopilot play until a serve starts (the next glass begins to arrive).
func _pour_until_swap() -> void:
	var pilot := Autopilot.new()
	var t := 0.0
	while not main.is_swapping() and t < 15.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	expect(main.is_swapping(), "the autopilot served a glass")


## Puts a glass at the target in, queues a serve with `next` as the next
## drink and lets it fire this tick.
func _serve_with_next(next: DrinkDef, hold := false) -> void:
	main._force_next = next
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.request_serve()
	main.tick(DT, hold)
	expect(main.glass.is_arriving(), "the serve fired and the next glass is arriving")


func _intro_ignores_input_and_arrivals_land() -> void:
	_fresh()
	expect(main.phase == Main.Phase.INTRO, "a round starts in INTRO")
	expect(main.glass.is_arriving() and main.pourer.is_arriving(), "the first glass and pourer arrive during INTRO")
	_run(1.0, true)
	expect(main.phase == Main.Phase.INTRO and main.pourer.tilt == 0.0, "DOWN is ignored during INTRO")
	expect(main.glass.position == Main.GLASS_POS and main.pourer.position == Main.GLASS_POS + main.drink.pourer_offset,
		"they have arrived by then")
	expect(is_equal_approx(main.time_left, 30.0), "the timer doesn't run during INTRO")
	_run(0.6, true)
	expect(main.phase == Main.Phase.PLAYING, "INTRO lasts 1.5 s")
	expect(main.time_left < 30.0 and main.time_left > 29.8, "the timer runs while PLAYING (%.2f)" % main.time_left)


func _full_round_with_autopilot() -> void:
	_fresh()
	var pilot := Autopilot.new()
	var coins_before: int = GameState.coins
	var served_at_time_up := -1
	var saw_refill := false
	var refill_done := false
	var refill_rest_ticks := 0
	var t := 0.0
	while main.phase != Main.Phase.SUMMARY and t < 60.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		if main.pourer.refilling:
			saw_refill = true
			if not refill_done and main.pourer.tilt == 0.0 and main.pourer.tilt_vel == 0.0:
				refill_rest_ticks += 1
		elif saw_refill:
			refill_done = true
		if served_at_time_up < 0 and main.time_left <= 0.0:
			served_at_time_up = main.results.size()
		t += DT
	expect(main.phase == Main.Phase.SUMMARY, "the round reaches SUMMARY")
	expect(main.results.size() >= 4, "the autopilot serves at least 4 glasses (served %d)" % main.results.size())
	expect(main.results.size() - served_at_time_up <= 1, "at most one glass is served after 0:00")
	var total := 0
	var only_water := true
	for r in main.results:
		total += r.coins
		only_water = only_water and r.drink == &"water"
	expect(only_water, "round 1 serves only water")
	expect(total == main.round_stats.coins, "round coins equal the sum of paid glasses")
	expect(GameState.coins - coins_before == total, "GameState.coins grew by the round's coins")
	expect(main.round_stats.served == main.results.size(), "served count matches the results")
	expect(saw_refill, "the pitcher ran dry and refilled during the round")
	expect(absf(refill_rest_ticks * DT - 1.0) < 0.1, "the refill lasts refill_time once upright (%.2f s)" % (refill_rest_ticks * DT))
	expect(main.summary.visible, "the summary is shown")


func _last_call_auto_serve() -> void:
	_to_playing()
	main.time_left = 1.0
	_run(1.2, true)  # 0:00 hits while pouring
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 while pouring enters LAST_CALL")
	var t := 0.0
	var idle_from := -1.0  # when nothing was pouring, in the air or held (and no swap)
	var served_at := -1.0
	while main.phase == Main.Phase.LAST_CALL and t < 10.0:
		main.tick(DT, false)
		t += DT
		if idle_from < 0.0 and not main.pourer.is_pouring() and main.stream.is_empty() and not main.is_swapping():
			idle_from = t
		if served_at < 0.0 and main.results.size() == 1:
			served_at = t
	expect(main.results.size() == 1, "the last-call glass is served automatically")
	var idle_for := served_at - idle_from
	expect(idle_from >= 0.0 and idle_for >= 3.0 and idle_for < 3.1, "auto-serve comes 3.0-3.1 s after the idle starts (%.3f s)" % idle_for)
	expect(main.phase == Main.Phase.SUMMARY, "the round ends after the last-call serve")
	expect(t - served_at >= Main.SUMMARY_DELAY - DT, "the summary waits SUMMARY_DELAY after the last serve (%.2f s)" % (t - served_at))
	expect(not main.glass.visible, "the last glass vanishes and no new glass arrives")
	main.next_round()
	expect(main.glass.visible and main.glass.is_arriving(), "the next round's first glass is visible and arriving")


func _last_call_held_down_while_refilling_does_not_serve() -> void:
	_to_playing()
	_run(1.5, true)
	expect(main.glass.volume > main.glass.capacity * Main.ACTIVE_SHARE, "some liquid is in the glass")
	main.time_left = 0.05
	_run(0.1, true)
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 with an active glass enters LAST_CALL")
	GameState.stats.refill_time = 5.0
	main.pourer.volume = main.pourer.full_volume * 0.001
	var served := main.results.size()
	_run(4.0, true)
	expect(main.pourer.refilling, "the pitcher is still refilling")
	expect(main.phase == Main.Phase.LAST_CALL and main.results.size() == served, "holding DOWN for 4 s blocks the idle auto-serve")
	GameState.stats = GameState.BASE_STATS.duplicate()


func _last_call_waits_for_a_refill() -> void:
	_to_playing()
	_run(1.5, true)
	main.time_left = 0.05
	_run(0.1, true)
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 with an active glass enters LAST_CALL")
	GameState.stats.refill_time = 5.0
	main.pourer.volume = main.pourer.full_volume * 0.001
	var served := main.results.size()
	_run(4.5)  # DOWN released: it swings back and refills for 5 s
	expect(main.pourer.refilling and main.results.size() == served, "the idle auto-serve waits while the pitcher refills")
	_run(6.0)
	expect(main.results.size() == served + 1, "...then serves 3 s after the refill")
	expect(main.phase == Main.Phase.SUMMARY, "...and the round ends")
	GameState.stats = GameState.BASE_STATS.duplicate()


func _last_call_tiny_pour_still_ends() -> void:
	_to_playing()
	main.time_left = 0.05
	# A drop smaller than 1 % of the glass is in the air when time runs out.
	main.stream.emit(main.pourer.global_position, Vector2(-20, 0), 5.0, DT)
	_run(0.1)
	expect(main.phase == Main.Phase.LAST_CALL, "liquid in the air at 0:00 counts as an active glass")
	_run(6.0)
	expect(main.phase == Main.Phase.SUMMARY, "a last call that never reaches 1 % still ends the round")
	expect(main.results.is_empty(), "the under-1 % glass isn't scored")


func _time_up_untouched_glass() -> void:
	_to_playing()
	main.time_left = 0.5
	_run(0.6)
	expect(main.phase == Main.Phase.SUMMARY, "0:00 with an untouched glass goes straight to SUMMARY")
	expect(main.results.is_empty(), "nothing is scored")


func _time_up_mid_swap() -> void:
	_to_playing()
	_pour_until_swap()
	main.time_left = DT * 0.5
	main.tick(DT, false)
	expect(main.phase == Main.Phase.SUMMARY, "0:00 while the next glass arrives ends the round immediately")
	expect(main.results.size() == 1, "only the served glass is scored")


func _empty_serve_ignored() -> void:
	_to_playing()
	main.streak_steps = 2
	main.request_serve()
	_run(0.5)
	expect(main.results.is_empty() and not main.is_swapping(), "serving an empty glass is ignored")
	expect(main.streak_steps == 2, "...and leaves the streak alone")


func _space_ignored_during_swap_and_refill() -> void:
	_to_playing()
	_pour_until_swap()
	var served := main.results.size()
	var filled := false
	while main.is_swapping():
		main.request_serve()  # mashing Space
		main.tick(DT, false)
		if not filled:
			# Put water in the arriving glass so a wrongly queued serve would score.
			filled = true
			main.glass.receive(Main.GLASS_POS.x, 500.0, 0.0)
	expect(filled, "the arriving glass was filled")
	_run(0.5)
	expect(main.results.size() == served, "Space mashed while the next glass arrives doesn't serve it")
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.tick(DT, false)
	expect(main.pourer.refilling, "a dry pitcher refills")
	main.request_serve()
	_run(0.2)
	expect(main.results.size() == served, "Space is ignored while refilling")


func _next_round_resets_and_reads_stats() -> void:
	_to_playing()
	_pour_until_swap()  # one glass served: results and a drained pourer
	_run(1.0)
	expect(main.results.size() == 1, "one glass was served before the round ends")
	expect(main.pourer.volume < main.pourer.full_volume, "the pitcher was drained by the serve")
	main.streak_steps = 3
	main.time_left = 0.01
	_run(0.1, true)  # holding DOWN through the end of the round
	expect(main.phase == Main.Phase.SUMMARY, "the round ended")
	_run(1.5, true)
	expect(main.pourer.tilt < 0.001, "DOWN is ignored on the summary (pitcher upright)")
	GameState.stats.round_duration = 10.0
	GameState.stats.good_tol = 0.2
	# Leave the pourer tilted, dry and refilling so only start_round can reset it.
	main.pourer.tilt = 0.6
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.pourer.refilling = true
	var round_before: int = GameState.round_number
	main.next_round()
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "next_round starts the next INTRO")
	expect(main.streak_steps == 0, "streak resets")
	expect(main.results.is_empty(), "results reset")
	expect(is_equal_approx(main.time_left, 10.0), "round_duration is read at round start")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "the pourer starts full")
	expect(main.pourer.tilt == 0.0 and not main.pourer.refilling, "the pourer starts upright and not refilling")
	expect(main.glass.def == main.drink and main.pourer.def == main.drink, "glass and pourer match the round's first drink")
	expect(not main.summary.visible, "the summary is hidden")
	var levels := main.glass.band_levels()
	expect(is_equal_approx(levels.x, roundf(main.glass.level_for(main.glass.target * 1.2))), "band markers follow stats.good_tol")
	GameState.stats = GameState.BASE_STATS.duplicate()


func _round_two_unlocks_wine() -> void:
	_fresh(2, 5)
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	expect(GameState.owned_drinks.has(wine), "round 2 unlocks wine")
	expect(main.drink == wine and main.glass.def == wine and main.pourer.def == wine, "round 2 opens with wine: glass and bottle")
	eq(main.hud.banner_label.text, "ROUND 2\nNEW DRINK: WINE", "the banner names the new drink")
	var seen := {}
	for i in 40:
		seen[main._pick_drink().id] = true
	expect(seen.has(&"water") and seen.has(&"wine"), "after the first glass, picks include both drinks (%s)" % [seen.keys()])
	GameState.round_number = 3
	main.start_round()
	eq(main.hud.banner_label.text, "ROUND 3", "no unlock banner once wine is owned")
	eq(GameState.owned_drinks.size(), 2, "wine isn't added twice")


func _picks_follow_the_seed() -> void:
	var runs: Array = []
	for attempt in 2:
		_fresh(2, 42)
		var ids: Array[StringName] = [main.drink.id]
		for i in 20:
			ids.append(main._pick_drink().id)
		runs.append(ids)
	expect(runs[0] == runs[1], "the same seed picks the same drinks")
	_fresh(2, 43)
	var other: Array[StringName] = [main.drink.id]
	for i in 20:
		other.append(main._pick_drink().id)
	expect(other != runs[0], "a different seed picks differently")


func _drink_change_swaps_the_pourer() -> void:
	_fresh(2, 3)
	_run(Main.INTRO_TIME + DT)
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	expect(main.drink == wine and not main.pourer.is_busy(), "wine is ready to pour")
	main.pourer.volume = main.pourer.full_volume * 0.5
	_serve_with_next(water)
	expect(main.drink == water and main.pourer.def == water and main.pourer.is_arriving(), "a drink change brings the other pourer")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "...full")
	_run(0.5)
	main.pourer.volume = main.pourer.full_volume * 0.6
	_serve_with_next(water)
	expect(not main.pourer.is_arriving(), "the same drink keeps its pourer")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume * 0.6), "...at its level")
	_run(0.5)
	# DOWN held through a drink change: the new bottle ignores it until it's
	# uncorked, then tilts while DOWN is still held.
	_serve_with_next(wine, true)
	var tilted_while_busy := false
	var t := 0.0
	while t < 1.0:
		main.tick(DT, true)
		tilted_while_busy = tilted_while_busy or (main.pourer.is_busy() and main.pourer.tilt > 0.0)
		t += DT
	expect(not tilted_while_busy, "DOWN is ignored while the bottle arrives and is uncorked")
	expect(main.pourer.tilt > 0.0, "...then it tilts with DOWN still held")


func _mixed_round_with_autopilot() -> void:
	_fresh(2, 11)  # a seed that serves both drinks this round
	var pilot := Autopilot.new()
	var t := 0.0
	while main.phase != Main.Phase.SUMMARY and t < 60.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	var count := {}
	for r in main.results:
		count[r.drink] = count.get(r.drink, 0) + 1
	expect(main.phase == Main.Phase.SUMMARY, "the mixed round reaches SUMMARY")
	expect(main.results.size() >= 4, "the autopilot serves at least 4 glasses in a mixed round (%d)" % main.results.size())
	expect(count.has(&"wine") and count.has(&"water"), "round 2 serves both drinks (%s)" % count)
```

- [ ] **Step 2: Update `tools/checks/check_bubbles.gd`** — replace its `run()` with (both drinks, vessels placed at home since rounds now start with arrivals):

```gdscript
func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var glass: Glass = main.glass
	var dt := 1.0 / 60.0
	var checked := 0
	var bad := 0
	var worst := ""
	for d: DrinkDef in [GameState.WATER, GameState.ROUND_UNLOCKS[2]]:
		glass.setup(d)
		glass.place(Main.GLASS_POS)
		main.pourer.setup(d)
		main.pourer.place(Main.GLASS_POS + d.pourer_offset)
		for hold_s in [1.2, 2.0, 2.6, 3.4]:
			main.stream.clear()
			glass.reset()
			main.pourer.reset()
			var t := 0.0
			while t < hold_s + 2.0:
				main._step_sim(dt, t < hold_s)
				for b in glass._bubbles:
					checked += 1
					var px := Vector2(floorf(b.x) + 0.5, floorf(b.y) + 0.5)
					if not Geometry2D.is_point_in_polygon(px, glass.interior):
						bad += 1
						if worst == "":
							worst = "%s hold %.1fs t=%.2fs bubble at (%.1f, %.1f)" % [d.id, hold_s, t, b.x, b.y]
				t += dt
	print("bubbles checked: %d, outside the glass: %d" % [checked, bad])
	expect(checked > 0, "some bubbles were spawned")
	expect(bad == 0, "no bubble outside the glass (first offender: %s)" % worst)
```

- [ ] **Step 3: Run the checks to verify `round` fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: `check_round: FAILED` (e.g. `_pick_drink`/`SUMMARY_DELAY` not found); the others OK.

- [ ] **Step 4: Add the Effects node to `main.tscn`**

Change the header's `load_steps=12` to `load_steps=13`, add after the `9_summary` ext_resource line:

```
[ext_resource type="Script" path="res://effects.gd" id="10_effects"]
```

and insert before `[node name="Hud" type="CanvasLayer" parent="."]`:

```
[node name="Effects" type="Node2D" parent="."]
script = ExtResource("10_effects")

```

- [ ] **Step 5: Replace `main.gd`**

```gdscript
class_name Main
extends Node2D
## The round loop: INTRO → PLAYING → LAST_CALL → SUMMARY, each glass a random
## drink you own (see docs/superpowers/specs/2026-10-15-round-loop-design.md
## and 2026-10-15-second-drink-design.md). Glasses and pourers arrive by
## sliding in. All round logic advances only in tick(dt, hold), so check
## scripts can fast-forward it headless (`manual = true`); tweens are used for
## HUD visuals only.
##
## Dev flags (after `--`):
##   --sweep[=drink_id]   headless tuning table for that drink (default water), pourer full and half full, then quit
##   --autoplay           the Autopilot plays: pours, serves, starts the next round
##   --seed=N             seed the drink picks so a run repeats
##   --shots=PREFIX       save PREFIX_<nn>.png every --shot-every=S seconds (default 1)
##   --quit=S             quit after S seconds

enum Phase { INTRO, PLAYING, LAST_CALL, SUMMARY }

const GLASS_POS := Vector2(256, 280)
const INTRO_TIME := 1.5
## The last-call glass vanishes this long before the summary appears, so its popup reads.
const SUMMARY_DELAY := 0.35
const LAST_CALL_IDLE := 3.0
## A glass counts as touched once it holds this share of its capacity; less can't be served.
const ACTIVE_SHARE := 0.01
const POPUP_POS := Vector2(256, 168)
const STREAK_POS := Vector2(184, 196)
const AUTOPLAY_SUMMARY_WAIT := 1.5
const HINT := "HOLD DOWN: POUR   SPACE: SERVE   F1: DEBUG"

@onready var glass: Glass = $Glass
@onready var pourer: Pourer = $Pourer
@onready var stream: Stream = $Stream
@onready var effects: Effects = $Effects
@onready var hud: Hud = $Hud
@onready var summary: RoundSummary = $RoundSummary

## When true, _physics_process does nothing and a check script drives tick().
var manual := false
var phase := Phase.INTRO
var phase_time := 0.0
var time_left := 0.0
## The current glass's drink; the pourer always matches it.
var drink: DrinkDef
var streak_steps := 0
## This round's tallies: served, perfects, best_steps, coins.
var round_stats := {}
## Every glass scored this round (Scoring.score results plus "drink", its id).
var results: Array[Dictionary] = []

var _serve_queued := false
var _summary_in := -1.0  # >= 0 while the last-call glass's puff plays before the summary
var _force_next: DrinkDef  # the next glass's drink when it isn't random (a just-unlocked drink)
var _idle := 0.0
var _autopilot: Autopilot
var _clock := 0.0
var _quit_at := INF
var _shot_prefix := ""
var _shot_every := 1.0
var _next_shot := 0.0
var _shot_index := 0


func _ready() -> void:
	hud.place_streak(STREAK_POS)
	summary.next_pressed.connect(next_round)
	glass.landed.connect(_on_landed)
	pourer.landed.connect(_on_landed)
	pourer.vanished.connect(effects.puff)
	pourer.popped.connect(effects.cork)
	var args := _parse_args()
	if args.has("seed"):
		GameState.rng.seed = int(args["seed"])
	if args.has("sweep"):
		_sweep(args["sweep"])
		get_tree().quit()
		return
	if args.has("autoplay"):
		_autopilot = Autopilot.new()
	_shot_prefix = args.get("shots", "")
	_shot_every = float(args.get("shot-every", "1.0"))
	if args.has("quit"):
		_quit_at = float(args["quit"])
	start_round()


func _parse_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	return args


func start_round() -> void:
	phase = Phase.INTRO
	phase_time = 0.0
	time_left = GameState.stats.round_duration
	streak_steps = 0
	round_stats = {"served": 0, "perfects": 0, "best_steps": 0, "coins": 0}
	results.clear()
	_serve_queued = false
	_summary_in = -1.0
	_idle = 0.0
	stream.clear()
	var unlocked := GameState.unlock_for_round(GameState.round_number)
	_force_next = unlocked
	drink = _pick_drink()
	stream.set_drink(drink)
	glass.arrive(drink, GLASS_POS)
	pourer.arrive(drink, GLASS_POS + drink.pourer_offset)
	summary.hide_results()
	hud.show_banner(Hud.round_banner(GameState.round_number, unlocked), INTRO_TIME)
	_refresh_hud()


func next_round() -> void:
	if phase != Phase.SUMMARY:
		return
	GameState.round_number += 1
	start_round()


## The next glass's drink: a just-unlocked drink first, otherwise any owned drink.
func _pick_drink() -> DrinkDef:
	if _force_next != null:
		var d := _force_next
		_force_next = null
		return d
	var owned := GameState.owned_drinks
	return owned[GameState.rng.randi_range(0, owned.size() - 1)]


func is_swapping() -> bool:
	return glass.is_arriving() or pourer.is_arriving()


func is_serving_phase() -> bool:
	return phase == Phase.PLAYING or phase == Phase.LAST_CALL


func request_serve() -> void:
	if not is_serving_phase() or is_swapping() or pourer.is_busy():
		return
	_serve_queued = true


func _physics_process(dt: float) -> void:
	if manual:
		return
	_clock += dt
	var hold := Input.is_physical_key_pressed(KEY_DOWN)
	if _autopilot != null:
		var d := _autopilot.decide(self)
		hold = d.hold
		if d.serve:
			request_serve()
		if phase == Phase.SUMMARY and phase_time >= AUTOPLAY_SUMMARY_WAIT:
			next_round()
	tick(dt, hold)
	if _clock >= _quit_at:
		get_tree().quit()


func _process(_dt: float) -> void:
	if _shot_prefix != "" and _clock >= _next_shot:
		_next_shot += _shot_every
		_shot_index += 1
		var path := "%s_%02d.png" % [_shot_prefix, _shot_index]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)


## One fixed step of the whole game. `hold` = DOWN is held this tick.
func tick(dt: float, hold: bool) -> void:
	phase_time += dt
	if phase == Phase.INTRO or phase == Phase.SUMMARY:
		hold = false
	if phase == Phase.INTRO and phase_time >= INTRO_TIME:
		_enter(Phase.PLAYING)
	_step_sim(dt, hold)
	effects.step(dt)
	if _summary_in >= 0.0:
		_summary_in -= dt
		if _summary_in <= 0.0:
			_summary_in = -1.0
			_finish_round()
		_refresh_hud()
		return
	if phase == Phase.PLAYING:
		time_left = maxf(time_left - dt, 0.0)
		if time_left <= 0.0:
			_on_time_up()
	if _serve_queued and not is_swapping() and not pourer.is_pouring() and stream.is_empty():
		_serve()
	if phase == Phase.LAST_CALL and not is_swapping():
		if hold or pourer.is_pouring() or pourer.is_busy() or not stream.is_empty():
			_idle = 0.0
		else:
			_idle += dt
			if _idle >= LAST_CALL_IDLE:
				_idle = 0.0
				_serve_queued = true
	_refresh_hud()


func _step_sim(dt: float, hold: bool) -> void:
	var out := pourer.step(dt, hold)
	if out > 0.0:
		stream.emit(pourer.global_position, pourer.exit_velocity(), out, dt)
	stream.step(dt, glass)
	glass.step(dt)


func _enter(p: Phase) -> void:
	phase = p
	phase_time = 0.0


func _glass_active() -> bool:
	return glass.volume >= glass.capacity * ACTIVE_SHARE or not stream.is_empty() or pourer.is_pouring()


func _on_time_up() -> void:
	if not is_swapping() and _glass_active():
		_enter(Phase.LAST_CALL)
		_idle = 0.0
		hud.show_banner("LAST CALL!", 1.5)
	else:
		_finish_round()


## Scores the glass; it vanishes and (unless it's last call) the next glass
## arrives — with the other pourer when the drink changes.
func _serve() -> void:
	_serve_queued = false
	if glass.volume < glass.capacity * ACTIVE_SHARE:
		if phase == Phase.LAST_CALL:
			_finish_round()
		return
	var r := Scoring.score(glass.volume, glass.target, glass.spilled > 0.5, streak_steps, drink, GameState.stats)
	r["drink"] = drink.id
	streak_steps = r.steps
	results.append(r)
	round_stats.served += 1
	if r.band == Scoring.PERFECT:
		round_stats.perfects += 1
	round_stats.best_steps = maxi(round_stats.best_steps, streak_steps)
	round_stats.coins += r.coins
	GameState.coins += r.coins
	hud.popup(r, POPUP_POS)
	effects.puff(glass.center_global())
	if phase == Phase.LAST_CALL:
		glass.vanish()
		_summary_in = SUMMARY_DELAY
		return
	var next := _pick_drink()
	if next != drink:
		effects.puff(pourer.center_global())
		pourer.arrive(next, GLASS_POS + next.pourer_offset)
		stream.set_drink(next)
	drink = next
	glass.arrive(drink, GLASS_POS)


## Dust only where an arrival lands on the counter (a held bottle lands in mid-air).
func _on_landed(at: Vector2) -> void:
	if at.y >= GLASS_POS.y - 1.0:
		effects.dust(at)


func _finish_round() -> void:
	_enter(Phase.SUMMARY)
	_serve_queued = false
	summary.show_results(GameState.round_number, round_stats, GameState.coins)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			request_serve()
		KEY_F1:
			hud.toggle_debug()
		KEY_ESCAPE:
			get_tree().quit()


func _refresh_hud() -> void:
	hud.set_time(time_left)
	hud.set_coins(GameState.coins)
	hud.set_streak(streak_steps)
	var hint := HINT
	if _serve_queued:
		hint = "SERVING..."
	elif pourer.refilling:
		hint = "REFILLING..."
	hud.set_hint(hint)
	if hud.is_debug_visible():
		var err := (glass.volume - glass.target) / glass.target * 100.0
		hud.set_debug("TILT %3d  FLOW %4d\nJUG  %4d/%d\nGLASS %4d/%d  %+.1f%%\nIN AIR %d  PHASE %s" % [
			roundi(rad_to_deg(pourer.tilt)), roundi(pourer.flow),
			roundi(pourer.volume), roundi(pourer.full_volume),
			roundi(glass.volume), roundi(glass.target), err,
			stream.parcel_count(), Phase.keys()[phase],
		])


## Simulates holds of increasing length — with the pourer full, then half
## full — and prints how much ends up in the glass, how far from the line,
## how much arrived after DOWN was released (the overshoot), and settle time.
func _sweep(drink_id: String) -> void:
	var dt := 1.0 / 60.0
	var d: DrinkDef = GameState.WATER
	if drink_id != "":
		var path := "res://drinks/%s.tres" % drink_id
		if not ResourceLoader.exists(path):
			printerr("no drink %s" % path)
			return
		d = load(path)
	glass.setup(d)
	glass.place(GLASS_POS)
	pourer.setup(d)
	pourer.place(GLASS_POS + d.pourer_offset)
	stream.set_drink(d)
	print("%s: glass %d px², line at %d px², pourer full %d px² (%.2f glasses)" % [
		d.id, glass.capacity, glass.target, pourer.full_volume, pourer.full_volume / glass.target,
	])
	for fill in [1.0, 0.5]:
		print("-- pourer starts %d%% full --" % roundi(fill * 100.0))
		print("hold_s  release_deg  peak_deg  fill%  vs_line%  after_release%  settle_s  spilled")
		var h := 0.6
		while h <= 4.61:
			stream.clear()
			glass.reset()
			pourer.reset(fill)
			var t := 0.0
			var peak := 0.0
			var at_release := -1.0
			var release_tilt := 0.0
			while t < 15.0:
				var hold := t < h
				if not hold and at_release < 0.0:
					at_release = glass.volume
					release_tilt = pourer.tilt
				_step_sim(dt, hold)
				peak = maxf(peak, pourer.tilt)
				t += dt
				if t > h and pourer.at_rest() and stream.is_empty():
					break
			print("%5.2f  %11d  %8d  %5.1f  %8.1f  %14.1f  %8.2f  %7d" % [
				h, roundi(rad_to_deg(release_tilt)), roundi(rad_to_deg(peak)),
				glass.volume / glass.capacity * 100.0, (glass.volume - glass.target) / glass.target * 100.0,
				(glass.volume - at_release) / glass.capacity * 100.0, t - h, roundi(glass.spilled + stream.spilled),
			])
			h += 0.2
```

(Compared with the old file: the swap constants/state and `_step_swap` are gone; `_ready` no longer sets up the glass and pourer — `start_round` makes them arrive; the sweep loads the drink by id and places both vessels.)

- [ ] **Step 6: Make the autopilot per-drink and busy-aware** — replace `autopilot.gd` with:

```gdscript
class_name Autopilot
extends RefCounted
## A simple scripted player for --autoplay and tools/checks/check_round.gd: pours
## until the glass (plus liquid in the air) nears the line, releases early to
## allow for the overshoot, then serves once everything has landed.

## Release DOWN when this share of the target is in the glass or the air, per
## drink id — the lower the line, the bigger the overshoot's share of the target.
var release_at := {&"water": 0.86, &"wine": 0.75}
var _released := false


func decide(main: Main) -> Dictionary:
	var out := {"hold": false, "serve": false}
	if not main.is_serving_phase() or main.is_swapping():
		_released = false
		return out
	if main.pourer.is_busy():
		return out
	var share: float = release_at.get(main.drink.id, 0.86)
	var poured := main.glass.volume + main.stream.in_flight_volume()
	if not _released and poured < main.glass.target * share:
		out.hold = true
	else:
		_released = true
		if main.pourer.at_rest() and main.stream.is_empty():
			out.serve = true
	return out
```

- [ ] **Step 7: Run all checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: eight OK lines (bubbles also prints `outside the glass: 0`). If only `round 2 serves both drinks` fails, seed 11 happened to give a wine-only round: change the seed in `_mixed_round_with_autopilot` to 12, 13, … until both drinks appear (keep the comment). If `the autopilot serves at least 4 glasses in a mixed round` fails, note the count and continue — Task 7 tunes the wine pour and the autopilot.

- [ ] **Step 8: Verify the water sweep is still unchanged, and the wine sweep runs**

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -- --sweep 2>&1 | grep -v '^Godot Engine' > .superpowers/sweep_water_after.txt; diff .superpowers/sweep_water_before.txt .superpowers/sweep_water_after.txt && echo SAME; "$GODOT" --headless --path . -- --sweep=wine 2>&1 | grep -v '^Godot Engine' | head -5
```

Expected: `SAME`, then a header like `wine: glass 3100 px², line at 1643 px², pourer full 4379 px² (2.67 glasses)` and the first table rows.

- [ ] **Step 9: Commit**

```bash
git add main.gd main.tscn autopilot.gd tools/checks/check_round.gd tools/checks/check_bubbles.gd
git commit -m "$(cat <<'EOF'
feat: mixed rounds — seeded drink picks, arrivals on serve and round start, wine from round 2

Glass swap replaced by vanish + arrival; a drink change swaps the pourer
(arriving full). The last-call idle auto-serve waits while the pourer is
busy, and the summary follows the last glass by 0.35 s. --sweep=<id> now
simulates that drink; new --seed=N.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Tune the wine pour and the autopilot, then look at it

**Files:**
- Modify: `drinks/wine.tres` (pour values only — never the shapes), `autopilot.gd`, `tools/checks/check_round.gd`, possibly `main.gd` (`POPUP_POS` only)

**Interfaces:**
- Consumes: `--sweep=wine` (Task 6), `Autopilot.release_at` (Task 6).
- Produces: final wine pour values; `Autopilot.release_at[&"wine"]`; the mixed-round quality assertion.

- [ ] **Step 1: Run both sweeps**

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -- --sweep=wine 2>&1 | grep -v '^Godot Engine' > .superpowers/sweep_wine.txt; cat .superpowers/sweep_wine.txt
```

(The water table is `.superpowers/sweep_water_after.txt`; its full-pourer row nearest the line is `3.00 s` at −1.0 %.)

- [ ] **Step 2: Judge the wine table against the targets** (full-pourer block):
  - **T2 — different habit:** take the row with the smallest |`vs_line%`|. Its `hold_s` must differ from water's 3.00 s by at least 0.7 s.
  - **T4 — no spill:** `spilled` must be 0 in every row whose `vs_line%` ≤ +10.
  - **Sanity:** the first row with `fill%` > 0 is at `hold_s` ≤ 1.2 (it pours soon after you start holding).

- [ ] **Step 3: Adjust until all three hold** — edit only these `drinks/wine.tres` values, re-running Step 1 after each change:
  - T2 fails with the wine hold *close to* 3.0 s: lower `max_flow` by 250 (not below 750), then if needed lower `pour_tilt_speed_deg` by 2 (not below 7). Both lengthen the hold. If the best row moves past `4.60` (the end of the table), undo the last step.
  - T4 fails: lower `stream_speed_k` by 1 (not below 2); if it still spills, move `pourer_offset.x` 2 px left (not below 6 — the lip must stay over the opening, which `check_drinks` verifies).
  - Sanity fails: raise `tilt_speed_deg` by 10.
  Record the final values and the nearest-line row in the commit message.

- [ ] **Step 4: Set the autopilot's wine release point** — from the final wine table's nearest-line row: `release_at = 1 − (after_release% × 3100) / (100 × 1643)`, rounded to 2 decimals (e.g. `after_release%` 14.0 → `1 − 434 / 1643` = 0.74). Put it in `autopilot.gd`: `var release_at := {&"water": 0.86, &"wine": <value>}`.

- [ ] **Step 5: Add the quality assertion** — at the end of `_mixed_round_with_autopilot` in `tools/checks/check_round.gd`:

```gdscript
	var good := 0
	for r in main.results:
		if r.band == Scoring.PERFECT or r.band == Scoring.GOOD:
			good += 1
	expect(good * 2 >= main.results.size(), "the autopilot lands most glasses GOOD or better (%d of %d)" % [good, main.results.size()])
```

- [ ] **Step 6: Run all checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: eight OK lines. If the new assertion fails, print the wine results' `error` values (temporarily add `print(r.drink, " ", r.band, " ", r.error)` in the loop): mostly positive errors → lower `release_at[&"wine"]` by 0.02; mostly negative → raise it by 0.02; repeat. Remove the print.

- [ ] **Step 7: Look at it** — record a mixed round with screenshots (round 2 starts about 33 s in):

```bash
mkdir -p .superpowers/shots && GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --seed=11 --shots="$PWD/.superpowers/shots/s" --shot-every=0.25 --quit=70 2>&1 | grep -iE "error|warning" | head
```

Expected: no error lines (a triangulation error would mean a broken polygon). Open frames from round 2 (`s_135.png` onward) with the Read tool and confirm:
  - a glass arriving: it slides in from the left, overshoots slightly and leans, with no gap or sinking into the counter;
  - a drink change: the old pourer puffs away, the new one slides in from the right;
  - the wine glass: stem and foot drawn, fill line and GOOD bracket left of the bowl, the bracket clear of the wall;
  - the bottle held at 55° over the glass with green walls and a cork before it pops; the stream lands inside the glass;
  - the popup above the glass readable — if `+15` overlaps the bottle's mouth, change `POPUP_POS` in `main.gd` to `Vector2(256, 148)` and re-check.
  If the bottle never runs dry in the recording, also run `--seed=12` (or longer `--quit`) until a refill with the wiggle and pop is captured.

- [ ] **Step 8: Commit**

Commit with a subject `tune: wine pour and autopilot release from the sweep` and a body that lists every `wine.tres` value you changed (old → new), `release_at[&"wine"]`, and the final full-pourer nearest-line sweep row for wine, ending with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line:

```bash
git add drinks/wine.tres autopilot.gd tools/checks/check_round.gd main.gd
git commit -F .superpowers/tune_msg.txt   # write the message there first
```

(Leave `main.gd` out of `git add` if `POPUP_POS` didn't change.)

---

### Task 8: Docs and final verification

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/superpowers/specs/2026-10-15-second-drink-design.md`

**Interfaces:**
- Consumes: the final sweeps from Task 7.
- Produces: docs that describe slice 2.

- [ ] **Step 1: Update `CLAUDE.md`**
  - **Current state:** replace the slice 1 paragraph's lead with slice 2: "slice 2 (second drink + mixed rounds) is implemented, awaiting playtest" — wine (bottle held at 55° over a big stemmed glass, line at the bowl's widest point, pays 15/12–3) unlocks at round 2 ("NEW DRINK: WINE"), then each glass is a random owned drink (seeded `GameState.rng`); glasses vanish on serve and the next one slides in from the left, a drink change brings the other pourer from the right (full); the pitcher refills in place, an empty bottle is replaced and uncorked. Keep the slice 1 description as the base.
  - **Next slices:** the between-rounds shop (slice 3), noting the open question from the spec: choosing the round's drink mix in the shop so late rounds aren't stuck on cheap water.
  - **Known deferred work:** remove the three fixed items (`--sweep=<id>` relabelling, `_draw_fill_line`'s left tick, the LAST_CALL auto-serve bypassing the refill guard). Keep the rest.
  - **Commands:** add `--seed=N` to the dev flags line; mention `--sweep=wine`; add `arrival` to the checks list.
  - **Architecture:** add `arrival.gd` (pure slide/lean/pivot curves; vessels step them; the lean turns only the `Liquid`/`Front` layers) and `effects.gd` (visual-only puffs, dust, cork; stepped from `tick()`); update the scene order to `Background, Glass (Liquid, Front), Stream, Pourer (Liquid, Front), Effects`; in `DrinkDef`/`GameState` describe `pourer_glass_color`, `pourer_rest_deg`, `refill_style`, `WATER`, `ROUND_UNLOCKS`, `rng`, `reset_session()`, `unlock_for_round()`; in the simulation loop replace the swap description (glass vanishes with a puff, next glass arrives in 0.3 s; `is_swapping()` = an arrival; Space ignored while arriving or while the pourer `is_busy()`; LAST_CALL idle waits while the pourer is busy; summary 0.35 s after the last-call glass); in `pourer.gd` describe the rest angle (`rotation = -(rest + tilt)`), `arrive()`/`place()`, `corked`, both refill styles and the signals; in `glass.gd` describe `arrive()`/`place()`/`vanish()`, `bracket_x()`/`left_tick()`, and that an empty glass doesn't slosh.
  - **Current tuning baseline:** add the wine numbers from `.superpowers/sweep_wine.txt` (where pouring starts, the nearest-line hold and its error, the after-release share, 2.67 glasses per bottle, PERFECT ≈ ±1 row) next to water's.

- [ ] **Step 2: Update `README.md`** — under **Rounds** add a bullet: "From round 2, wine joins water: each glass is randomly water or wine. Wine is poured from a bottle into a big stemmed glass with the line at its widest point (PERFECT 15 coins, GOOD 12→3); an empty bottle is replaced and uncorked." Add `--seed=N` to the dev flags block (`# seed the drink picks`).

- [ ] **Step 3: Mark the spec implemented** — in the spec header replace `Status: Draft — awaiting review` with `Status: Implemented (2026-10-15), awaiting playtest — plan docs/superpowers/plans/2026-10-15-second-drink.md`. If Task 7 changed `POPUP_POS` or any number the spec states, correct the spec to match the code.

- [ ] **Step 4: Final verification**

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import >/dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|outside"; "$GODOT" --headless --path . -- --sweep 2>&1 | grep -v '^Godot Engine' | diff .superpowers/sweep_water_before.txt - && echo WATER-SAME
```

Expected: eight `check_*: OK` lines, `outside the glass: 0`, `WATER-SAME`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md docs/superpowers/specs/2026-10-15-second-drink-design.md
git commit -m "$(cat <<'EOF'
docs: describe slice 2 (wine, mixed rounds, arrivals) and mark the spec implemented

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Hand off for playtest** — use superpowers:finishing-a-development-branch. The user playtests before merging (slice 1 was merged after their verdict).
