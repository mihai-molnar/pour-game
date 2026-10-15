extends CheckBase
## Checks the glass: exact capacity and fixed target per drink, band levels
## following stats.good_tol, geometry helpers, the fill-line tick on a glass
## that narrows toward the rim, setup leaving no state behind, and the
## arrival. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass

const DT := 1.0 / 60.0
const HOME := Vector2(256, 280)


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	glass.place(HOME)
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
	expect(_tint_clear(glass), "wall tint polygons leave the interior clear")
	var walls := glass.outer_x_at(-37.0)
	expect(walls.is_equal_approx(Vector2(-19, 19)), "outer walls at mid height (got %s)" % walls)
	eq(glass.left_tick(), Vector2i(-25, -23), "water: the fill-line tick is unchanged")

	_check_wine(glass, wine)
	glass.setup(water)
	expect(glass.capacity == 2346.0 and is_equal_approx(glass.target, want), "back to water: same capacity and target")
	expect(glass.opening_world() == Vector2(237, 275), "back to water: same opening (got %s)" % glass.opening_world())
	expect(glass.volume == 0.0 and glass._row_area.size() == 69, "back to water: empty, water's 69 rows (got %d)" % glass._row_area.size())
	_check_arrival(glass, water)


func _check_wine(glass: Glass, wine: DrinkDef) -> void:
	glass.setup(wine)
	expect(glass.capacity == 3100.0, "wine: capacity = interior pixel count (got %d)" % glass.capacity)
	expect(is_equal_approx(glass.target, 0.53 * glass.capacity), "wine: target = fill_fraction x capacity")
	var prev := glass.level_for(0.0)
	var rising := true
	var v := 25.0
	while v <= glass.capacity:
		var y := glass.level_for(v)
		rising = rising and y < prev
		prev = y
		v += 25.0
	expect(rising, "wine: the level rises with every 25 px² poured")
	expect(is_equal_approx(glass.rim_y_world(), 184.0), "wine: rim at y=184 (got %.1f)" % glass.rim_y_world())
	expect(glass.opening_world() == Vector2(238, 274), "wine: opening (got %s)" % glass.opening_world())
	eq(glass.left_tick(), Vector2i(-30, -28), "wine: the tick runs from the bracket to the bulging wall")
	expect(_tint_clear(glass), "wine: wall tint polygons leave the bowl clear")


func _check_arrival(glass: Glass, water: DrinkDef) -> void:
	var landed: Array[Vector2] = []
	glass.landed.connect(func(at: Vector2) -> void: landed.append(at))
	var front: Node2D = glass.get_node("Front")
	glass.receive(HOME.x, 500.0, 0.0)
	glass.arrive(water, HOME)
	expect(glass.volume == 0.0, "an arriving glass is empty")
	near(glass.position.x, Glass.OFFSCREEN_X, "it starts off-screen left")
	expect(glass.is_arriving() and glass.visible, "...visible and arriving")
	var t := 0.0
	var leaned := false
	var node_rotated := false
	while glass.is_arriving() and t < 1.0:
		glass.step(DT)
		t += DT
		leaned = leaned or absf(front.rotation) > 0.01
		node_rotated = node_rotated or glass.rotation != 0.0
	expect(absf(t - Arrival.ARRIVE_TIME) <= DT + 1e-6, "the slide takes ARRIVE_TIME (%.3f s)" % t)
	expect(glass.position == HOME, "it ends exactly at home (%s)" % glass.position)
	eq(landed.size(), 1, "landed fires once")
	if landed.size() == 1:
		expect(landed[0].is_equal_approx(HOME + Vector2(17, 0)), "...at the leading foot corner (%s)" % landed[0])
	while t < 1.0:
		glass.step(DT)
		t += DT
		leaned = leaned or absf(front.rotation) > 0.01
		node_rotated = node_rotated or glass.rotation != 0.0
	expect(leaned and not node_rotated, "the lean turns the drawing, never the node")
	eq(front.rotation, 0.0, "upright after the wobble")
	glass.vanish()
	expect(not glass.visible and not glass.is_arriving(), "vanish hides the glass")
	glass.place(HOME)
	expect(glass.visible and glass.position == HOME, "place shows it at home at once")


func _tint_clear(glass: Glass) -> bool:
	var tint := DrawLayer.wall_polygons(glass.outer, glass.interior)
	var c := Vector2.ZERO
	for p in glass.interior:
		c += p
	c /= glass.interior.size()
	for w in tint:
		if Geometry2D.is_point_in_polygon(c, w):
			return false
	return not tint.is_empty()
