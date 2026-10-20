extends CheckBase
## Checks the pure scoring rules: steps from rows off the line, fixed payouts,
## the streak, the spill penalty, the garnish bonus and the upgrades' bonus. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=scoring


func run() -> void:
	var water: DrinkDef = load("res://drinks/water.tres")
	var wine: DrinkDef = load("res://drinks/wine.tres")
	var stats := {"perfect_rows": 1, "good_rows": 3, "ok_rows": 6, "coin_mult": 1.0, "streak_start": 2, "streak_step": 0.1, "streak_max": 3.0}
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
	# Streak: GOOD-or-better glasses in a row; GOOD ENOUGH holds it, MISS/SPILL reset it.
	eq(Scoring.next_streak(0, Scoring.GOOD), 1, "GOOD adds a glass to the streak")
	eq(Scoring.next_streak(0, Scoring.PERFECT), 1, "PERFECT adds one too")
	eq(Scoring.next_streak(5, Scoring.GOOD_ENOUGH), 5, "GOOD ENOUGH holds the streak")
	eq(Scoring.next_streak(5, Scoring.MISS), 0, "MISS resets")
	eq(Scoring.next_streak(5, Scoring.SPILL), 0, "SPILL resets")
	# Multiplier: x1 until streak_start glasses in a row, then 1 + streak_step per glass, capped.
	var mults := []
	for n in [0, 1, 2, 3, 10, 19, 20, 25]:
		mults.append(snappedf(Scoring.multiplier(n, stats), 0.01))
	eq(mults, [1.0, 1.0, 1.2, 1.3, 2.0, 2.9, 3.0, 3.0], "x1, x1, x1.2, x1.3 ... x3 after 20 glasses, capped")
	var faster := stats.duplicate()
	faster.streak_step = 0.2
	eq(snappedf(Scoring.multiplier(3, faster), 0.01), 1.6, "streak_step comes from stats (a shop upgrade)")
	# score(): pays at the multiplier from before this glass; a spill's cost isn't multiplied.
	var first := Scoring.score(0, 0.0, false, 0, water, stats)
	eq([first.band, first.coins, first.streak], [Scoring.PERFECT, 10, 1], "score: the first PERFECT pays x1 and starts the streak")
	eq(Scoring.score(1, 0.0, false, 1, water, stats).coins, 10, "score: the second still pays x1")
	eq(Scoring.score(0, 0.0, false, 2, water, stats).coins, 12, "score: the third pays x1.2")
	eq(Scoring.score(3, 0.05, false, 3, water, stats).coins, 8, "score: GOOD at x1.3 pays round(7.8) = 8")
	var held := Scoring.score(5, -0.08, false, 4, water, stats)
	eq([held.coins, held.streak], [4, 4], "score: GOOD ENOUGH at x1.4 pays round(4.2) = 4 and keeps the streak")
	var spill := Scoring.score(0, 0.1, true, 20, wine, stats)
	eq([spill.band, spill.coins, spill.streak], [Scoring.SPILL, -9, 0], "score: a wine spill at x3 costs 9, unmultiplied, and resets the streak")
	near(Scoring.score(9, -0.1, false, 0, water, stats).error, -0.1, "score: passes the volume error through")
	eq(Scoring.score(9, -0.1, false, 0, water, stats).rows, 9, "score: ...and the rows")
	# Garnishes: a share of each step's coins, rounded to whole coins before the streak.
	var ice: GarnishDef = load("res://garnishes/ice.tres")
	var lime: GarnishDef = load("res://garnishes/lime.tres")
	var with_ice: Array[GarnishDef] = [ice]
	var with_lime: Array[GarnishDef] = [lime]
	var both: Array[GarnishDef] = [ice, lime]
	var table := []
	for gs in [with_ice, with_lime, both]:
		for b in [Scoring.PERFECT, Scoring.GOOD, Scoring.GOOD_ENOUGH]:
			table.append(Scoring.garnished_coins(Scoring.base_coins(b, water), gs))
	eq(table, [12, 7, 4, 13, 8, 4, 15, 9, 5], "water pays 12/7/4 with ice, 13/8/4 with lime, 15/9/5 with both")
	eq(Scoring.score(0, 0.0, false, 5, water, stats, both).coins, roundi(15 * 1.5), "a garnished PERFECT at x1.5 pays round(15 x 1.5)")
	eq(Scoring.score(0, 0.1, true, 0, water, stats, both).coins, -6, "a garnished spill still costs 6")
	eq(Scoring.score(9, 0.0, false, 0, water, stats, both).coins, 0, "a garnished MISS pays 0")
	eq(Scoring.score(0, 0.0, false, 0, water, stats, with_ice).garnishes, [&"ice"], "score records the garnishes")
	eq(Scoring.score(0, 0.0, false, 0, water, stats).garnishes, [], "...none by default")
	# Upgrades: always on, their bonus adds to the garnishes'; vintage replaces premium (GameState).
	var sparkling: UpgradeDef = load("res://upgrades/sparkling.tres")
	var premium: UpgradeDef = load("res://upgrades/premium.tres")
	var vintage: UpgradeDef = load("res://upgrades/vintage.tres")
	var bubbly: Array[UpgradeDef] = [sparkling]
	var none: Array[GarnishDef] = []
	var pays := []
	for gs: Array[GarnishDef] in [none, both]:
		for b in [Scoring.PERFECT, Scoring.GOOD, Scoring.GOOD_ENOUGH]:
			pays.append(Scoring.garnished_coins(Scoring.base_coins(b, water), gs, bubbly))
	eq(pays, [14, 8, 4, 19, 11, 6], "sparkling water pays 14/8/4, with ice and lime 19/11/6")
	var wine_pays := []
	var premium_only: Array[UpgradeDef] = [premium]
	var vintage_only: Array[UpgradeDef] = [vintage]
	for ups: Array[UpgradeDef] in [premium_only, vintage_only]:
		for b in [Scoring.PERFECT, Scoring.GOOD, Scoring.GOOD_ENOUGH]:
			wine_pays.append(Scoring.garnished_coins(Scoring.base_coins(b, wine), none, ups))
	eq(wine_pays, [21, 13, 7, 24, 14, 8], "premium wine pays 21/13/7, vintage 24/14/8")
	eq(Scoring.score(0, 0.0, false, 0, water, stats, both, bubbly).coins, 19, "score: garnishes and upgrades add up")
	eq(Scoring.score(0, 0.1, true, 0, water, stats, both, bubbly).coins, -6, "a sparkling spill still costs 6")
	eq(Scoring.score(9, 0.0, false, 0, water, stats, none, bubbly).coins, 0, "a sparkling MISS pays 0")
	stats.coin_mult = 2.0
	eq(Scoring.score(0, 0.0, false, 0, water, stats).coins, 20, "score: coin_mult doubles a payout")
	eq(Scoring.score(0, 0.0, true, 0, water, stats).coins, -6, "score: ...but not a spill's cost")
