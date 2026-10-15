class_name Scoring
## Pure scoring rules. A glass is judged by how many pixel rows its settled
## surface sits from the fill line, as drawn (Glass.rows_from_line): each step
## pays a fixed amount from the DrinkDef and an overflow costs coins. No scene
## dependencies, so tools/checks/check_scoring.gd tests them directly.

const PERFECT := &"PERFECT"
const GOOD := &"GOOD"
const GOOD_ENOUGH := &"GOOD_ENOUGH"
const MISS := &"MISS"
const SPILL := &"SPILL"
## Streak steps map to x1, x1.5, x2, x2.5, x3.
const MAX_STEPS := 4


## The step for a surface `rows` rows from the line; the limits are stats'
## perfect_rows / good_rows / ok_rows (inclusive).
static func band(rows: int, spilled: bool, stats: Dictionary) -> StringName:
	if spilled:
		return SPILL
	if rows <= stats.perfect_rows:
		return PERFECT
	if rows <= stats.good_rows:
		return GOOD
	if rows <= stats.ok_rows:
		return GOOD_ENOUGH
	return MISS


## Coins for a step before the streak multiplier and coin_mult; negative for a spill.
static func base_coins(b: StringName, def: DrinkDef) -> int:
	if b == PERFECT:
		return def.perfect_coins
	if b == GOOD:
		return def.good_coins
	if b == GOOD_ENOUGH:
		return def.ok_coins
	if b == SPILL:
		return -def.spill_coins
	return 0


static func next_steps(steps: int, b: StringName) -> int:
	if b == PERFECT:
		return mini(steps + 2, MAX_STEPS)
	if b == GOOD:
		return mini(steps + 1, MAX_STEPS)
	if b == GOOD_ENOUGH:
		return steps  # a safe pour holds the streak
	return 0


static func multiplier(steps: int) -> float:
	return 1.0 + 0.5 * clampi(steps, 0, MAX_STEPS)


## Earnings scale with the streak before this glass and coin_mult; a spill's cost doesn't.
static func paid_coins(base: int, steps_before: int, coin_mult: float) -> int:
	if base <= 0:
		return base
	return roundi(base * multiplier(steps_before) * coin_mult)


## Scores one served glass. `rows` = rows from the line as drawn; `error` = the
## signed volume error relative to the target (passed through for tools and the
## debug readout). `coins` is the nominal payout — negative for a spill; Main
## stops the coin total at 0. `steps` is the streak after this glass.
static func score(rows: int, error: float, spilled: bool, steps_before: int, def: DrinkDef, stats: Dictionary) -> Dictionary:
	var b := band(rows, spilled, stats)
	return {
		"band": b,
		"rows": rows,
		"error": error,
		"coins": paid_coins(base_coins(b, def), steps_before, stats.coin_mult),
		"steps": next_steps(steps_before, b),
	}
