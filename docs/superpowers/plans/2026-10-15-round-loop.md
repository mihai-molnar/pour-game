# Slice 1 Round Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the pour prototype into slice 1: 30 s rounds of water pours with a streak multiplier, a pitcher that drains across glasses and refills itself, a last-call ending, a round summary, and drinks defined as `DrinkDef` resources.

**Architecture:** Evolve the prototype in place. Drink data moves into `DrinkDef` resources (`drinks/water.tres`); session state and the upgrade seam (`stats`) live in a `GameState` autoload; scoring is a pure static `Scoring` class; `main.gd` becomes a tick-driven phase machine (INTRO → PLAYING → LAST_CALL → SUMMARY) whose logic only advances in `tick(dt, hold)`, so headless check scripts can fast-forward whole rounds. The simulation order (pourer → stream → glass) is unchanged.

**Tech Stack:** Godot 4.5.1 (GDScript, Forward Plus), headless checks run by `tools/run_check.gd` (no test framework), Python 3 + Pillow for screenshot contact sheets.

**Spec:** `docs/superpowers/specs/2026-10-15-round-loop-design.md`

**Branch:** `feat/round-loop` (merge to `master` when done).

## Global Constraints

- Project root: `/Users/mihai/Godot games/pour-prototype` (or the worktree created for this branch). All paths below are relative to it.
- Every Bash call is a fresh shell: start Godot commands with `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot";` and quote `"$GODOT"` (the path has a space).
- After creating any script with a `class_name`, run `"$GODOT" --headless --path . --import` before running checks, or you'll get "Could not find type" errors from a stale class cache.
- Checks live in `tools/checks/check_<name>.gd`, `extends CheckBase` (Task 1), and do their work in `func run() -> void` using `expect(ok, what)`, `eq(got, want, what)`, `near(got, want, what)`. They run through the runner, which loads them *after* autoloads exist (a `--script` file itself cannot reference `GameState` or any class that uses it — verified on 4.5.1), resets `GameState` before each check, and fails a check if it records a failure **or logs any script error**:
  `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=<name>` (or `--check=all`). Success = a `check_<name>: OK` line per check and exit 0. Always keep `--quit-after` (macOS has no `timeout`).
- Inside checks, instantiate the game with `var main: Node = load("res://main.tscn").instantiate()` then `add_child(main)`; game classes (`Glass`, `Pourer`, `Main`, `Autopilot` …) and `GameState` may be used directly.
- GDScript `const` cannot hold `PackedVector2Array(...)` — use `var` or resource fields.
- Resolution 640×360, `stretch/mode="viewport"`; all coordinates in 640×360 px; counter top y = 280; glass rest position `(256, 280)`.
- Colors only via `Palette.*` in scripts (alpha variants fine); `.tres`/`.tscn` repeat the hex values verbatim. Font Press Start 2P, sizes multiples of 8.
- Gameplay reads tunables from `GameState.stats` at point of use; never hard-code a value that has a stats key. Slice 1 stats: `round_duration = 30.0`, `perfect_tol = 0.03`, `good_tol = 0.10`, `coin_mult = 1.0`, `pour_speed_mult = 1.0`, `refill_time = 1.0`.
- Round logic advances only in `main.tick(dt, hold)`; tweens are for HUD visuals only.
- Spec numbers: water fill line `0.9` of the glass; PERFECT ±3 % → 10 coins; GOOD ±10 % → 8…2 coins; MISS/SPILL 0; streak GOOD +1 / PERFECT +2 steps, ×(1 + 0.5·steps), cap 4 steps (×3), reset on MISS/SPILL/new round; payout uses the multiplier *before* the glass; INTRO 1.5 s; swap out 0.35 s / in 0.5 s; LAST_CALL idle auto-serve 3 s; serves under 1 % of capacity ignored; full pitcher ≈ 2.5 glasses at the line.
- Commit Godot's `.uid` sidecars; never commit `.godot/`. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Mashing Space during a glass swap or a refill** must not queue a serve for the next glass — Task 6 `_space_ignored_during_swap_and_refill`.
2. **Holding DOWN across the round end, through the summary, into the next INTRO** must not tilt or pour, and the next round starts upright with a full pitcher — Task 6 `_intro_ignores_input`, `_next_round_resets_and_reads_stats`.
3. **Liquid still in the air at 0:00 that adds less than 1 %** enters LAST_CALL but must still end the round (auto-serve finds an unservable glass) — Task 6 `_last_call_tiny_pour_still_ends`.
4. **The pitcher running dry while tilted** must swing back upright ignoring DOWN, then refill for `refill_time`; liquid already in the air still lands — Task 4 `check_pourer` refill test, Task 6 `_full_round_with_autopilot`.
5. **Stats changed between rounds** (the upgrade seam: `round_duration`, `good_tol`, `pour_speed_mult`, `refill_time`) take effect without restarting — Task 3 band test, Task 4 `pour_speed_mult`/`refill_time` tests, Task 6 `round_duration` test.

## Task Dependencies

Task 1 first (it also creates the check runner every later task uses). Tasks 2, 3 and 5 only depend on Task 1 (they touch different files apart from a few lines in `main.gd`/`main.tscn`); Task 4 depends on Task 3 (`DrawLayer.draw_outline`). Task 6 depends on all of 1–5. Task 7 is last. The chosen execution is sequential, in order.

---

### Task 1: Check runner, DrinkDef resource, water.tres, GameState autoload

**Files:**
- Create: `tools/run_check.gd`, `tools/checks/check_base.gd`, `tools/checks/check_bubbles.gd` (migrated), `tools/checks/check_drinks.gd`, `drink_def.gd`, `drinks/water.tres`, `game_state.gd`
- Delete: `tools/check_bubbles.gd`, `tools/check_bubbles.gd.uid` (replaced by the migrated check)
- Modify: `project.godot` (add `[autoload]`)

**Interfaces:**
- Consumes: nothing.
- Produces: the check runner (`tools/run_check.gd`, `--check=<name>|all`) and `class_name CheckBase extends Node` with `failures: int`, `run() -> void` (override), `expect(ok: bool, what: String)`, `eq(got: Variant, want: Variant, what: String)`, `near(got: float, want: float, what: String, tolerance := 1e-4)`. `class_name DrinkDef extends Resource` with fields `id: StringName`, `display_name: String`, `liquid_color: Color`, `liquid_highlight: Color`, `glass_interior: PackedVector2Array`, `glass_outer: PackedVector2Array`, `fill_fraction: float`, `perfect_coins: int`, `good_coins_max: int`, `good_coins_min: int`, `pourer_interior/pourer_outer/pourer_handle: PackedVector2Array`, `pourer_full_fraction: float`, `spout_dir: Vector2`, `pourer_offset: Vector2`, `tilt_speed_deg`, `pour_tilt_speed_deg`, `tilt_response`, `return_force`, `return_damp`, `max_tilt_deg`, `rest_bounce`, `pour_rate`, `max_flow`, `stream_speed_min`, `stream_speed_k`, `slosh_spring`, `slosh_damp`, `slosh_gain`, `slosh_max` (all `float`). Autoload `GameState` with `BASE_STATS: Dictionary`, `coins: int`, `round_number: int`, `owned_drinks: Array[DrinkDef]`, `stats: Dictionary`.

- [ ] **Step 1: Create the runner** — `tools/run_check.gd`:

```gdscript
extends SceneTree
## Runs headless checks from res://tools/checks/ once autoloads exist — a
## --script file itself can't reference GameState or any class that uses it.
## Usage (from the project root):
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all
## Prints "check_<name>: OK" per passing check and exits 1 if any failed. A
## check fails if it records a failure or logs any script error. No OK line at
## all means the runner itself crashed — read the error output.

const DIR := "res://tools/checks/"


class ErrorCounter extends Logger:
	var errors := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors += 1


func _process(_delta: float) -> bool:
	var wanted := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--check="):
			wanted = a.trim_prefix("--check=")
	var names: Array[String] = []
	if wanted == "all":
		for file in DirAccess.get_files_at(DIR):
			if file.begins_with("check_") and file.ends_with(".gd") and file != "check_base.gd":
				names.append(file.trim_prefix("check_").trim_suffix(".gd"))
	else:
		names.append(wanted)
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var gs: Node = root.get_node("GameState")
	var failed := 0
	for n in names:
		gs.stats = gs.BASE_STATS.duplicate()
		gs.coins = 0
		gs.round_number = 1
		var errors_before := counter.errors
		var script: Script = load(DIR + "check_%s.gd" % n)
		var check: Node = script.new() if script != null and script.can_instantiate() else null
		if check == null:
			print("check_%s: FAILED (could not load tools/checks/check_%s.gd)" % [n, n])
			failed += 1
			continue
		root.add_child(check)
		check.run()
		var errors := counter.errors - errors_before
		if check.failures == 0 and errors == 0:
			print("check_%s: OK" % n)
		else:
			print("check_%s: FAILED (%d failures, %d script errors)" % [n, check.failures, errors])
			failed += 1
		check.free()
	OS.remove_logger(counter)
	quit(1 if failed > 0 else 0)
	return false
```

- [ ] **Step 2: Create the check base** — `tools/checks/check_base.gd`:

```gdscript
class_name CheckBase
extends Node
## Base for headless checks in res://tools/checks/, run by tools/run_check.gd
## after autoloads exist (so checks may use GameState and typed game classes).
## Override run(); record failures with expect / eq / near.

var failures := 0


func run() -> void:
	pass


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)


func eq(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		failures += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])


func near(got: float, want: float, what: String, tolerance := 1e-4) -> void:
	if absf(got - want) > tolerance:
		failures += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])
```

- [ ] **Step 3: Migrate the bubble check** — create `tools/checks/check_bubbles.gd`, then `git rm tools/check_bubbles.gd tools/check_bubbles.gd.uid`:

```gdscript
extends CheckBase
## Simulates pours and fails if any bubble is ever outside the glass interior.


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var glass: Glass = main.glass
	var dt := 1.0 / 60.0
	var checked := 0
	var bad := 0
	var worst := ""
	for hold_s in [1.2, 2.0, 2.6, 3.4]:
		main.stream.clear()
		glass.reset()
		main.pitcher.reset()
		var t := 0.0
		while t < hold_s + 2.0:
			main._step_sim(dt, t < hold_s)
			for b in glass._bubbles:
				checked += 1
				var px := Vector2(floorf(b.x) + 0.5, floorf(b.y) + 0.5)
				if not Geometry2D.is_point_in_polygon(px, glass.interior):
					bad += 1
					if worst == "":
						worst = "hold %.1fs t=%.2fs bubble at (%.1f, %.1f)" % [hold_s, t, b.x, b.y]
			t += dt
	print("bubbles checked: %d, outside the glass: %d" % [checked, bad])
	expect(checked > 0, "some bubbles were spawned")
	expect(bad == 0, "no bubble outside the glass (first offender: %s)" % worst)
```

- [ ] **Step 4: Prove the runner works on the migrated check**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=bubbles; echo "exit $?"`
Expected: `bubbles checked: N, outside the glass: 0`, `check_bubbles: OK`, `exit 0`.

- [ ] **Step 5: Write the failing drinks check** — `tools/checks/check_drinks.gd`:

```gdscript
extends CheckBase
## Validates every drink in res://drinks/ and the GameState defaults.


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
	var checked := 0
	for file in DirAccess.get_files_at("res://drinks"):
		if file.ends_with(".tres"):
			_check_drink(load("res://drinks/" + file))
			checked += 1
	expect(checked >= 1, "found at least one drink")


func _check_drink(d: DrinkDef) -> void:
	var n := String(d.id)
	expect(d.id != &"", "%s: has an id" % n)
	expect(d.glass_interior.size() >= 3 and d.glass_outer.size() >= 3, "%s: glass polygons" % n)
	expect(d.pourer_interior.size() >= 3 and d.pourer_outer.size() >= 3, "%s: pourer polygons" % n)
	expect(d.pourer_interior.has(Vector2.ZERO), "%s: spout lip (0,0) is a pourer_interior vertex" % n)
	expect(d.fill_fraction > 0.0 and d.fill_fraction <= 1.0, "%s: fill_fraction in (0, 1]" % n)
	expect(d.pourer_full_fraction > 0.0 and d.pourer_full_fraction < 1.0, "%s: pourer_full_fraction in (0, 1)" % n)
	expect(d.perfect_coins >= d.good_coins_max and d.good_coins_max >= d.good_coins_min, "%s: coins PERFECT >= GOOD max >= GOOD min" % n)
	for p in d.glass_outer:
		expect(p.y <= 0.0, "%s: the glass sits on its origin (outer y <= 0)" % n)
	var c := Vector2.ZERO
	for p in d.glass_interior:
		c += p
	c /= d.glass_interior.size()
	for p in d.glass_interior:
		expect(Geometry2D.is_point_in_polygon(p.lerp(c, 0.05), d.glass_outer), "%s: glass interior inside outer" % n)
```

- [ ] **Step 6: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=drinks; echo "exit $?"`
Expected: errors about `DrinkDef`/`GameState` not found and `check_drinks: FAILED (...)` (or no OK line); not `check_drinks: OK`.

- [ ] **Step 7: Create `drink_def.gd`**

```gdscript
class_name DrinkDef
extends Resource
## Everything that makes a drink a drink: the glass, the container you pour
## from, the fill line, the payout and the pour feel. One .tres per drink in
## res://drinks/. Shapes are local pixels with y down: the glass origin is its
## bottom center; the pourer origin is the spout lip (the tilt pivot).

@export var id: StringName
@export var display_name := ""
@export var liquid_color := Color("0099db")
## Stream core, sparkles, drips.
@export var liquid_highlight := Color("2ce8f5")

@export_group("Glass")
@export var glass_interior := PackedVector2Array()
@export var glass_outer := PackedVector2Array()
## The fill line as a share of the glass interior — fixed per drink type.
@export_range(0.1, 1.0) var fill_fraction := 0.9

@export_group("Payout")
@export var perfect_coins := 10
@export var good_coins_max := 8
@export var good_coins_min := 2

@export_group("Pourer")
@export var pourer_interior := PackedVector2Array()
@export var pourer_outer := PackedVector2Array()
## Optional handle polyline (empty for bottles).
@export var pourer_handle := PackedVector2Array()
## "Full" as a share of the pourer interior (a brim-full pitcher would pour at the slightest tilt).
@export_range(0.1, 0.99) var pourer_full_fraction := 0.9
@export var spout_dir := Vector2(-1.0, -0.25)
## Spout lip position relative to the glass origin with the pourer at rest.
@export var pourer_offset := Vector2(14, -87)

@export_group("Tilt")
## Tilt speed (°/s) while DOWN is held and the liquid hasn't reached the lip yet.
@export var tilt_speed_deg := 45.0
## Tilt speed (°/s) while DOWN is held and it is pouring (careful hands).
@export var pour_tilt_speed_deg := 15.0
## How quickly it reaches that speed (1/s). Lower = heavier container.
@export var tilt_response := 6.0
## Constant pull back toward upright once DOWN is released (rad/s²). Lower = more momentum.
@export var return_force := 3.0
## Velocity damping while returning (1/s); caps the return speed at return_force / return_damp.
@export var return_damp := 2.0
@export_range(30.0, 175.0) var max_tilt_deg := 140.0
## Fraction of speed kept when it clunks back onto the table.
@export var rest_bounce := 0.2

@export_group("Pour")
## Share of the over-the-lip excess that leaves per second.
@export var pour_rate := 7.0
## Hard cap on flow (px²/s).
@export var max_flow := 3000.0
@export var stream_speed_min := 15.0
## Exit speed grows with sqrt(excess), like a weir.
@export var stream_speed_k := 5.0

@export_group("Slosh")
@export var slosh_spring := 60.0
@export var slosh_damp := 4.0
## How strongly tilt acceleration sloshes the surface (braking surges liquid toward the spout).
@export var slosh_gain := 0.04
@export var slosh_max := 0.25
```

- [ ] **Step 8: Create `drinks/water.tres`** (the prototype's glass and pitcher; Task 4 enlarges the pitcher)

```
[gd_resource type="Resource" script_class="DrinkDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://drink_def.gd" id="1_drink"]

[resource]
script = ExtResource("1_drink")
id = &"water"
display_name = "Water"
liquid_color = Color(0, 0.6, 0.858824, 1)
liquid_highlight = Color(0.172549, 0.909804, 0.960784, 1)
glass_interior = PackedVector2Array(-15, -5, 15, -5, 19, -74, -19, -74)
glass_outer = PackedVector2Array(-17, 0, 17, 0, 21, -74, -21, -74)
fill_fraction = 0.9
pourer_interior = PackedVector2Array(0, 0, 58, 0, 58, 82, 13, 82, 13, 13)
pourer_outer = PackedVector2Array(-3, -1, 60, -1, 60, 87, 11, 87, 11, 15)
pourer_handle = PackedVector2Array(60, 10, 68, 10, 73, 15, 73, 58, 68, 63, 60, 63)
pourer_offset = Vector2(14, -87)
```

- [ ] **Step 9: Create `game_state.gd`**

```gdscript
extends Node
## Session state (autoload `GameState`): coins, round progress, owned drinks,
## and `stats` — every tunable a future upgrade may change. Gameplay reads
## `stats` at point of use and never hard-codes a value that has a key.
## Nothing is saved yet (session only).

const BASE_STATS := {
	"round_duration": 30.0,
	"perfect_tol": 0.03,
	"good_tol": 0.10,
	"coin_mult": 1.0,
	"pour_speed_mult": 1.0,
	"refill_time": 1.0,
}

var coins := 0
var round_number := 1
var owned_drinks: Array[DrinkDef] = [preload("res://drinks/water.tres")]
var stats: Dictionary = BASE_STATS.duplicate()
```

- [ ] **Step 10: Register the autoload** — in `project.godot`, add this section directly after the `[application]` section (before `[display]`):

```
[autoload]

GameState="*res://game_state.gd"
```

- [ ] **Step 11: Import and run all checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all; echo "exit $?"`
Expected: `check_bubbles: OK`, `check_drinks: OK`, `exit 0`.

- [ ] **Step 12: Smoke-run the game headless**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 300 2>&1 | grep -E "ERROR|SCRIPT"; echo done`
Expected: just `done` (no errors).

- [ ] **Step 13: Commit**

```bash
git add -A tools drink_def.gd drink_def.gd.uid drinks game_state.gd game_state.gd.uid project.godot
git commit -m "feat: check runner, DrinkDef resource, water drink, GameState autoload

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Scoring rules

**Files:**
- Create: `scoring.gd`, `tools/checks/check_scoring.gd`
- Modify: `main.gd` (`_serve`, `_popup`, R key), `glass.gd` (remove `evaluate()` and the scoring exports)

**Interfaces:**
- Consumes: `DrinkDef.perfect_coins/good_coins_max/good_coins_min` (Task 1); `GameState.stats`.
- Produces: `class_name Scoring` with `const PERFECT := &"PERFECT"`, `GOOD`, `MISS`, `SPILL`, `MAX_STEPS := 4`; `static func band(error: float, spilled: bool, perfect_tol: float, good_tol: float) -> StringName`; `static func base_coins(b: StringName, error: float, def: DrinkDef, perfect_tol: float, good_tol: float) -> float`; `static func next_steps(steps: int, b: StringName) -> int`; `static func multiplier(steps: int) -> float`; `static func paid_coins(base: float, steps_before: int, coin_mult: float) -> int`; `static func score(volume: float, target: float, spilled: bool, steps_before: int, def: DrinkDef, stats: Dictionary) -> Dictionary` returning `{band: StringName, error: float, coins: int, steps: int}`.

- [ ] **Step 1: Write the failing check** — create `tools/checks/check_scoring.gd`:

```gdscript
extends CheckBase
## Checks the pure scoring rules (slice 1 spec, "Scoring"). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=scoring


func run() -> void:
	var water: DrinkDef = load("res://drinks/water.tres")
	var stats := {"perfect_tol": 0.03, "good_tol": 0.10, "coin_mult": 1.0}
	# Bands; edges are inclusive.
	eq(Scoring.band(0.0, false, 0.03, 0.10), Scoring.PERFECT, "0% is PERFECT")
	eq(Scoring.band(0.03, false, 0.03, 0.10), Scoring.PERFECT, "+3% is PERFECT")
	eq(Scoring.band(-0.03, false, 0.03, 0.10), Scoring.PERFECT, "-3% is PERFECT")
	eq(Scoring.band(0.031, false, 0.03, 0.10), Scoring.GOOD, "+3.1% is GOOD")
	eq(Scoring.band(0.10, false, 0.03, 0.10), Scoring.GOOD, "+10% is GOOD")
	eq(Scoring.band(-0.10, false, 0.03, 0.10), Scoring.GOOD, "-10% is GOOD")
	eq(Scoring.band(0.101, false, 0.03, 0.10), Scoring.MISS, "+10.1% is MISS")
	eq(Scoring.band(-0.5, false, 0.03, 0.10), Scoring.MISS, "-50% is MISS")
	eq(Scoring.band(0.0, true, 0.03, 0.10), Scoring.SPILL, "a spill beats a perfect level")
	# Base coins.
	eq(Scoring.base_coins(Scoring.PERFECT, 0.01, water, 0.03, 0.10), 10.0, "PERFECT pays perfect_coins")
	near(Scoring.base_coins(Scoring.GOOD, 0.03, water, 0.03, 0.10), 8.0, "GOOD at the PERFECT edge pays good_coins_max")
	near(Scoring.base_coins(Scoring.GOOD, -0.10, water, 0.03, 0.10), 2.0, "GOOD at the GOOD edge pays good_coins_min")
	near(Scoring.base_coins(Scoring.GOOD, 0.065, water, 0.03, 0.10), 5.0, "GOOD halfway pays the midpoint")
	eq(Scoring.base_coins(Scoring.MISS, 0.5, water, 0.03, 0.10), 0.0, "MISS pays 0")
	eq(Scoring.base_coins(Scoring.SPILL, 0.0, water, 0.03, 0.10), 0.0, "SPILL pays 0")
	# Streak.
	eq(Scoring.next_steps(0, Scoring.GOOD), 1, "GOOD adds one step")
	eq(Scoring.next_steps(0, Scoring.PERFECT), 2, "PERFECT adds two steps")
	eq(Scoring.next_steps(3, Scoring.PERFECT), 4, "steps cap at 4")
	eq(Scoring.next_steps(4, Scoring.GOOD), 4, "capped stays capped")
	eq(Scoring.next_steps(4, Scoring.MISS), 0, "MISS resets")
	eq(Scoring.next_steps(3, Scoring.SPILL), 0, "SPILL resets")
	eq(Scoring.multiplier(0), 1.0, "x1 at 0 steps")
	eq(Scoring.multiplier(1), 1.5, "x1.5 at 1 step")
	eq(Scoring.multiplier(4), 3.0, "x3 at 4 steps")
	eq(Scoring.multiplier(9), 3.0, "multiplier caps at x3")
	# score(): the payout uses the multiplier from before this glass.
	var first := Scoring.score(100.0, 100.0, false, 0, water, stats)
	eq(first.band, Scoring.PERFECT, "score: an exact fill is PERFECT")
	eq(first.coins, 10, "score: the first PERFECT pays x1")
	eq(first.steps, 2, "score: the first PERFECT moves the streak to 2 steps")
	var second := Scoring.score(100.0, 100.0, false, first.steps, water, stats)
	eq(second.coins, 20, "score: the second PERFECT pays x2")
	eq(Scoring.score(105.0, 100.0, false, 1, water, stats).coins, 9, "score: GOOD +5% at x1.5 pays round(6.29 * 1.5) = 9")
	eq(Scoring.score(150.0, 100.0, false, 4, water, stats).steps, 0, "score: a MISS resets the streak")
	near(Scoring.score(90.0, 100.0, false, 0, water, stats).error, -0.10, "score: error is signed and relative to the target")
	stats.coin_mult = 2.0
	eq(Scoring.score(100.0, 100.0, false, 0, water, stats).coins, 20, "score: coin_mult doubles the payout")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=scoring; echo "exit $?"`
Expected: compile error "Identifier not declared: Scoring" (or similar); no `check_scoring: OK`.

- [ ] **Step 3: Create `scoring.gd`**

```gdscript
class_name Scoring
## Pure scoring rules — see docs/superpowers/specs/2026-10-15-round-loop-design.md
## ("Scoring"). No scene dependencies, so tools/checks/check_scoring.gd tests them directly.

const PERFECT := &"PERFECT"
const GOOD := &"GOOD"
const MISS := &"MISS"
const SPILL := &"SPILL"
## Streak steps map to x1, x1.5, x2, x2.5, x3.
const MAX_STEPS := 4
## Float slack so band edges stay inclusive after the error's rounding.
const EPS := 1e-6


static func band(error: float, spilled: bool, perfect_tol: float, good_tol: float) -> StringName:
	if spilled:
		return SPILL
	var a := absf(error)
	if a <= perfect_tol + EPS:
		return PERFECT
	if a <= good_tol + EPS:
		return GOOD
	return MISS


## Coins before the streak multiplier and coin_mult (not rounded yet).
static func base_coins(b: StringName, error: float, def: DrinkDef, perfect_tol: float, good_tol: float) -> float:
	if b == PERFECT:
		return float(def.perfect_coins)
	if b == GOOD:
		var t := clampf((absf(error) - perfect_tol) / (good_tol - perfect_tol), 0.0, 1.0)
		return lerpf(def.good_coins_max, def.good_coins_min, t)
	return 0.0


static func next_steps(steps: int, b: StringName) -> int:
	if b == PERFECT:
		return mini(steps + 2, MAX_STEPS)
	if b == GOOD:
		return mini(steps + 1, MAX_STEPS)
	return 0


static func multiplier(steps: int) -> float:
	return 1.0 + 0.5 * clampi(steps, 0, MAX_STEPS)


static func paid_coins(base: float, steps_before: int, coin_mult: float) -> int:
	return roundi(base * multiplier(steps_before) * coin_mult)


## Scores one served glass. `coins` uses the multiplier from `steps_before`;
## `steps` is the streak after this glass.
static func score(volume: float, target: float, spilled: bool, steps_before: int, def: DrinkDef, stats: Dictionary) -> Dictionary:
	var error := (volume - target) / target
	var b := band(error, spilled, stats.perfect_tol, stats.good_tol)
	return {
		"band": b,
		"error": error,
		"coins": paid_coins(base_coins(b, error, def, stats.perfect_tol, stats.good_tol), steps_before, stats.coin_mult),
		"steps": next_steps(steps_before, b),
	}
```

- [ ] **Step 4: Import and run the check**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=scoring; echo "exit $?"`
Expected: `check_scoring: OK`, `exit 0`.

- [ ] **Step 5: Use Scoring in the prototype loop** — in `main.gd`:

Add after `var served := 0`:
```gdscript
var _streak_steps := 0
```

In `_serve()`, replace
```gdscript
	var result := glass.evaluate()
	coins += result.coins
```
with
```gdscript
	var result := Scoring.score(glass.volume, glass.target, glass.spilled > 0.5, _streak_steps, GameState.owned_drinks[0], GameState.stats)
	_streak_steps = result.steps
	coins += result.coins
```

Replace the whole `match result.band:` block in `_popup()` with:
```gdscript
	if result.band == Scoring.PERFECT:
		text = "PERFECT! +%d" % result.coins
		color = Palette.GOLD
	elif result.band == Scoring.GOOD:
		text = "GOOD %+d%% +%d" % [pct, result.coins]
		color = Palette.GREEN
	elif result.band == Scoring.SPILL:
		text = "SPILLED!"
		color = Palette.RED
	else:
		text = "MISS %+d%%" % pct
		color = Palette.RED
```

In `_unhandled_input`, in the `KEY_R:` branch add `_streak_steps = 0` after `served = 0`.

- [ ] **Step 6: Remove the old scoring from `glass.gd`** — delete the export lines `perfect_tol`, `good_tol`, `perfect_coins`, `good_coins_max`, `good_coins_min` (and their doc comments) from the `Target` export group (keep `target_min`/`target_max`), and delete the whole `evaluate()` function.

- [ ] **Step 7: Run all checks and a headless smoke run**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|FAIL|ERROR|outside"; "$GODOT" --headless --path . --quit-after 300 2>&1 | grep -E "ERROR|SCRIPT" ; echo done`
Expected: `check_drinks: OK`, `check_scoring: OK`, `outside the glass: 0`, no `ERROR`/`SCRIPT` lines.

- [ ] **Step 8: Commit**

```bash
git add scoring.gd scoring.gd.uid tools/checks/check_scoring.gd tools/checks/check_scoring.gd.uid main.gd glass.gd
git commit -m "feat: pure Scoring rules with streak multiplier

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Glass from DrinkDef — fixed target, high-contrast fill line, band markers

**Files:**
- Modify (full rewrite): `glass.gd`
- Modify: `draw_layer.gd` (add `draw_outline`), `stream.gd` (`set_drink`, colors), `main.gd` (`_ready` setup)
- Create: `tools/checks/check_glass.gd`

**Interfaces:**
- Consumes: `DrinkDef` (Task 1); `GameState.stats.good_tol`.
- Produces: `Glass.setup(d: DrinkDef) -> void`; `Glass.def: DrinkDef`; `Glass.reset() -> void` (empties; target unchanged); `Glass.target: float` (= `fill_fraction × capacity`); `Glass.target_y() -> float`; `Glass.band_levels() -> Vector2` (x = local row of the +good_tol edge, y = local row of the −good_tol edge, both rounded); `Glass.outer_x_at(y: float) -> Vector2` (outer wall x left/right at local y); unchanged: `level_for`, `rim_y_world`, `opening_world`, `surface_y_world_at`, `receive`, `step`, `volume`, `spilled`, `capacity`, `interior`, `_bubbles`. `static DrawLayer.draw_outline(ci: CanvasItem, poly: PackedVector2Array, wall: Color, rim: Color) -> void`. `Stream.set_drink(d: DrinkDef) -> void`.

- [ ] **Step 1: Write the failing check** — create `tools/checks/check_glass.gd`:

```gdscript
extends CheckBase
## Checks the glass set up from water.tres: exact capacity, fixed target,
## band levels following stats.good_tol, and geometry helpers. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.owned_drinks[0]
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
	var walls := glass.outer_x_at(-37.0)
	expect(walls.is_equal_approx(Vector2(-19, 19)), "outer walls at mid height (got %s)" % walls)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass; echo "exit $?"`
Expected: errors/FAIL lines (e.g. `def` / `band_levels` not found); no `check_glass: OK`.

- [ ] **Step 3: Add the outline helper to `draw_layer.gd`** (append):

```gdscript


## Draws a polygon's edges as 1 px lines; edges along its top (the rim or
## opening) use `rim` instead (a transparent `rim` skips them).
static func draw_outline(ci: CanvasItem, poly: PackedVector2Array, wall: Color, rim: Color) -> void:
	var top := INF
	for p in poly:
		top = minf(top, p.y)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var c := rim if a.y - top < 1.0 and b.y - top < 1.0 else wall
		if c.a > 0.0:
			ci.draw_line(a, b, c)
```

- [ ] **Step 4: Rewrite `glass.gd`** (full file):

```gdscript
class_name Glass
extends Node2D
## A glass (tumbler, mug, cup …) configured by a DrinkDef. Its inside is
## rasterized once into pixel columns/rows, so the volume → level mapping is
## exact to what's drawn. The surface is a 1D wave (one spring column per
## pixel) that the stream and glass motion excite; waves are visual only — the
## volume is the gameplay truth. The fill line is fixed per drink
## (fill_fraction × capacity) and the ±good_tol band is drawn beside it.

@export_group("Waves")
@export var wave_speed := 40.0
@export var wave_spring := 30.0
@export var wave_damp := 3.0
@export var wave_max := 6.0
## Downward kick per (volume × speed) of liquid landing.
@export var impact_gain := 0.0005
## Slosh from the glass sliding (liquid lags the motion).
@export var move_slosh := 0.0012

var def: DrinkDef
var interior := PackedVector2Array()
var outer := PackedVector2Array()
var volume := 0.0
var target := 0.0
var spilled := 0.0
var capacity := 0.0

var _x0 := 0
var _y0 := 0
var _col_top := PackedInt32Array()
var _col_bottom := PackedInt32Array()
var _row_area := PackedInt32Array()
var _row_left := PackedInt32Array()
var _row_right := PackedInt32Array()
var _wave_h := PackedFloat32Array()
var _wave_v := PackedFloat32Array()
var _level := 0.0
var _target_y := 0.0
var _bubbles: Array[Vector3] = []  # x, y (local), rise speed
var _drips: Array[Vector3] = []    # side (-1/1), y (local), speed
var _last_x := 0.0
var _last_vx := 0.0

@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front
@onready var _mat := _liquid.material as ShaderMaterial


func _ready() -> void:
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front
	_last_x = global_position.x


func setup(d: DrinkDef) -> void:
	def = d
	interior = d.glass_interior
	outer = d.glass_outer
	_rasterize()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in interior:
		lo = lo.min(p)
		hi = hi.max(p)
	_mat.set_shader_parameter("tint", d.liquid_color)
	_mat.set_shader_parameter("center_x", (lo.x + hi.x) * 0.5)
	_mat.set_shader_parameter("half_width", (hi.x - lo.x) * 0.5)
	_mat.set_shader_parameter("highlight_x", lo.x + 4.0)
	target = d.fill_fraction * capacity
	_target_y = level_for(target)
	reset()


## Empties the glass for the next serve (the fill line stays where it is).
func reset() -> void:
	volume = 0.0
	spilled = 0.0
	_level = level_for(0.0)
	_wave_h.fill(0.0)
	_wave_v.fill(0.0)
	_bubbles.clear()
	_drips.clear()


func _rasterize() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in interior:
		lo = lo.min(p)
		hi = hi.max(p)
	_x0 = floori(lo.x)
	_y0 = floori(lo.y)
	var cols := ceili(hi.x) - _x0
	var rows := ceili(hi.y) - _y0
	_col_top.resize(cols)
	_col_bottom.resize(cols)
	_row_area.resize(rows)
	_row_area.fill(0)
	_row_left.resize(rows)
	_row_left.fill(1 << 30)
	_row_right.resize(rows)
	_row_right.fill(-(1 << 30))
	_wave_h.resize(cols)
	_wave_v.resize(cols)
	capacity = 0.0
	for c in cols:
		var top := 1 << 30
		var bottom := -(1 << 30)
		for r in rows:
			if Geometry2D.is_point_in_polygon(Vector2(_x0 + c + 0.5, _y0 + r + 0.5), interior):
				top = mini(top, _y0 + r)
				bottom = maxi(bottom, _y0 + r + 1)
				_row_area[r] += 1
				_row_left[r] = mini(_row_left[r], _x0 + c)
				_row_right[r] = maxi(_row_right[r], _x0 + c)
				capacity += 1.0
		_col_top[c] = top
		_col_bottom[c] = bottom


## Local y of the calm surface holding `vol`.
func level_for(vol: float) -> float:
	var remaining := vol
	for r in range(_row_area.size() - 1, -1, -1):
		var a := float(_row_area[r])
		if a == 0.0:
			continue
		if remaining <= a:
			return _y0 + r + 1 - remaining / a
		remaining -= a
	return float(_y0)


func target_y() -> float:
	return _target_y


## Local rows of the ±good_tol band edges: x = upper (+tol), y = lower (−tol).
func band_levels() -> Vector2:
	var tol: float = GameState.stats.good_tol
	return Vector2(roundf(level_for(target * (1.0 + tol))), roundf(level_for(target * (1.0 - tol))))


func rim_y_world() -> float:
	return global_position.y + _y0


## World x range of the opening (the interior's top pixel row).
func opening_world() -> Vector2:
	return Vector2(global_position.x + _row_left[0], global_position.x + _row_right[0] + 1)


## Outer wall x (left, right) at local y.
func outer_x_at(y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := outer.size()
	for i in n:
		var a := outer[i]
		var b := outer[(i + 1) % n]
		if a.y != b.y and (a.y - y) * (b.y - y) <= 0.0:
			var x := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
			lo = minf(lo, x)
			hi = maxf(hi, x)
	return Vector2(lo, hi)


func _col(x_world: float) -> int:
	return clampi(floori(x_world - global_position.x) - _x0, 0, _wave_h.size() - 1)


func _surface_local(c: int) -> float:
	if volume < 0.5:
		return float(_col_bottom[c])
	return minf(_level - _wave_h[c], float(_col_bottom[c]))


## True if the pixel at local (x, y) is inside the glass.
func _inside(x: float, y: float) -> bool:
	var c := floori(x) - _x0
	var r := floori(y)
	return c >= 0 and c < _col_top.size() and r >= _col_top[c] and r < _col_bottom[c]


func surface_y_world_at(x_world: float) -> float:
	return global_position.y + _surface_local(_col(x_world))


func receive(x_world: float, vol: float, speed: float) -> void:
	volume += vol
	if volume > capacity:
		spilled += volume - capacity
		volume = capacity
		if _drips.size() < 30:
			_drips.append(Vector3(1.0 if randf() < 0.5 else -1.0, float(_y0), randf_range(30.0, 60.0)))
	var c := _col(x_world)
	var kick := vol * speed * impact_gain
	_wave_v[c] -= kick
	if c > 0:
		_wave_v[c - 1] -= kick * 0.5
	if c < _wave_v.size() - 1:
		_wave_v[c + 1] -= kick * 0.5
	if randf() < vol * speed * 0.0004 and _bubbles.size() < 40:
		# Spawn under the impact, but never deeper than this column's floor.
		var bc := clampi(c + randi_range(-2, 2), 0, _col_top.size() - 1)
		var top := _surface_local(bc) + 2.0
		var floor_y := float(_col_bottom[bc]) - 1.0
		if floor_y > top:
			var y := minf(top + randf_range(1.0, 2.0 + speed * 0.06), floor_y)
			_bubbles.append(Vector3(float(_x0 + bc) + 0.5, y, randf_range(8.0, 22.0)))


func step(dt: float) -> void:
	_level = level_for(volume)
	_mat.set_shader_parameter("surface_y", _level)

	var vx := (global_position.x - _last_x) / dt
	var ax := (vx - _last_vx) / dt
	_last_x = global_position.x
	_last_vx = vx

	var n := _wave_h.size()
	var mid := (n - 1) * 0.5
	var c2 := wave_speed * wave_speed
	var sdt := dt * 0.5
	for sub in 2:
		for i in n:
			var l := _wave_h[maxi(i - 1, 0)]
			var r := _wave_h[mini(i + 1, n - 1)]
			var acc := c2 * (l + r - 2.0 * _wave_h[i]) - wave_spring * _wave_h[i] - wave_damp * _wave_v[i]
			acc -= ax * move_slosh * (i - mid)
			_wave_v[i] += acc * sdt
		for i in n:
			_wave_h[i] = clampf(_wave_h[i] + _wave_v[i] * sdt, -wave_max, wave_max)

	for i in range(_bubbles.size() - 1, -1, -1):
		var b := _bubbles[i]
		b.y -= b.z * dt
		var wobbled := b.x + sin(b.y * 0.7) * 0.15
		if _inside(wobbled, b.y):
			b.x = wobbled
		var c := clampi(floori(b.x) - _x0, 0, n - 1)
		if volume < 0.5 or b.y <= _surface_local(c) + 1.0:
			_bubbles.remove_at(i)
		else:
			_bubbles[i] = b
	for i in range(_drips.size() - 1, -1, -1):
		var d := _drips[i]
		d.y += d.z * dt
		if d.y >= 0.0:
			_drips.remove_at(i)
		else:
			_drips[i] = d

	_liquid.queue_redraw()
	_front.queue_redraw()


func _draw_liquid(ci: CanvasItem) -> void:
	if def == null or volume < 0.5:
		return
	for c in _col_top.size():
		var top := maxi(roundi(_surface_local(c)), _col_top[c])
		if top < _col_bottom[c]:
			ci.draw_rect(Rect2(_x0 + c, top, 1, _col_bottom[c] - top), Color.WHITE)


func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	ci.draw_colored_polygon(outer, Color(Palette.FROST, 0.08))
	for wall in Geometry2D.clip_polygons(outer, interior):
		ci.draw_colored_polygon(wall, Color(Palette.FROST, 0.3))

	# Meniscus + bubbles.
	if volume >= 0.5:
		for c in _col_top.size():
			var top := maxi(roundi(_surface_local(c)), _col_top[c])
			if top < _col_bottom[c]:
				ci.draw_rect(Rect2(_x0 + c, top, 1, 1), Color(Palette.WHITE, 0.55))
	for b in _bubbles:
		ci.draw_rect(Rect2(floorf(b.x), floorf(b.y), 1, 1), Color(Palette.WHITE, 0.7))

	_draw_band(ci)
	_draw_fill_line(ci)

	# Walls: outlines inset/outset half a pixel so 1 px lines land on the glass's own pixels.
	for poly in Geometry2D.offset_polygon(outer, -0.5, Geometry2D.JOIN_MITER):
		DrawLayer.draw_outline(ci, poly, Palette.FROST, Color(Palette.FROST, 0.7))
	for poly in Geometry2D.offset_polygon(interior, 0.5, Geometry2D.JOIN_MITER):
		DrawLayer.draw_outline(ci, poly, Color(Palette.MIST, 0.5), Color(0, 0, 0, 0))
	# Highlights, derived from the interior's row spans.
	var rows := _row_left.size()
	for r in range(6, rows - 6):
		ci.draw_rect(Rect2(_row_left[r] + 3, _y0 + r, 1, 1), Color(Palette.WHITE, 0.55))
	for r in range(8, mini(22, rows)):
		ci.draw_rect(Rect2(_row_right[r] - 3, _y0 + r, 1, 1), Color(Palette.WHITE, 0.35))

	# Drips running down the outside after an overflow.
	for d in _drips:
		var walls := outer_x_at(d.y)
		var px := floorf(walls.y) if d.x > 0.0 else floorf(walls.x) - 1.0
		ci.draw_rect(Rect2(px, floorf(d.y), 1, 2), def.liquid_highlight)


## The ±good_tol band: a light bracket (spine + end ticks pointing at the
## glass) just outside the left wall, outlined dark so it reads on any background.
func _draw_band(ci: CanvasItem) -> void:
	var band := band_levels()
	var y_top := int(band.x)
	var y_bot := int(band.y)
	var x := floori(outer_x_at(float(y_top)).x) - 4
	var h := y_bot - y_top + 1
	ci.draw_rect(Rect2(x - 1, y_top - 1, 3, h + 2), Palette.INK)
	ci.draw_rect(Rect2(x - 1, y_top - 1, 5, 3), Palette.INK)
	ci.draw_rect(Rect2(x - 1, y_bot - 1, 5, 3), Palette.INK)
	ci.draw_rect(Rect2(x, y_top, 1, h), Palette.FROST)
	ci.draw_rect(Rect2(x, y_top, 3, 1), Palette.FROST)
	ci.draw_rect(Rect2(x, y_bot, 3, 1), Palette.FROST)


## The fill line: a 1 px white line with dark rows above and below across the
## inside, plus outlined ticks outside the walls. The left tick runs from the
## band bracket to the wall, so it reads as the bracket's centre mark.
func _draw_fill_line(ci: CanvasItem) -> void:
	var ty := roundi(_target_y)
	var r := ty - _y0
	if r < 0 or r >= _row_left.size():
		return
	var left := _row_left[r]
	var width := _row_right[r] - left + 1
	ci.draw_rect(Rect2(left, ty - 1, width, 3), Palette.INK)
	ci.draw_rect(Rect2(left, ty, width, 1), Palette.WHITE)
	var walls := outer_x_at(float(ty) + 0.5)
	var bracket_x := floori(outer_x_at(band_levels().x).x) - 4
	var left_end := floori(walls.x) - 2
	ci.draw_rect(Rect2(bracket_x - 1, ty - 1, left_end - bracket_x + 2, 3), Palette.INK)
	ci.draw_rect(Rect2(bracket_x, ty, left_end - bracket_x, 1), Palette.WHITE)
	# Short right tick: the pourer's wall sits ~4 px to the right of the glass.
	var right_start := ceili(walls.y) + 1
	ci.draw_rect(Rect2(right_start - 1, ty - 1, 4, 3), Palette.INK)
	ci.draw_rect(Rect2(right_start, ty, 2, 1), Palette.WHITE)
```

- [ ] **Step 5: Liquid colors from the drink in `stream.gd`**

Add after `var spilled := 0.0`:
```gdscript
var liquid_color := Palette.WATER
var liquid_highlight := Palette.WATER_LIGHT
```
Add after the `emit` function:
```gdscript
func set_drink(d: DrinkDef) -> void:
	liquid_color = d.liquid_color
	liquid_highlight = d.liquid_highlight
```
In `_draw()`, replace the first two lines with:
```gdscript
	var body := Color(liquid_color, 0.9)
	var core := Color(liquid_highlight, 0.9)
```

- [ ] **Step 6: Set the glass up from the drink in `main.gd`** — make these the first lines of `_ready()` (before `_build_hud()`):

```gdscript
	var drink: DrinkDef = GameState.owned_drinks[0]
	glass.setup(drink)
	stream.set_drink(drink)
```

- [ ] **Step 7: Run the checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|FAIL|ERROR|outside"`
Expected: `check_glass: OK`, `outside the glass: 0`, `check_scoring: OK`, `check_drinks: OK`, no `ERROR`.

- [ ] **Step 8: Look at it** — capture autopilot screenshots and view the glass up close:

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; S="$TMPDIR/pour_task3"; mkdir -p "$S"; "$GODOT" --path . --windowed --resolution 1280x720 -- --hold=2.6 --shots="$S/shot" --quit=4.2; python3 -c "
from PIL import Image
im = Image.open('$S/shot_6.png').crop((200, 180, 320, 290)); im.resize((480, 440), Image.NEAREST).save('$S/glass_zoom.png')"; echo "$S/glass_zoom.png"`
Then Read the printed PNG. Expected: a white fill line with dark edges clearly visible against the tiles and the water; a light bracket with end ticks left of the glass spanning the band, with the fill line's left tick crossing it; walls outlined; no stray lines. If the fill line or bracket is hard to see, adjust only colors/sizes in `_draw_band`/`_draw_fill_line` and re-check.

- [ ] **Step 9: Commit**

```bash
git add glass.gd draw_layer.gd stream.gd main.gd tools/checks/check_glass.gd tools/checks/check_glass.gd.uid
git commit -m "feat: glass from DrinkDef with fixed fill line and tolerance band markers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Pourer from DrinkDef — bigger pitcher, auto-refill, sweep retune

**Files:**
- Rename: `pitcher.gd` → `pourer.gd`, `pitcher.gd.uid` → `pourer.gd.uid` (`git mv`), then rewrite `pourer.gd`
- Modify: `drinks/water.tres` (bigger pitcher), `main.tscn` (node + script rename), `main.gd` (rename, setup, serve, sweep), `tools/checks/check_bubbles.gd` (`main.pitcher` → `main.pourer`)
- Create: `tools/checks/check_pourer.gd`

**Interfaces:**
- Consumes: `DrinkDef` (Task 1); `DrawLayer.draw_outline` (Task 3); `GameState.stats.pour_speed_mult`, `GameState.stats.refill_time`.
- Produces: `class_name Pourer`: `setup(d: DrinkDef) -> void`; `reset(fill := 1.0) -> void` (upright, still, `volume = full_volume * fill`, not refilling); `step(dt: float, hold: bool) -> float` (volume poured this tick); `exit_velocity() -> Vector2`; `is_pouring() -> bool`; `at_rest() -> bool`; fields `def`, `interior`, `capacity` (interior area), `full_volume`, `volume`, `tilt`, `tilt_vel`, `flow`, `excess`, `refilling: bool`; `static poly_area(p: PackedVector2Array) -> float`. `main.pourer` replaces `main.pitcher`.

- [ ] **Step 1: Rename the file** (keeps the uid):

```bash
git mv pitcher.gd pourer.gd
git mv pitcher.gd.uid pourer.gd.uid
```

- [ ] **Step 2: Write the failing check** — create `tools/checks/check_pourer.gd`:

```gdscript
extends CheckBase
## Checks the pourer: DrinkDef setup, capacity vs the glass, pour_speed_mult,
## and the automatic refill. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=pourer

const DT := 1.0 / 60.0


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var pourer: Pourer = main.pourer
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.owned_drinks[0]
	expect(pourer.def == water, "pourer is set up with water")
	var glasses := pourer.full_volume / glass.target
	expect(glasses > 2.3 and glasses < 2.7, "a full pitcher holds ~2.5 glasses at the line (got %.2f)" % glasses)
	expect(pourer.position.is_equal_approx(Vector2(256, 280) + water.pourer_offset), "pourer sits at glass + pourer_offset")
	pourer.reset()
	expect(pourer.volume == pourer.full_volume and not pourer.refilling, "reset() = full, upright, not refilling")

	# pour_speed_mult scales the tilt speed (measured before any pouring starts).
	var base_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 2.0
	var fast_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 1.0
	var ratio := fast_tilt / base_tilt
	expect(ratio > 1.8 and ratio < 2.2, "pour_speed_mult 2 doubles the tilt speed (ratio %.2f)" % ratio)

	# Running dry while tilted: DOWN is ignored (same motion held or not), it
	# returns upright, then refills over stats.refill_time.
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
```

- [ ] **Step 3: Rewrite `pourer.gd`** (full file):

```gdscript
class_name Pourer
extends Node2D
## The container you pour from (pitcher, bottle …), configured by a DrinkDef.
## It tilts around its spout lip (this node's origin). Pouring is pure
## geometry: the liquid surface stays (almost) level in the world while the
## pourer rotates, and whatever volume no longer fits below the line through
## the spout lip leaves through the spout. Volumes are areas in px², the same
## unit the glass uses. When it runs dry it refills itself: input is ignored,
## it returns upright, then fills over GameState.stats.refill_time.

## Excess below this is treated as "not pouring" so the stream can end cleanly.
const MIN_EXCESS := 0.5
## Below this share of full_volume the pourer counts as empty and refills.
const EMPTY_SHARE := 0.01

var def: DrinkDef
var interior := PackedVector2Array()
## Interior area (px²).
var capacity := 0.0
## What "full" holds: capacity × def.pourer_full_fraction.
var full_volume := 0.0

var tilt := 0.0
var tilt_vel := 0.0
var slosh := 0.0
var slosh_vel := 0.0
var volume := 0.0
var flow := 0.0
var excess := 0.0
var exit_speed := 0.0
var refilling := false

var _refill_t := -1.0  # < 0 while still swinging back upright
var _refill_from := 0.0
var _surf_angle := 0.0
var _surf_point := Vector2.ZERO

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


## Upright, still, not refilling, holding `fill` × full_volume.
func reset(fill := 1.0) -> void:
	tilt = 0.0
	tilt_vel = 0.0
	slosh = 0.0
	slosh_vel = 0.0
	volume = full_volume * fill
	flow = 0.0
	excess = 0.0
	refilling = false
	_refill_t = -1.0
	rotation = 0.0
	_update_surface()


## Advances one physics tick. Returns the volume that left the spout this tick.
func step(dt: float, hold: bool) -> float:
	if not refilling and volume < full_volume * EMPTY_SHARE:
		refilling = true
		_refill_t = -1.0
	if refilling:
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
	rotation = -tilt

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
	if _refill_t < 0.0:
		if tilt > 0.0 or tilt_vel != 0.0:
			return  # still swinging back upright
		_refill_t = 0.0
		_refill_from = volume
	_refill_t += dt
	var duration: float = GameState.stats.refill_time
	var t := clampf(_refill_t / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	volume = lerpf(_refill_from, full_volume, t)
	if t >= 1.0:
		refilling = false


func exit_velocity() -> Vector2:
	return def.spout_dir.normalized().rotated(rotation) * exit_speed


func is_pouring() -> bool:
	return flow > 0.0


func at_rest() -> bool:
	return tilt <= 0.0001 and absf(tilt_vel) < 0.01 and not is_pouring()


## Surface angle in local space: world-level (rotated back by the tilt) plus slosh.
func _local_surface_angle() -> float:
	return tilt + slosh


func _update_surface() -> void:
	_surf_angle = _local_surface_angle()
	var shown := minf(volume, _area_below(Vector2.ZERO, _surf_angle))
	var u := Vector2.from_angle(_surf_angle)
	var n := Vector2(-u.y, u.x)
	# Binary search how far below the lip the surface sits for this volume.
	var lo := 0.0
	var hi := 200.0
	for i in 22:
		var mid := (lo + hi) * 0.5
		if _area_below(n * mid, _surf_angle) > shown:
			lo = mid
		else:
			hi = mid
	_surf_point = n * lo
	_liquid.queue_redraw()
	_front.queue_redraw()


## Interior ∩ half-plane below the line through `point` at `angle` (local).
func _liquid_shape(point: Vector2, angle: float) -> Array[PackedVector2Array]:
	var u := Vector2.from_angle(angle)
	var n := Vector2(-u.y, u.x)
	var half := PackedVector2Array([
		point - u * 400.0, point + u * 400.0, point + u * 400.0 + n * 400.0, point - u * 400.0 + n * 400.0,
	])
	return Geometry2D.intersect_polygons(interior, half)


func _area_below(point: Vector2, angle: float) -> float:
	var total := 0.0
	for poly in _liquid_shape(point, angle):
		total += poly_area(poly)
	return total


static func poly_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


## The highlight stripe: the interior's left-most long, mostly vertical edge,
## moved 4 px inward and shortened 8 px at both ends.
func _highlight_segment() -> PackedVector2Array:
	var best := -1
	var best_x := INF
	for i in interior.size():
		var a := interior[i]
		var b := interior[(i + 1) % interior.size()]
		var d := b - a
		if absf(d.y) > absf(d.x) * 2.0 and absf(d.y) > 20.0 and (a.x + b.x) * 0.5 < best_x:
			best = i
			best_x = (a.x + b.x) * 0.5
	if best < 0:
		return PackedVector2Array()
	var a := interior[best]
	var b := interior[(best + 1) % interior.size()]
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	if n.dot(_bounds(interior).get_center() - a) < 0.0:
		n = -n
	return PackedVector2Array([a + n * 4.0 + dir * 8.0, b + n * 4.0 - dir * 8.0])


func _draw_liquid(ci: CanvasItem) -> void:
	if def == null or volume < 1.0:
		return
	for poly in _liquid_shape(_surf_point, _surf_angle):
		ci.draw_colored_polygon(poly, Color.WHITE)


func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	var outer := def.pourer_outer
	ci.draw_colored_polygon(outer, Color(Palette.FROST, 0.10))
	for wall in Geometry2D.clip_polygons(outer, interior):
		ci.draw_colored_polygon(wall, Color(Palette.FROST, 0.3))
	# Liquid surface sparkle.
	if volume >= 1.0:
		var u := Vector2.from_angle(_surf_angle)
		var line := PackedVector2Array([_surf_point - u * 200.0, _surf_point + u * 200.0])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, interior):
			ci.draw_polyline(seg, Color(Palette.WHITE, 0.55))
	DrawLayer.draw_outline(ci, outer, Palette.FROST, Color(Palette.FROST, 0.45))
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
```

- [ ] **Step 4: Enlarge the water pitcher** — replace `drinks/water.tres` with (the pitcher interior is 57×100 + spout ≈ 5 785 px²; full = 0.9 of that ≈ 2.47 glasses at the line; `pour_tilt_speed_deg = 11.0` is a starting guess for Step 9):

```
[gd_resource type="Resource" script_class="DrinkDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://drink_def.gd" id="1_drink"]

[resource]
script = ExtResource("1_drink")
id = &"water"
display_name = "Water"
liquid_color = Color(0, 0.6, 0.858824, 1)
liquid_highlight = Color(0.172549, 0.909804, 0.960784, 1)
glass_interior = PackedVector2Array(-15, -5, 15, -5, 19, -74, -19, -74)
glass_outer = PackedVector2Array(-17, 0, 17, 0, 21, -74, -21, -74)
fill_fraction = 0.9
pourer_interior = PackedVector2Array(0, 0, 70, 0, 70, 100, 13, 100, 13, 13)
pourer_outer = PackedVector2Array(-3, -1, 72, -1, 72, 105, 11, 105, 11, 15)
pourer_handle = PackedVector2Array(72, 12, 81, 12, 86, 18, 86, 70, 81, 76, 72, 76)
pourer_offset = Vector2(14, -105)
pour_tilt_speed_deg = 11.0
```

- [ ] **Step 5: Rename the node in `main.tscn`** — replace the file with:

```
[gd_scene load_steps=10 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]
[ext_resource type="Texture2D" path="res://art/background.png" id="2_bg"]
[ext_resource type="Script" path="res://glass.gd" id="3_glass"]
[ext_resource type="Script" path="res://pourer.gd" id="4_pourer"]
[ext_resource type="Script" path="res://stream.gd" id="5_stream"]
[ext_resource type="Shader" path="res://liquid.gdshader" id="6_liquid"]
[ext_resource type="Script" path="res://draw_layer.gd" id="7_layer"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_glass"]
shader = ExtResource("6_liquid")
shader_parameter/tint = Color(0, 0.6, 0.858824, 1)
shader_parameter/tint_strength = 0.5
shader_parameter/refraction_px = 1.0
shader_parameter/lens_strength = 0.3
shader_parameter/dither_levels = 4.0
shader_parameter/highlight = Color(1, 1, 1, 1)
shader_parameter/highlight_strength = 0.45

[sub_resource type="ShaderMaterial" id="ShaderMaterial_pourer"]
shader = ExtResource("6_liquid")
shader_parameter/tint = Color(0, 0.6, 0.858824, 1)
shader_parameter/tint_strength = 0.5
shader_parameter/refraction_px = 1.0
shader_parameter/lens_strength = 0.25
shader_parameter/dither_levels = 4.0
shader_parameter/highlight = Color(1, 1, 1, 1)
shader_parameter/highlight_strength = 0.35

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Background" type="Sprite2D" parent="."]
texture = ExtResource("2_bg")
centered = false

[node name="Glass" type="Node2D" parent="."]
position = Vector2(256, 280)
script = ExtResource("3_glass")

[node name="Liquid" type="Node2D" parent="Glass"]
material = SubResource("ShaderMaterial_glass")
script = ExtResource("7_layer")

[node name="Front" type="Node2D" parent="Glass"]
script = ExtResource("7_layer")

[node name="Stream" type="Node2D" parent="."]
script = ExtResource("5_stream")

[node name="Pourer" type="Node2D" parent="."]
position = Vector2(270, 175)
script = ExtResource("4_pourer")

[node name="Liquid" type="Node2D" parent="Pourer"]
material = SubResource("ShaderMaterial_pourer")
script = ExtResource("7_layer")

[node name="Front" type="Node2D" parent="Pourer"]
script = ExtResource("7_layer")
```

- [ ] **Step 6: Update `main.gd` for the pourer**

1. Replace `@onready var pitcher: Pitcher = $Pitcher` with `@onready var pourer: Pourer = $Pourer`, then replace every remaining `pitcher.` with `pourer.` in the file.
2. In `_ready()`, after `stream.set_drink(drink)` add:
```gdscript
	pourer.setup(drink)
	pourer.position = Vector2(GLASS_X, 280.0) + drink.pourer_offset
```
3. In `_serve()`, replace the refill callback
```gdscript
	tw.tween_callback(func() -> void:
		glass.reset()
		if pourer.refill_on_serve:
			pourer.refill()
	)
```
with `tw.tween_callback(glass.reset)` (the pitcher now drains across glasses and refills itself).
4. In `_update_hud()`, replace `roundi(pourer.capacity)` with `roundi(pourer.full_volume)`.
5. In `_ready()`, replace `_sweep()` with `_sweep(args["sweep"])`, and replace the whole `_sweep()` function (and its doc comment) with:

```gdscript
## Simulates holds of increasing length — with the pourer full, then half
## full — and prints how much ends up in the glass, how far from the line,
## how much arrived after DOWN was released (the overshoot), and settle time.
func _sweep(drink_id: String) -> void:
	var dt := 1.0 / 60.0
	var d: DrinkDef = GameState.owned_drinks[0]
	for owned in GameState.owned_drinks:
		if String(owned.id) == drink_id:
			d = owned
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

- [ ] **Step 7: Point the bubble check at the pourer** — in `tools/checks/check_bubbles.gd`, replace `main.pitcher.reset()` with `main.pourer.reset()`.

- [ ] **Step 8: Import and run the checks**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|FAIL|ERROR|outside"`
Expected: all `OK`, `outside the glass: 0`, no `ERROR`. (If the `~2.5 glasses` check fails, the pitcher shape in water.tres was mistyped.)

- [ ] **Step 9: Retune the feel with the sweep**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -- --sweep=water 2>&1 | grep -v "^Godot Engine"`
Acceptance (pourer full table) — the prototype's feel the user liked:
- the first row with `fill% > 0` has `hold_s` 0.6–0.8 (pouring starts ~0.5 s into a hold);
- the row with `vs_line%` closest to 0 has `hold_s` between 2.2 and 3.2;
- rows with `fill%` between 70 and 95 have `after_release%` between 9 and 15.

The wider pitcher pours more per degree than the prototype's, so the main knob is `pour_tilt_speed_deg` in `drinks/water.tres` (lower = slower fill, smaller overshoot); only touch `tilt_speed_deg` if pouring starts too late/early. Edit, re-run, repeat until all three hold. The half-full table is informational (pouring starts later and gushes less) — note its numbers in the commit message.

- [ ] **Step 10: Look at it**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; S="$TMPDIR/pour_task4"; mkdir -p "$S"; "$GODOT" --path . --windowed --resolution 1280x720 -- --hold=2.8 --shots="$S/shot" --quit=4.2; python3 -c "
from PIL import Image
ims = [Image.open('$S/shot_%d.png' % i).crop((180, 40, 420, 290)) for i in (1, 3, 5)]
sheet = Image.new('RGB', (720, 250))
for i, im in enumerate(ims): sheet.paste(im, (i * 240, 0))
sheet.resize((1440, 500), Image.NEAREST).save('$S/sheet.png')"; echo "$S/sheet.png"`
Read the PNG. Expected: the bigger glass pitcher at rest sits on the counter right of the glass without overlapping it; tilted, its outline, handle, highlight stripe and level water surface look right; the stream lands inside the glass.

- [ ] **Step 11: Commit**

```bash
git add pourer.gd pourer.gd.uid drinks/water.tres main.tscn main.gd tools/checks/check_pourer.gd tools/checks/check_pourer.gd.uid tools/checks/check_bubbles.gd
git commit -m "feat: Pourer from DrinkDef with auto-refill and a 2.5-glass pitcher

<paste the final sweep acceptance numbers here: pour start hold, hold
nearest the line, after_release range; half-full summary>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: HUD and round summary screen

**Files:**
- Create: `hud.gd`, `round_summary.gd`, `round_summary.tscn`, `tools/checks/check_ui.gd`
- Modify: `main.gd` (use `Hud`), `main.tscn` (add `Hud` node), `stream.gd` (`parcel_count()`)

**Interfaces:**
- Consumes: `Scoring.multiplier`, `Scoring.PERFECT/GOOD/SPILL` (Task 2).
- Produces: `class_name Hud extends CanvasLayer`: `static format_time(seconds: float) -> String`; `static format_mult(steps: int) -> String`; `set_time(seconds: float)`; `set_coins(total: int)`; `place_streak(pos: Vector2)`; `set_streak(steps: int)`; `popup(result: Dictionary, at: Vector2)`; `show_banner(text: String, seconds: float)`; `set_hint(text: String)`; `toggle_debug()`; `is_debug_visible() -> bool`; `set_debug(text: String)`; labels `timer_label`, `coins_label`, `streak_label`, `banner_label`, `hint_label`, `debug_label`. `class_name RoundSummary extends CanvasLayer`: `signal next_pressed`; `show_results(round_number: int, stats: Dictionary, total_coins: int)` (stats keys `served`, `perfects`, `best_steps`, `coins`); `hide_results()`; `body_text() -> String`. `Stream.parcel_count() -> int`.

- [ ] **Step 1: Write the failing check** — create `tools/checks/check_ui.gd`:

```gdscript
extends CheckBase
## Checks HUD formatting/state and the round summary screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=ui


func run() -> void:
	eq(Hud.format_time(30.0), "0:30", "30 s")
	eq(Hud.format_time(29.01), "0:30", "counts whole seconds up")
	eq(Hud.format_time(5.0), "0:05", "5 s")
	eq(Hud.format_time(0.2), "0:01", "the last fraction shows 0:01")
	eq(Hud.format_time(0.0), "0:00", "0 s")
	eq(Hud.format_time(-1.0), "0:00", "never negative")
	eq(Hud.format_time(75.0), "1:15", "minutes")
	eq(Hud.format_mult(0), "x1", "x1")
	eq(Hud.format_mult(1), "x1.5", "x1.5")
	eq(Hud.format_mult(2), "x2", "x2")
	eq(Hud.format_mult(4), "x3", "x3")
	eq(Hud.format_mult(9), "x3", "capped at x3")

	var hud: Hud = load("res://hud.gd").new()
	add_child(hud)
	hud.set_time(4.0)
	eq(hud.timer_label.text, "0:04", "timer text")
	eq(hud.timer_label.get_theme_color("font_color"), Palette.RED, "timer is red in the last 5 s")
	hud.set_time(12.0)
	eq(hud.timer_label.get_theme_color("font_color"), Palette.WHITE, "timer is white otherwise")
	hud.set_coins(42)
	eq(hud.coins_label.text, "COINS 42", "coins label")
	hud.set_streak(2)
	eq(hud.streak_label.text, "x2", "streak label")
	hud.show_banner("LAST CALL!", 1.5)
	eq(hud.banner_label.visible and hud.banner_label.text == "LAST CALL!", true, "banner shows")
	eq(hud.is_debug_visible(), false, "debug starts hidden")
	hud.toggle_debug()
	eq(hud.is_debug_visible(), true, "F1 toggles debug")

	var summary: RoundSummary = load("res://round_summary.tscn").instantiate()
	add_child(summary)
	eq(summary.visible, false, "summary starts hidden")
	summary.show_results(3, {"served": 7, "perfects": 2, "best_steps": 4, "coins": 55}, 120)
	eq(summary.visible, true, "show_results shows it")
	var text := summary.body_text()
	for want in ["GLASSES", "7", "PERFECT", "2", "x3", "+55", "120"]:
		eq(text.contains(want), true, "summary shows %s" % want)
	var pressed := [false]
	summary.next_pressed.connect(func() -> void: pressed[0] = true)
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	summary._unhandled_input(space)
	eq(pressed[0], true, "Space on the summary emits next_pressed")
	eq(summary.visible, false, "...and hides it")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=ui; echo "exit $?"`
Expected: compile error ("Hud" not declared); no `check_ui: OK`.

- [ ] **Step 3: Create `hud.gd`**

```gdscript
class_name Hud
extends CanvasLayer
## Everything drawn over the game: timer, coins, streak multiplier, result
## popups, banners, the key hint and the F1 debug readout. Purely visual — it
## never drives game logic (its tweens only animate labels).

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const SCREEN_W := 640.0

var root: Control
var timer_label: Label
var coins_label: Label
var streak_label: Label
var banner_label: Label
var hint_label: Label
var debug_label: Label

var _streak_pos := Vector2(184, 196)
var _banner_tween: Tween


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 8
	root.theme = theme
	add_child(root)
	coins_label = make_label(Vector2(8, 8), Palette.GOLD)
	timer_label = make_label(Vector2(0, 8), Palette.WHITE)
	timer_label.size = Vector2(SCREEN_W, 8)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_label = make_label(_streak_pos, Palette.FROST)
	banner_label = make_label(Vector2(0, 112), Palette.WHITE)
	banner_label.size = Vector2(SCREEN_W, 16)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 16)
	banner_label.visible = false
	hint_label = make_label(Vector2(8, 344), Palette.FROST)
	debug_label = make_label(Vector2(8, 24), Palette.FROST)
	debug_label.visible = false


func make_label(pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Palette.INK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 4)
	root.add_child(l)
	return l


## Seconds left as M:SS, rounding up (0:30 at the start, 0:00 only at the end).
static func format_time(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


static func format_mult(steps: int) -> String:
	var m := Scoring.multiplier(steps)
	return "x%d" % int(m) if m == floorf(m) else "x%.1f" % m


func set_time(seconds: float) -> void:
	timer_label.text = format_time(seconds)
	timer_label.add_theme_color_override("font_color", Palette.RED if seconds <= 5.0 else Palette.WHITE)


func set_coins(total: int) -> void:
	coins_label.text = "COINS %d" % total


func place_streak(pos: Vector2) -> void:
	_streak_pos = pos
	streak_label.position = pos


## Shows what the next glass pays; pops when it changes.
func set_streak(steps: int) -> void:
	var text := format_mult(steps)
	if text == streak_label.text:
		return
	streak_label.text = text
	streak_label.add_theme_color_override("font_color", Palette.GOLD if steps > 0 else Palette.FROST)
	streak_label.position = _streak_pos - Vector2(0, 4)
	create_tween().tween_property(streak_label, "position", _streak_pos, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Floating result text centred on `at` (a Scoring.score() result).
func popup(result: Dictionary, at: Vector2) -> void:
	var pct := roundi(result.error * 100.0)
	var text := "MISS %+d%%" % pct
	var color := Palette.RED
	if result.band == Scoring.PERFECT:
		text = "PERFECT! +%d" % result.coins
		color = Palette.GOLD
	elif result.band == Scoring.GOOD:
		text = "GOOD %+d%% +%d" % [pct, result.coins]
		color = Palette.GREEN
	elif result.band == Scoring.SPILL:
		text = "SPILLED!"
	var label := make_label(at - Vector2(100, 0), color)
	label.size = Vector2(200, 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	var tw := create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 24.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(label.queue_free)


func show_banner(text: String, seconds: float) -> void:
	banner_label.text = text
	banner_label.visible = true
	banner_label.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(maxf(seconds - 0.3, 0.0))
	_banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_callback(banner_label.hide)


func set_hint(text: String) -> void:
	hint_label.text = text


func toggle_debug() -> void:
	debug_label.visible = not debug_label.visible


func is_debug_visible() -> bool:
	return debug_label.visible


func set_debug(text: String) -> void:
	debug_label.text = text
```

- [ ] **Step 4: Create `round_summary.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://round_summary.gd" id="1_summary"]

[node name="RoundSummary" type="CanvasLayer"]
layer = 2
script = ExtResource("1_summary")
```

- [ ] **Step 5: Create `round_summary.gd`**

```gdscript
class_name RoundSummary
extends CanvasLayer
## End-of-round screen: glasses, perfects, best streak, coins this round and
## total. Space or clicking NEXT ROUND emits next_pressed and hides it.

signal next_pressed

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const SCREEN_W := 640.0

var _title: Label
var _body: Label
var _button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 8
	root.theme = theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(Palette.INK, 0.8)
	root.add_child(dim)
	_title = _centered_label(root, 96.0, Palette.GOLD, 16)
	_body = _centered_label(root, 136.0, Palette.FROST, 8)
	_button = Button.new()
	_button.text = "NEXT ROUND (SPACE)"
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_color_override("font_color", Palette.WHITE)
	_button.add_theme_color_override("font_hover_color", Palette.GOLD)
	_button.position = Vector2(SCREEN_W * 0.5 - 96.0, 248.0)
	_button.size = Vector2(192, 16)
	_button.pressed.connect(_next)
	root.add_child(_button)
	visible = false


func _centered_label(parent: Control, y: float, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.position = Vector2(0, y)
	l.size = Vector2(SCREEN_W, font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("line_spacing", 6)
	parent.add_child(l)
	return l


## `stats` keys: served, perfects, best_steps, coins.
func show_results(round_number: int, stats: Dictionary, total_coins: int) -> void:
	_title.text = "ROUND %d DONE" % round_number
	var rows := [
		["GLASSES", str(stats.served)],
		["PERFECT", str(stats.perfects)],
		["BEST STREAK", Hud.format_mult(stats.best_steps)],
		["COINS", "+%d" % stats.coins],
		["", ""],
		["TOTAL", str(total_coins)],
	]
	var lines: Array[String] = []
	for row in rows:
		lines.append("%-12s%6s" % row)
	_body.text = "\n".join(lines)
	visible = true


func hide_results() -> void:
	visible = false


func body_text() -> String:
	return _body.text


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_next()


func _next() -> void:
	visible = false
	next_pressed.emit()
```

- [ ] **Step 6: Add `parcel_count()` to `stream.gd`** (after `is_empty()`):

```gdscript
func parcel_count() -> int:
	return _parcels.size()
```

- [ ] **Step 7: Import and run the UI check**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=ui; echo "exit $?"`
Expected: `check_ui: OK`, `exit 0`.

- [ ] **Step 8: Switch `main.gd` to the Hud**

1. In `main.tscn`, add the ext_resource line `[ext_resource type="Script" path="res://hud.gd" id="8_hud"]` after the `7_layer` line, change `load_steps=10` to `load_steps=11`, and append at the end:
```
[node name="Hud" type="CanvasLayer" parent="."]
script = ExtResource("8_hud")
```
2. In `main.gd`: delete the vars `_hud`, `_coins_label`, `_status_label`, `_debug_label` and the functions `_build_hud`, `_label`, `_popup`, `_update_hud`; delete the `_build_hud()` call in `_ready()`; add `@onready var hud: Hud = $Hud` after `@onready var stream: Stream = $Stream`.
3. In `_serve()`, replace `_popup(result)` with `hud.popup(result, Vector2(GLASS_X, 168))`.
4. In `_unhandled_input`, replace the `KEY_F1:` branch body with `hud.toggle_debug()`.
5. In `_physics_process`, replace `_update_hud()` with `_refresh_hud()` and add this function:

```gdscript
func _refresh_hud() -> void:
	hud.set_coins(coins)
	hud.set_streak(_streak_steps)
	hud.set_hint("SERVING..." if _serve_queued else "HOLD DOWN: POUR   SPACE: SERVE   F1: DEBUG   R: RESET")
	if hud.is_debug_visible():
		var err := (glass.volume - glass.target) / glass.target * 100.0
		hud.set_debug("TILT %3d  FLOW %4d\nJUG  %4d/%d\nGLASS %4d/%d  %+.1f%%\nIN AIR %d" % [
			roundi(rad_to_deg(pourer.tilt)), roundi(pourer.flow),
			roundi(pourer.volume), roundi(pourer.full_volume),
			roundi(glass.volume), roundi(glass.target), err,
			stream.parcel_count(),
		])
```
6. In `_ready()`, after `pourer.position = ...`, add `hud.place_streak(Vector2(184, 196))`.

- [ ] **Step 9: Run every check plus a headless smoke run**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|FAIL|ERROR|outside"; "$GODOT" --headless --path . --quit-after 300 2>&1 | grep -E "ERROR|SCRIPT"; echo done`
Expected: every check `OK`, `outside the glass: 0`, no `ERROR`/`SCRIPT`.

- [ ] **Step 10: Commit**

```bash
git add hud.gd hud.gd.uid round_summary.gd round_summary.gd.uid round_summary.tscn stream.gd main.gd main.tscn tools/checks/check_ui.gd tools/checks/check_ui.gd.uid
git commit -m "feat: HUD (timer, coins, streak, banners) and round summary screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Round flow — phases, last call, autopilot, round check

**Files:**
- Create: `autopilot.gd`, `tools/checks/check_round.gd`
- Modify (full rewrite): `main.gd`, `main.tscn`
- Modify: `stream.gd` (`in_flight_volume()`), `tools/checks/check_bubbles.gd` (manual mode)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `class_name Main` (main.gd) with `enum Phase { INTRO, PLAYING, LAST_CALL, SUMMARY }`, consts `GLASS_POS`, `OFFSCREEN_X`, `INTRO_TIME`, `SWAP_OUT_TIME`, `SWAP_IN_TIME`, `LAST_CALL_IDLE`, `ACTIVE_SHARE`; fields `manual: bool`, `phase`, `phase_time`, `time_left`, `drink`, `streak_steps`, `round_stats: Dictionary`, `results: Array[Dictionary]`, `glass`, `pourer`, `stream`, `hud`, `summary`; methods `tick(dt: float, hold: bool)`, `request_serve()`, `start_round()`, `next_round()`, `is_swapping() -> bool`, `is_serving_phase() -> bool`, `_step_sim(dt, hold)`. `class_name Autopilot extends RefCounted` with `release_at: float` and `decide(main: Main) -> Dictionary` (`{hold: bool, serve: bool}`). `Stream.in_flight_volume() -> float`.

- [ ] **Step 1: Add `in_flight_volume()` to `stream.gd`** (after `parcel_count()`):

```gdscript
## Liquid poured but not landed yet (px²), including a drop still forming on the lip.
func in_flight_volume() -> float:
	var total := _pending
	for p in _parcels:
		total += p.vol
	return total
```

- [ ] **Step 2: Write the failing check** — create `tools/checks/check_round.gd`:

```gdscript
extends CheckBase
## Plays rounds headless at full simulation speed and checks the round rules
## from the slice 1 spec (phases, last call, auto-serve, refill, resets). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round

const DT := 1.0 / 60.0
var main: Main


func run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	_intro_ignores_input()
	_full_round_with_autopilot()
	_last_call_auto_serve()
	_last_call_tiny_pour_still_ends()
	_time_up_untouched_glass()
	_time_up_mid_swap()
	_empty_serve_ignored()
	_space_ignored_during_swap_and_refill()
	_next_round_resets_and_reads_stats()


func _fresh() -> void:
	GameState.stats = GameState.BASE_STATS.duplicate()
	GameState.round_number = 1
	main.start_round()


func _run(seconds: float, hold := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		main.tick(DT, hold)
		t += DT


func _to_playing() -> void:
	_fresh()
	_run(Main.INTRO_TIME + DT)


## Lets the autopilot play until a serve starts (the glass begins to slide out).
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


func _intro_ignores_input() -> void:
	_fresh()
	expect(main.phase == Main.Phase.INTRO, "a round starts in INTRO")
	_run(1.0, true)
	expect(main.phase == Main.Phase.INTRO and main.pourer.tilt == 0.0, "DOWN is ignored during INTRO")
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
	for r in main.results:
		total += r.coins
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
	var served_at := -1.0
	while main.phase == Main.Phase.LAST_CALL and t < 10.0:
		main.tick(DT, false)
		t += DT
		if served_at < 0.0 and main.results.size() == 1:
			served_at = t
	expect(main.results.size() == 1, "the last-call glass is served automatically")
	expect(served_at >= 3.0, "auto-serve waits for 3 s of idle (served after %.2f s)" % served_at)
	expect(main.phase == Main.Phase.SUMMARY, "the round ends after the last-call serve")
	expect(main.glass.position.x == Main.OFFSCREEN_X, "no new glass slides in after last call")


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
	expect(main.phase == Main.Phase.SUMMARY, "0:00 during a glass swap ends the round immediately")
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
	while main.is_swapping():
		main.request_serve()  # mashing Space
		main.tick(DT, false)
	_run(0.5)
	expect(main.results.size() == served, "Space mashed during a swap doesn't serve the next glass")
	main.glass.receive(Main.GLASS_POS.x, 500.0, 0.0)
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.tick(DT, false)
	expect(main.pourer.refilling, "a dry pitcher refills")
	main.request_serve()
	_run(0.2)
	expect(main.results.size() == served, "Space is ignored while refilling")


func _next_round_resets_and_reads_stats() -> void:
	_to_playing()
	main.streak_steps = 3
	main.time_left = 0.01
	_run(0.1, true)  # holding DOWN through the end of the round
	expect(main.phase == Main.Phase.SUMMARY, "the round ended")
	_run(1.5, true)
	expect(main.pourer.tilt < 0.001, "DOWN is ignored on the summary (pitcher upright)")
	GameState.stats.round_duration = 10.0
	GameState.stats.good_tol = 0.2
	var round_before: int = GameState.round_number
	main.next_round()
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "next_round starts the next INTRO")
	expect(main.streak_steps == 0 and main.results.is_empty(), "streak and results reset")
	expect(is_equal_approx(main.time_left, 10.0), "round_duration is read at round start")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "the pitcher starts full")
	expect(not main.summary.visible, "the summary is hidden")
	var levels := main.glass.band_levels()
	expect(is_equal_approx(levels.x, roundf(main.glass.level_for(main.glass.target * 1.2))), "band markers follow stats.good_tol")
	GameState.stats = GameState.BASE_STATS.duplicate()
```

- [ ] **Step 3: Run it to verify it fails**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round; echo "exit $?"`
Expected: compile errors (`Main`/`Autopilot` not declared); no `check_round: OK`.

- [ ] **Step 4: Create `autopilot.gd`**

```gdscript
class_name Autopilot
extends RefCounted
## A simple scripted player for --autoplay and tools/checks/check_round.gd: pours
## until the glass (plus liquid in the air) nears the line, releases early to
## allow for the overshoot, then serves once everything has landed.

## Release DOWN when this share of the target is in the glass or the air.
var release_at := 0.86
var _released := false


func decide(main: Main) -> Dictionary:
	var out := {"hold": false, "serve": false}
	if not main.is_serving_phase() or main.is_swapping():
		_released = false
		return out
	if main.pourer.refilling:
		return out
	var poured := main.glass.volume + main.stream.in_flight_volume()
	if not _released and poured < main.glass.target * release_at:
		out.hold = true
	else:
		_released = true
		if main.pourer.at_rest() and main.stream.is_empty():
			out.serve = true
	return out
```

- [ ] **Step 5: Rewrite `main.gd`** (full file):

```gdscript
class_name Main
extends Node2D
## Slice 1 round loop: INTRO → PLAYING → LAST_CALL → SUMMARY (see
## docs/superpowers/specs/2026-10-15-round-loop-design.md). All round logic
## advances only in tick(dt, hold), so check scripts can fast-forward it
## headless (`manual = true`); tweens are used for HUD visuals only.
##
## Dev flags (after `--`):
##   --sweep[=drink_id]   headless tuning table (pourer full and half full), then quit
##   --autoplay           the Autopilot plays: pours, serves, starts the next round
##   --shots=PREFIX       save PREFIX_<nn>.png every --shot-every=S seconds (default 1)
##   --quit=S             quit after S seconds

enum Phase { INTRO, PLAYING, LAST_CALL, SUMMARY }

const GLASS_POS := Vector2(256, 280)
const OFFSCREEN_X := -40.0
const INTRO_TIME := 1.5
const SWAP_OUT_TIME := 0.35
const SWAP_IN_TIME := 0.5
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
@onready var hud: Hud = $Hud
@onready var summary: RoundSummary = $RoundSummary

## When true, _physics_process does nothing and a check script drives tick().
var manual := false
var phase := Phase.INTRO
var phase_time := 0.0
var time_left := 0.0
var drink: DrinkDef
var streak_steps := 0
## This round's tallies: served, perfects, best_steps, coins.
var round_stats := {}
## Every glass scored this round (Scoring.score results).
var results: Array[Dictionary] = []

var _serve_queued := false
var _swap_t := -1.0  # < 0 when no glass swap is running
var _swap_reset := false
var _swap_brings_glass := true
var _idle := 0.0
var _autopilot: Autopilot
var _clock := 0.0
var _quit_at := INF
var _shot_prefix := ""
var _shot_every := 1.0
var _next_shot := 0.0
var _shot_index := 0


func _ready() -> void:
	drink = GameState.owned_drinks[0]
	glass.setup(drink)
	stream.set_drink(drink)
	pourer.setup(drink)
	pourer.position = GLASS_POS + drink.pourer_offset
	hud.place_streak(STREAK_POS)
	summary.next_pressed.connect(next_round)
	var args := _parse_args()
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
	_swap_t = -1.0
	_idle = 0.0
	stream.clear()
	glass.position = GLASS_POS
	glass.reset()
	pourer.reset()
	summary.hide_results()
	hud.show_banner("ROUND %d" % GameState.round_number, INTRO_TIME)
	_refresh_hud()


func next_round() -> void:
	if phase != Phase.SUMMARY:
		return
	GameState.round_number += 1
	start_round()


func is_swapping() -> bool:
	return _swap_t >= 0.0


func is_serving_phase() -> bool:
	return phase == Phase.PLAYING or phase == Phase.LAST_CALL


func request_serve() -> void:
	if not is_serving_phase() or is_swapping() or pourer.refilling:
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
	_step_swap(dt)
	if phase == Phase.PLAYING:
		time_left = maxf(time_left - dt, 0.0)
		if time_left <= 0.0:
			_on_time_up()
	if _serve_queued and not is_swapping() and not pourer.is_pouring() and stream.is_empty():
		_serve()
	if phase == Phase.LAST_CALL and not is_swapping():
		if hold or pourer.is_pouring() or not stream.is_empty():
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


func _serve() -> void:
	_serve_queued = false
	if glass.volume < glass.capacity * ACTIVE_SHARE:
		if phase == Phase.LAST_CALL:
			_finish_round()
		return
	var r := Scoring.score(glass.volume, glass.target, glass.spilled > 0.5, streak_steps, drink, GameState.stats)
	streak_steps = r.steps
	results.append(r)
	round_stats.served += 1
	if r.band == Scoring.PERFECT:
		round_stats.perfects += 1
	round_stats.best_steps = maxi(round_stats.best_steps, streak_steps)
	round_stats.coins += r.coins
	GameState.coins += r.coins
	hud.popup(r, POPUP_POS)
	_swap_t = 0.0
	_swap_reset = false
	_swap_brings_glass = phase == Phase.PLAYING


## Slides the served glass out, empties it off-screen, and (unless the round
## is ending) slides it back in as the next glass.
func _step_swap(dt: float) -> void:
	if _swap_t < 0.0:
		return
	_swap_t += dt
	if _swap_t < SWAP_OUT_TIME:
		glass.position.x = Tween.interpolate_value(GLASS_POS.x, OFFSCREEN_X - GLASS_POS.x, _swap_t, SWAP_OUT_TIME, Tween.TRANS_QUAD, Tween.EASE_IN)
		return
	if not _swap_reset:
		_swap_reset = true
		glass.position.x = OFFSCREEN_X
		if not _swap_brings_glass:
			_swap_t = -1.0
			if phase == Phase.LAST_CALL:
				_finish_round()
			return
		glass.reset()
	var t_in := _swap_t - SWAP_OUT_TIME
	if t_in >= SWAP_IN_TIME:
		glass.position.x = GLASS_POS.x
		_swap_t = -1.0
		return
	glass.position.x = Tween.interpolate_value(OFFSCREEN_X, GLASS_POS.x - OFFSCREEN_X, t_in, SWAP_IN_TIME, Tween.TRANS_BACK, Tween.EASE_OUT)


func _finish_round() -> void:
	_enter(Phase.SUMMARY)
	_serve_queued = false
	_swap_brings_glass = false
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
	var d: DrinkDef = GameState.owned_drinks[0]
	for owned in GameState.owned_drinks:
		if String(owned.id) == drink_id:
			d = owned
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

- [ ] **Step 6: Rewrite `main.tscn`** (full file — adds `RoundSummary`):

```
[gd_scene load_steps=12 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]
[ext_resource type="Texture2D" path="res://art/background.png" id="2_bg"]
[ext_resource type="Script" path="res://glass.gd" id="3_glass"]
[ext_resource type="Script" path="res://pourer.gd" id="4_pourer"]
[ext_resource type="Script" path="res://stream.gd" id="5_stream"]
[ext_resource type="Shader" path="res://liquid.gdshader" id="6_liquid"]
[ext_resource type="Script" path="res://draw_layer.gd" id="7_layer"]
[ext_resource type="Script" path="res://hud.gd" id="8_hud"]
[ext_resource type="PackedScene" path="res://round_summary.tscn" id="9_summary"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_glass"]
shader = ExtResource("6_liquid")
shader_parameter/tint = Color(0, 0.6, 0.858824, 1)
shader_parameter/tint_strength = 0.5
shader_parameter/refraction_px = 1.0
shader_parameter/lens_strength = 0.3
shader_parameter/dither_levels = 4.0
shader_parameter/highlight = Color(1, 1, 1, 1)
shader_parameter/highlight_strength = 0.45

[sub_resource type="ShaderMaterial" id="ShaderMaterial_pourer"]
shader = ExtResource("6_liquid")
shader_parameter/tint = Color(0, 0.6, 0.858824, 1)
shader_parameter/tint_strength = 0.5
shader_parameter/refraction_px = 1.0
shader_parameter/lens_strength = 0.25
shader_parameter/dither_levels = 4.0
shader_parameter/highlight = Color(1, 1, 1, 1)
shader_parameter/highlight_strength = 0.35

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Background" type="Sprite2D" parent="."]
texture = ExtResource("2_bg")
centered = false

[node name="Glass" type="Node2D" parent="."]
position = Vector2(256, 280)
script = ExtResource("3_glass")

[node name="Liquid" type="Node2D" parent="Glass"]
material = SubResource("ShaderMaterial_glass")
script = ExtResource("7_layer")

[node name="Front" type="Node2D" parent="Glass"]
script = ExtResource("7_layer")

[node name="Stream" type="Node2D" parent="."]
script = ExtResource("5_stream")

[node name="Pourer" type="Node2D" parent="."]
position = Vector2(270, 175)
script = ExtResource("4_pourer")

[node name="Liquid" type="Node2D" parent="Pourer"]
material = SubResource("ShaderMaterial_pourer")
script = ExtResource("7_layer")

[node name="Front" type="Node2D" parent="Pourer"]
script = ExtResource("7_layer")

[node name="Hud" type="CanvasLayer" parent="."]
script = ExtResource("8_hud")

[node name="RoundSummary" parent="." instance=ExtResource("9_summary")]
```

- [ ] **Step 7: Put the bubble check in manual mode** — in `tools/checks/check_bubbles.gd`, in `run()` right after `add_child(main)` add `main.manual = true`.

- [ ] **Step 8: Import and run the round check**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round; echo "exit $?"`
Expected: `check_round: OK`, `exit 0`. If the autopilot serves fewer than 4 glasses, check `release_at` against the sweep's overshoot rather than loosening the assertion.

- [ ] **Step 9: Run every check, the sweep, and a headless smoke run**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|FAIL|ERROR|outside"; "$GODOT" --headless --path . -- --sweep 2>&1 | head -3; "$GODOT" --headless --path . --quit-after 600 -- --autoplay 2>&1 | grep -E "ERROR|SCRIPT"; echo done`
Expected: every check `OK`, `outside the glass: 0`, the sweep header line prints, no `ERROR`/`SCRIPT` from 10 s of autoplay.

- [ ] **Step 10: Commit**

```bash
git add autopilot.gd autopilot.gd.uid main.gd main.tscn stream.gd tools/checks/check_round.gd tools/checks/check_round.gd.uid tools/checks/check_bubbles.gd
git commit -m "feat: round flow with intro, timer, last call, summary and autopilot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Visual pass, docs, final verification

**Files:**
- Modify: `CLAUDE.md`, `README.md`; possibly colors/sizes in `glass.gd` (`_draw_band`, `_draw_fill_line`) and `hud.gd` positions if screenshots show problems.

**Interfaces:**
- Consumes: the finished slice.
- Produces: docs describing the round loop; screenshots reviewed.

- [ ] **Step 1: Capture an autoplayed round**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; S="$TMPDIR/pour_task7"; rm -rf "$S"; mkdir -p "$S"; "$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --shots="$S/round" --shot-every=1.5 --quit=40; python3 -c "
import glob
from PIL import Image
files = sorted(glob.glob('$S/round_*.png'))
ims = [Image.open(f) for f in files]
cols = 4
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (640 * cols, 360 * rows))
for i, im in enumerate(ims): sheet.paste(im, ((i % cols) * 640, (i // cols) * 360))
sheet.save('$S/sheet.png'); print(len(ims), 'shots ->', '$S/sheet.png')"`
Read `sheet.png` (and individual `round_NN.png` files as needed).
Expected, and fix anything that fails: "ROUND 1" banner at the start; timer `0:30` counting down at top center, red in the last 5 s; `COINS n` top left; the `xN` streak left of the glass changing after serves; result popups; the white fill line and the band bracket clearly visible against tiles and water; "REFILLING..." hint at least once; "LAST CALL!" banner near 0:00; the summary screen with GLASSES / PERFECT / BEST STREAK / COINS / TOTAL and NEXT ROUND; then "ROUND 2". Text must not overlap the glass, pitcher, or each other.

- [ ] **Step 2: Update `CLAUDE.md`** — rewrite the sections that describe the prototype so they describe slice 1:
  - *Project Overview:* current state = slice 1 round loop implemented (cite the spec and this plan); next slices: second drink + mixed rounds, then the shop.
  - *Commands:* replace the check list with all seven checks (`check_drinks`, `check_scoring`, `check_glass`, `check_pourer`, `check_ui`, `check_round`, `check_bubbles`), `--sweep[=drink_id]`, `--autoplay --shots=PREFIX --shot-every=S --quit=S`; document the runner (`tools/run_check.gd -- --check=<name>|all`, checks in `tools/checks/` extend `CheckBase`) and why it exists: a `--script` file can't reference `GameState` or any class that uses it, so checks are loaded after autoloads; a check also fails on any logged script error.
  - *Architecture:* add `DrinkDef`/`drinks/*.tres` (drinks are data; shapes drive both drawing and physics), `GameState` (coins, round, owned drinks, `stats` upgrade seam with the six keys), `Scoring` (pure rules; payout uses the pre-glass multiplier), `Pourer` (renamed from Pitcher; auto-refill), the `Main` phase machine (`tick()` is the only place round logic advances; `manual` mode; serve queue; last call; swap), `Hud`, `RoundSummary`, `Autopilot`; update the tuning baseline with Task 4's final sweep numbers.
  - Keep *Visual identity*, *Gotchas*, *Conventions*; add the fill-line/band style to *Visual identity*.

- [ ] **Step 3: Update `README.md`** — controls (hold ↓ pour, Space serve, F1 debug, Esc quit; R no longer exists), the round rules in three lines (30 s timer, streak x1→x3, last call), and the new dev flags; drop "(spike — throwaway)" from the title.

- [ ] **Step 4: Final verification**

Run: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . --import > /dev/null 2>&1; "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all 2>&1 | grep -E "check_|FAIL|ERROR|outside"; git status --short`
Expected: seven `OK` lines (bubbles prints `outside the glass: 0`), and `git status` shows only the files you meant to change.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md glass.gd hud.gd
git commit -m "docs: describe the slice 1 round loop; visual pass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Hand over for playtest** — tell the controller the slice is ready; the controller launches `"$GODOT" --path .` for the user and asks how a round feels (timer pressure, streak, refill timing, last call, fill line visibility).
