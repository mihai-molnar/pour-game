extends CheckBase
## Validates every drink in res://drinks/ and its garnishes, the shop
## catalog and the GameState defaults, and seeded picks.


func run() -> void:
	var expected := {
		"round_duration": 30.0, "perfect_rows": 1, "good_rows": 3, "ok_rows": 6,
		"streak_start": 2, "streak_step": 0.1, "streak_max": 3.0,
		"coin_mult": 1.0, "pour_speed_mult": 1.0, "refill_time": 1.0,
	}
	for key in expected:
		eq(GameState.stats.get(key), expected[key], "stats.%s" % key)
	eq(GameState.BASE_STATS, expected, "BASE_STATS")
	expect(GameState.coins == 0 and GameState.round_number == 1, "session starts at 0 coins, round 1")
	expect(GameState.owned_drinks.size() == 1 and GameState.owned_drinks[0].id == &"water", "owned_drinks is [water]")

	# Typed locals: a preloaded .tres const may only be known as Resource to the analyzer.
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.WINE
	expect(wine.id == &"wine", "GameState.WINE is wine")
	expect(GameState.menu.size() == 1 and GameState.menu[0] == water, "menu starts as [water]")
	expect(GameState.owned_garnishes.is_empty() and GameState.new_drinks.is_empty(), "nothing bought yet")
	expect(GameState.DRINKS.size() == 2 and GameState.DRINKS[0] == water and GameState.DRINKS[1] == wine, "the catalog is water, wine")
	eq([water.price, wine.price], [0, 80], "water is free, wine costs 80")
	eq(water.garnishes.map(func(g: GarnishDef) -> StringName: return g.id), [&"ice", &"lime"], "water's garnishes are ice and lime")
	eq(wine.garnishes.size(), 0, "wine has none yet")
	var ice: GarnishDef = water.garnishes[0]
	var lime: GarnishDef = water.garnishes[1]
	eq([ice.price, ice.bonus, ice.key, ice.kind], [10, 0.2, KEY_UP, GarnishDef.Kind.ICE], "ice: 10 coins, +20 %, UP, falls in")
	eq([lime.price, lime.bonus, lime.key, lime.kind], [15, 0.3, KEY_LEFT, GarnishDef.Kind.RIM], "lime: 15 coins, +30 %, LEFT, on the rim")
	eq([ice.description, lime.description], ["Water pays +20%", "Water pays +30%"], "card lines")
	eq([ice.display_name, lime.display_name], ["Ice", "Lime"], "garnish names")
	eq([ice.cube_count, ice.cube_size], [2, 10.4], "ice: two cubes of 10.4 px")
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
	main.glass.setup(water)
	var floor_w: int = main.glass._row_area[main.glass._row_area.size() - 1]
	expect(ice.cube_count * ice.cube_size < floor_w, "...side by side they fit the tumbler's floor (%d px)" % floor_w)
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
	expect(d.perfect_coins >= d.good_coins and d.good_coins >= d.ok_coins and d.ok_coins > 0, "%s: coins PERFECT >= GOOD >= GOOD ENOUGH > 0" % n)
	expect(d.spill_coins > 0, "%s: a spill costs coins" % n)
	for p in d.glass_outer:
		expect(p.y <= 0.0, "%s: the glass sits on its origin (outer y <= 0)" % n)
	_inside(d.glass_interior, d.glass_outer, "%s: glass interior inside outer" % n)
	_inside(d.pourer_interior, d.pourer_outer, "%s: pourer interior inside outer" % n)

	# The whole GOOD ENOUGH band above the line must be reachable without spilling.
	glass.setup(d)
	var above := glass.rows_from_line(glass.capacity)
	expect(above >= GameState.BASE_STATS.ok_rows, "%s: a brim-full glass is at least ok_rows over the line (%d rows)" % [n, above])
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
