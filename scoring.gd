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


## The streak: GOOD-or-better glasses in a row. GOOD ENOUGH holds it; MISS
## and SPILL reset it.
static func next_streak(streak: int, b: StringName) -> int:
	if b == PERFECT or b == GOOD:
		return streak + 1
	if b == GOOD_ENOUGH:
		return streak
	return 0


## The coin multiplier for a streak: x1 until stats.streak_start glasses in a
## row, then 1 + streak_step per glass (x1.2 after 2, x1.3 after 3 ...), capped
## at streak_max.
static func multiplier(streak: int, stats: Dictionary) -> float:
	if streak < stats.streak_start:
		return 1.0
	return minf(1.0 + stats.streak_step * streak, stats.streak_max)


## Earnings scale with the streak before this glass and coin_mult; a spill's cost doesn't.
static func paid_coins(base: int, streak_before: int, stats: Dictionary) -> int:
	if base <= 0:
		return base
	return roundi(base * multiplier(streak_before, stats) * stats.coin_mult)


## Scores one served glass. `rows` = rows from the line as drawn; `error` = the
## signed volume error relative to the target (passed through for tools and the
## debug readout). `coins` is the nominal payout — negative for a spill; Main
## stops the coin total at 0. `streak` is the streak after this glass.
static func score(rows: int, error: float, spilled: bool, streak_before: int, def: DrinkDef, stats: Dictionary) -> Dictionary:
	var b := band(rows, spilled, stats)
	return {
		"band": b,
		"rows": rows,
		"error": error,
		"coins": paid_coins(base_coins(b, def), streak_before, stats),
		"streak": next_streak(streak_before, b),
	}
