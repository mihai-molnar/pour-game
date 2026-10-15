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
