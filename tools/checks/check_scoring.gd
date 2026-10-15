extends CheckBase
## Checks the pure scoring rules: steps from rows off the line, fixed payouts,
## the streak, and the spill penalty. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=scoring


func run() -> void:
	var water: DrinkDef = load("res://drinks/water.tres")
	var wine: DrinkDef = load("res://drinks/wine.tres")
	var stats := {"perfect_rows": 1, "good_rows": 3, "ok_rows": 6, "coin_mult": 1.0}
	# Steps by rows from the line (as drawn); limits are inclusive.
	eq(Scoring.band(0, false, stats), Scoring.PERFECT, "on the line is PERFECT")
	eq(Scoring.band(1, false, stats), Scoring.PERFECT, "1 row off is PERFECT")
	eq(Scoring.band(2, false, stats), Scoring.GOOD, "2 rows off is GOOD")
	eq(Scoring.band(3, false, stats), Scoring.GOOD, "3 rows off is GOOD")
	eq(Scoring.band(4, false, stats), Scoring.GOOD_ENOUGH, "4 rows off is GOOD ENOUGH")
	eq(Scoring.band(6, false, stats), Scoring.GOOD_ENOUGH, "6 rows off is GOOD ENOUGH")
	eq(Scoring.band(7, false, stats), Scoring.MISS, "7 rows off is a MISS")
	eq(Scoring.band(0, true, stats), Scoring.SPILL, "a spill beats a perfect level")
	var wider := stats.duplicate()
	wider.ok_rows = 8
	eq(Scoring.band(7, false, wider), Scoring.GOOD_ENOUGH, "the row limits come from stats (a wider-tolerance upgrade)")
	# Fixed payouts per step; a spill costs coins.
	eq(Scoring.base_coins(Scoring.PERFECT, water), 10, "water PERFECT pays 10")
	eq(Scoring.base_coins(Scoring.GOOD, water), 6, "water GOOD pays 6")
	eq(Scoring.base_coins(Scoring.GOOD_ENOUGH, water), 3, "water GOOD ENOUGH pays 3")
	eq(Scoring.base_coins(Scoring.MISS, water), 0, "MISS pays 0")
	eq(Scoring.base_coins(Scoring.SPILL, water), -6, "a water spill costs 6")
	eq([Scoring.base_coins(Scoring.PERFECT, wine), Scoring.base_coins(Scoring.GOOD, wine), Scoring.base_coins(Scoring.GOOD_ENOUGH, wine), Scoring.base_coins(Scoring.SPILL, wine)],
		[15, 9, 5, -9], "wine pays 15 / 9 / 5 and a spill costs 9")
	# Streak.
	eq(Scoring.next_steps(0, Scoring.GOOD), 1, "GOOD adds one step")
	eq(Scoring.next_steps(0, Scoring.PERFECT), 2, "PERFECT adds two steps")
	eq(Scoring.next_steps(3, Scoring.GOOD_ENOUGH), 3, "GOOD ENOUGH holds the streak")
	eq(Scoring.next_steps(3, Scoring.PERFECT), 4, "steps cap at 4")
	eq(Scoring.next_steps(4, Scoring.GOOD), 4, "capped stays capped")
	eq(Scoring.next_steps(4, Scoring.MISS), 0, "MISS resets")
	eq(Scoring.next_steps(3, Scoring.SPILL), 0, "SPILL resets")
	eq(Scoring.multiplier(0), 1.0, "x1 at 0 steps")
	eq(Scoring.multiplier(1), 1.5, "x1.5 at 1 step")
	eq(Scoring.multiplier(4), 3.0, "x3 at 4 steps")
	eq(Scoring.multiplier(9), 3.0, "multiplier caps at x3")
	# score(): the payout uses the multiplier from before this glass; a spill's cost isn't multiplied.
	var first := Scoring.score(0, 0.0, false, 0, water, stats)
	eq(first.band, Scoring.PERFECT, "score: on the line is PERFECT")
	eq(first.coins, 10, "score: the first PERFECT pays x1")
	eq(first.steps, 2, "score: the first PERFECT moves the streak to 2 steps")
	eq(Scoring.score(1, 0.0, false, first.steps, water, stats).coins, 20, "score: the second PERFECT pays x2")
	eq(Scoring.score(3, 0.05, false, 1, water, stats).coins, 9, "score: GOOD at x1.5 pays 9")
	eq(Scoring.score(5, -0.08, false, 3, water, stats).coins, 8, "score: GOOD ENOUGH at x2.5 pays round(7.5) = 8")
	eq(Scoring.score(5, -0.08, false, 3, water, stats).steps, 3, "score: ...and keeps the streak")
	var spill := Scoring.score(0, 0.1, true, 4, wine, stats)
	eq([spill.band, spill.coins, spill.steps], [Scoring.SPILL, -9, 0], "score: a wine spill at x3 costs 9, unmultiplied, and resets the streak")
	near(Scoring.score(9, -0.1, false, 0, water, stats).error, -0.1, "score: passes the volume error through")
	eq(Scoring.score(9, -0.1, false, 0, water, stats).rows, 9, "score: ...and the rows")
	stats.coin_mult = 2.0
	eq(Scoring.score(0, 0.0, false, 0, water, stats).coins, 20, "score: coin_mult doubles a payout")
	eq(Scoring.score(0, 0.0, true, 0, water, stats).coins, -6, "score: ...but not a spill's cost")
