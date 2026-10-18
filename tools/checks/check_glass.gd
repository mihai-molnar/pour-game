extends CheckBase
## Checks the glass: exact capacity and fixed target per drink, rows from the
## line and the scoring band in rows, geometry helpers, where the fill line and
## band marks are drawn (on the rows scoring measures), the drawn liquid
## matching the volume and level, setup leaving no state behind, and the
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
	eq(glass.rows_from_line(glass.target), 0, "the target volume is on the line")
	eq(glass.rows_from_line(glass.capacity), 6, "a brim-full tumbler is 6 rows over the line")
	eq(glass.rows_from_line(0.0), 63, "an empty tumbler is 63 rows under it")
	var one_row := float(glass._row_area[roundi(glass.target_y()) - glass._y0])
	eq(glass.rows_from_line(glass.target + 2.0 * one_row), 2, "two rows' worth more is 2 rows over")
	eq(glass.band_rows(3), Vector2i(-71, -65), "the ±3 row band around the line at y -68")
	eq(glass.band_rows(6), Vector2i(-74, -62), "the ±6 row band reaches the rim row")
	eq(glass.band_rows(9), Vector2i(-74, -59), "...and is cut at the rim")
	expect(glass.opening_world() == Vector2(237, 275), "opening at the rim (got %s)" % glass.opening_world())
	expect(is_equal_approx(glass.rim_y_world(), 206.0), "rim at y=206 (got %.1f)" % glass.rim_y_world())
	expect(_tint_clear(glass), "wall tint polygons leave the interior clear")
	var walls := glass.outer_x_at(-37.0)
	expect(walls.is_equal_approx(Vector2(-19, 19)), "outer walls at mid height (got %s)" % walls)
	eq(glass.line_y(), -68.0, "water: the fill line is drawn on row -68")
	eq(glass.band_edges(1), Vector2(-69.5, -66.5), "PERFECT spans ±1.5 rows around the line")
	eq(glass.band_edges(3), Vector2(-71.5, -64.5), "GOOD ticks at ±3.5")
	eq(glass.band_edges(6), Vector2(-74.0, -61.5), "GOOD ENOUGH reaches the rim and is cut there")
	expect(glass.bracket_x() <= glass.outer_x_at(-68.0).x - 2.0, "the bracket clears the wall (%.1f)" % glass.bracket_x())
	_check_drawn_liquid(glass)

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
	var ly := float(roundi(glass.target_y()))
	eq(glass.line_y(), ly, "wine: the fill line is drawn on the target's row")
	eq(glass.band_edges(6), Vector2(ly - 6.5, ly + 6.5), "wine: GOOD ENOUGH spans ±6.5 rows inside the bowl")
	var bulge := INF
	for y in range(int(ly) - 7, int(ly) + 8):
		bulge = minf(bulge, glass.outer_x_at(float(y)).x)
	expect(glass.bracket_x() <= bulge - 2.0, "wine: the bracket clears the bowl's bulge (%.1f vs %.1f)" % [glass.bracket_x(), bulge])
	_check_drawn_liquid(glass)
	expect(_tint_clear(glass), "wine: wall tint polygons leave the bowl clear")


## What is drawn must match what is scored: a calm glass's liquid top sits
## exactly on level_for(volume), its area matches the volume, it never draws
## above the rim, and every amount (a first drop to brim-full) triangulates.
func _check_drawn_liquid(glass: Glass) -> void:
	var n := glass.def.id
	for vol in [0.6, 3.0, 400.0, glass.target, glass.capacity]:
		glass.reset()
		glass.volume = vol
		glass.step(DT)
		var poly := glass.liquid_polygon()
		expect(poly.is_empty() or not Geometry2D.triangulate_polygon(poly).is_empty(), "%s: liquid at %.1f triangulates" % [n, vol])
		if vol >= 3.0:
			expect(not poly.is_empty(), "%s: %.0f px² of liquid is drawn" % [n, vol])
		if poly.is_empty():
			continue
		var top := INF
		for p in poly:
			top = minf(top, p.y)
		if vol >= 3.0:
			near(top, glass.level_for(vol), "%s: calm liquid top at %.0f px² is the scored level" % [n, vol], 0.05)
		if vol >= 400.0:
			near(Pourer.poly_area(poly) / vol, 1.0, "%s: drawn liquid area matches %.0f px²" % [n, vol], 0.04)
		expect(top >= glass.level_for(glass.capacity) - 0.01, "%s: liquid never draws above the rim" % n)
	glass.reset()


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
	var tint := VesselArt.walls(glass.outer, glass.interior)
	var c := Vector2.ZERO
	for p in glass.interior:
		c += p
	c /= glass.interior.size()
	for w in tint:
		if Geometry2D.is_point_in_polygon(c, w):
			return false
	return not tint.is_empty()
