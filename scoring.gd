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
