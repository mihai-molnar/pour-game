extends CheckBase
## Checks the glass: exact capacity and fixed target per drink, rows from the
## line and the scoring band in rows, geometry helpers, where the fill line and
## band marks are drawn (on the rows scoring measures), the drawn liquid
## matching the volume and level, setup leaving no state behind, the
## arrival, and garnishes (ice raising the level, the lime on the rim). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass

const DT := 1.0 / 60.0
const HOME := Vector2(256, 280)


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.WINE
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
	expect(glass.opening_world() == Vector2(237, 275), "opening at the rim (got %s)" % glass.opening_world())
	expect(is_equal_approx(glass.rim_y_world(), 206.0), "rim at y=206 (got %.1f)" % glass.rim_y_world())
	expect(_tint_clear(glass), "wall tint polygons leave the interior clear")
	var walls := glass.outer_x_at(-37.0)
	expect(walls.is_equal_approx(Vector2(-19, 19)), "outer walls at mid height (got %s)" % walls)
	eq(glass.line_y(), -68.0, "water: the fill line is drawn on row -68")
	eq(glass.band_edges(1), Vector2(-69.5, -66.5), "PERFECT spans ±1.5 rows around the line")
	eq(glass.band_edges(3), Vector2(-71.5, -64.5), "GOOD ticks at ±3.5")
	eq(glass.band_edges(6), Vector2(-74.0, -61.5), "GOOD ENOUGH reaches the rim and is cut there")
	eq(glass.band_edges(9), Vector2(-74.0, -58.5), "...however wide the band")
	expect(glass.bracket_x() <= glass.outer_x_at(-68.0).x - 2.0, "the bracket clears the wall (%.1f)" % glass.bracket_x())
	_check_line_span(glass)
	_check_drawn_liquid(glass)

	_check_ice(glass, water)
	_check_lime(glass, water)
	_check_ice_physics(glass, water)
	_check_wine(glass, wine)
	_check_foam(glass, GameState.BEER)
	_check_tilt(glass, GameState.BEER)
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
	_check_line_span(glass)
	_check_drawn_liquid(glass)
	expect(_tint_clear(glass), "wine: wall tint polygons leave the bowl clear")
	var mat := (glass.get_node("Liquid") as CanvasItem).material as ShaderMaterial
	eq([mat.get_shader_parameter("tint"), mat.get_shader_parameter("absorb"), mat.get_shader_parameter("scatter")],
		[wine.liquid_color, wine.liquid_absorb, wine.liquid_scatter], "wine: the liquid shader gets wine's look")


## Beer's head: a fast pour builds it on top of the beer, every px² of beer
## is accounted for, the stream lands on it, it is drawn as big as it is, the
## beer creeps up as it drains, and running it over the rim is a spill.
func _check_foam(glass: Glass, beer: DrinkDef) -> void:
	glass.setup(beer)
	glass.place(HOME)
	expect(glass.foam != null and glass.foam.volume == 0.0, "a beer glass starts without a head")
	var landed := 0.0
	for i in 120:  # 2 s at about 600 px²/s
		glass.receive(HOME.x, 10.0, 200.0)
		landed += 10.0
		glass.step(DT)
	expect(glass.foam.volume > 300.0, "a fast pour builds a head (%.0f px²)" % glass.foam.volume)
	near(glass.volume + glass.foam.beer + glass.spilled, landed, "beer: landed = liquid + head's beer + spilled", 0.05)
	expect(glass.foam_level() < glass.surface_level(glass.volume) - 5.0, "the head sits on top of the beer")
	near(glass.surface_y_world_at(HOME.x) - HOME.y, glass.foam_level(), "the stream lands on the head", 1.5)
	var poly := glass.foam_polygon()
	expect(not Geometry2D.triangulate_polygon(poly).is_empty(), "the head is drawable")
	near(Pourer.poly_area(poly) / glass.foam.volume, 1.0, "the drawn head's area matches its volume", 0.06)
	var before := glass.volume
	var settled := glass.settled_volume()
	_steps(glass, 4.0)
	expect(glass.volume > before and absf(glass.volume - settled) < 20.0,
		"the beer creeps up as the head drains (%.0f -> %.0f, predicted %.0f)" % [before, glass.volume, settled])
	glass.receive(HOME.x, glass.capacity, 0.0)  # far too much: the head runs over first
	expect(glass.spilled > 0.5 and glass.volume + glass.foam.volume <= glass.max_liquid() + 0.01, "an overflowing head is a spill")
	glass.reset()
	expect(glass.foam.volume == 0.0 and glass.volume == 0.0, "reset clears the head")
	glass.setup(GameState.WATER)
	expect(glass.foam == null, "water has no head")


## Beer's glass tips about its mouth while pouring: upright it is exactly as
## before, a hair of tilt doesn't jump the level, tipped it holds less, the
## surface stays level in the world and the drawn beer matches its volume; it
## tips in, straightens as it fills, waits out a short gap, comes back exactly
## upright. Water's glass never tips.
func _check_tilt(glass: Glass, beer: DrinkDef) -> void:
	glass.setup(beer)
	glass.place(HOME)
	for v in [100.0, 800.0, glass.target]:
		eq(glass.surface_level(v), glass.level_for(v), "upright: the level is level_for (%.0f px²)" % v)
	glass.tilt = 1e-4
	for v in [100.0, 800.0, glass.target]:
		near(glass.surface_level(v), glass.level_for(v), "a hair of tilt doesn't jump the level (%.0f px²)" % v, 0.5)
	glass.tilt = deg_to_rad(30.0)
	expect(glass.max_liquid() < glass.capacity * 0.97 and glass.max_liquid() > glass.capacity * 0.8,
		"tipped, it holds less (%.0f of %.0f)" % [glass.max_liquid(), glass.capacity])
	var lvl := glass.surface_level(glass.target)
	var ys: Array[float] = []
	for x in [-10.0, 0.0, 10.0]:
		ys.append((glass.frame() * Vector2(x, glass.calm_y(x, lvl))).y)
	expect(absf(ys[0] - ys[2]) < 0.01 and absf(ys[1] - ys[2]) < 0.01, "the tipped surface is level in the world %s" % [ys])
	expect((glass.frame() * glass.pivot()).distance_to(glass.pivot()) < 1e-4, "it tips about its mouth")
	glass.volume = glass.target
	glass.step(DT)
	near(Pourer.poly_area(glass.liquid_polygon()) / glass.target, 1.0, "tipped: the drawn beer matches its volume", 0.04)
	glass.reset()
	glass.tilt = 0.0
	for i in 24:
		glass.step_tilt(DT, true)
	expect(glass.tilt >= deg_to_rad(beer.glass_pour_tilt_deg) * 0.9, "an empty glass tips to ~35° in 0.4 s (%.1f°)" % rad_to_deg(glass.tilt))
	glass.volume = glass.target
	for i in 60:
		glass.step_tilt(DT, true)
	near(rad_to_deg(glass.tilt), beer.glass_line_tilt_deg, "at the line it is held at ~15°", 0.5)
	for i in 14:
		glass.step_tilt(DT, false)
	expect(not glass.is_upright(), "it stays tipped through a short gap")
	var t := 0
	while not glass.is_upright() and t < 120:
		glass.step_tilt(DT, false)
		t += 1
	expect(glass.is_upright() and t * DT < 0.75, "then comes back exactly upright (%.2f s)" % (t * DT))
	glass.tilt = 0.4
	glass.place(HOME)
	expect(glass.is_upright(), "place() stands it upright")
	glass.setup(GameState.WATER)
	for i in 60:
		glass.step_tilt(DT, true)
	expect(glass.is_upright(), "water's glass never tips")


## The target marker runs from the bracket to the glass's left wall, never across the glass.
func _check_line_span(glass: Glass) -> void:
	var span := glass.line_span()
	eq(span.x, glass.bracket_x(), "%s: the target marker starts at the bracket" % glass.def.id)
	near(span.y, glass.outer_x_at(glass.line_y()).x, "%s: ...and stops at the glass's left wall" % glass.def.id, 0.01)


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


func _steps(glass: Glass, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		glass.step(DT)
		t += DT


func _drawn_top(glass: Glass) -> float:
	var top := INF
	for p in glass.liquid_polygon():
		top = minf(top, p.y)
	return top


## Ice falls in, then takes up room: the iced level is what is drawn and
## scored, and an iced glass holds less before it spills.
func _check_ice(glass: Glass, water: DrinkDef) -> void:
	var ice: GarnishDef = water.garnishes[0]
	glass.setup(water)
	glass.place(HOME)
	var landed := []
	glass.garnish_landed.connect(func(g: GarnishDef, _at: Vector2) -> void: landed.append(g.id))
	expect(glass.add_garnish(ice) and not glass.add_garnish(ice), "ice goes in once")
	expect(glass.garnish_busy() and glass.displaced(glass.target) == 0.0, "falling ice displaces nothing yet")
	_steps(glass, Glass.ICE_FALL_TIME + DT)
	expect(not glass.garnish_busy() and landed == [&"ice"], "it lands after ICE_FALL_TIME, once (%s)" % [landed])
	near(glass.surface_level(0.0), glass.level_for(0.0), "ice in an empty glass makes no water level")
	var rows := glass.rows_from_line(glass.target)
	expect(rows >= 4 and rows <= 6, "ice raises the surface at the line by 4-6 rows (%d)" % rows)
	var prev := INF
	var rising := true
	var v := 0.0
	while v <= glass.max_liquid():
		rising = rising and glass.surface_level(v) <= prev
		prev = glass.surface_level(v)
		v += 5.0
	expect(rising, "the iced level rises with every 5 px² poured")
	near(glass.surface_level(glass.max_liquid()), glass.level_for(glass.capacity), "max_liquid fills an iced glass to the rim", 0.01)
	glass.receive(HOME.x, glass.target * 0.7, 0.0)
	_steps(glass, 3.0)
	near(_drawn_top(glass), glass.surface_level(glass.volume), "a calm iced glass is drawn at the iced level", 0.05)
	glass.receive(HOME.x, glass.capacity, 0.0)
	near(glass.volume, glass.max_liquid(), "an iced glass holds max_liquid", 0.01)
	expect(glass.spilled > 0.5, "...and the rest spills")
	glass.setup(water)
	glass.place(HOME)
	glass.receive(HOME.x, glass.capacity - 4.0 * 38.0, 0.0)
	glass.add_garnish(ice)
	_steps(glass, Glass.ICE_FALL_TIME + DT)
	expect(glass.spilled > 0.5 and glass.volume <= glass.max_liquid() + 0.01, "ice into a nearly full glass overflows")
	for i in ice.cube_count:
		expect(not Geometry2D.triangulate_polygon(GarnishArt.ice_outline(Vector2.ZERO, ice.cube_size, 0.3 * i)).is_empty(), "ice cube %d triangulates" % i)
	glass.arrive(water, HOME)
	expect(glass.garnishes.is_empty() and not glass.garnish_busy() and glass.displaced(1000.0) == 0.0, "an arriving glass is bare")
	glass.place(HOME)


## The lime drops onto the rim and changes nothing about the level.
func _check_lime(glass: Glass, water: DrinkDef) -> void:
	var lime: GarnishDef = water.garnishes[1]
	glass.setup(water)
	glass.place(HOME)
	glass.receive(HOME.x, glass.target, 0.0)
	expect(glass.add_garnish(lime) and glass.garnish_busy(), "the lime drops onto the rim")
	_steps(glass, Glass.LIME_DROP_TIME + DT)
	expect(not glass.garnish_busy() and glass.has_garnish(&"lime"), "...and sits there")
	eq(glass.rows_from_line(glass.volume), 0, "the lime doesn't change the level")
	for poly in GarnishArt.lime_polygons(Vector2.ZERO, 7.0, -0.6):
		expect(not Geometry2D.triangulate_polygon(poly).is_empty(), "the lime's polygons triangulate")


## The cubes bounce and slide but always stay inside the glass, separate,
## and come to rest; afloat they ride near the surface; the stream pushes them.
func _check_ice_physics(glass: Glass, water: DrinkDef) -> void:
	var ice: GarnishDef = water.garnishes[0]
	var inside := true
	var resting := true
	var overlap := 0.0
	var moved := false
	var walls := _grown(glass.interior, 0.6)
	for i in 30:
		seed(100 + i)  # the physics' randomness is visual; a fixed seed repeats a failure
		glass.setup(water)
		glass.place(HOME)
		glass.add_garnish(ice)
		_steps(glass, Glass.ICE_FALL_TIME + DT)
		expect(glass.ice != null and glass.ice.cubes.size() == 2, "drop %d: landed ice is simulated" % i)
		if glass.ice == null:
			return
		var start: Vector2 = glass.ice.cubes[0].pos
		var t := 0.0
		while t < 1.2:
			glass.step(DT)
			t += DT
			for c in glass.ice.cubes:
				for p in glass.ice.corners(c):
					inside = inside and Geometry2D.is_point_in_polygon(p, walls)
		moved = moved or glass.ice.cubes[0].pos.distance_to(start) > 0.5
		resting = resting and glass.ice.max_speed() < 3.0 and glass.ice.max_spin() < 0.3
		overlap = maxf(overlap, _overlap(glass.ice.corners(glass.ice.cubes[0]), glass.ice.corners(glass.ice.cubes[1])))
	expect(inside, "dropped into an empty glass, the cubes never leave it")
	expect(moved, "...they move on landing instead of sticking where they fell")
	expect(resting, "...and come to rest within about a second")
	expect(overlap < 1.0, "...without sinking into each other (%.2f px²)" % overlap)
	glass.setup(water)
	glass.place(HOME)
	glass.receive(HOME.x, glass.target - 216.0 * ice.float_share, 0.0)
	glass.add_garnish(ice)
	_steps(glass, Glass.ICE_FALL_TIME + 2.5)
	var level := glass.surface_level(glass.volume)
	for c in glass.ice.cubes:
		near(c.pos.y, level + ice.cube_size * (ice.float_share - 0.5), "afloat at the line, a cube rides with float_share under", 2.5)
	var before: Vector2 = glass.ice.cubes[0].vel
	glass.receive(HOME.x + glass.ice.cubes[0].pos.x + 3.0, 40.0, 120.0)
	expect(glass.ice.cubes[0].vel.x < before.x - 0.5, "liquid landing beside a cube pushes it away")
	glass.arrive(water, HOME)
	expect(glass.ice == null, "an arriving glass has no ice")
	glass.place(HOME)


func _grown(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	return Geometry2D.offset_polygon(poly, by)[0]


func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var area := 0.0
	for p in Geometry2D.intersect_polygons(a, b):
		area += Pourer.poly_area(p)
	return area


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
