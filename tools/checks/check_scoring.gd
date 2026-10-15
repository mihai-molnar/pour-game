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
