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
