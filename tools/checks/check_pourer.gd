extends CheckBase
## Checks the pourer: DrinkDef setup, capacity vs the glass, pour_speed_mult,
## the held rest angle, arrivals (DOWN ignored until ready, a bottle's cork)
## and both refill styles. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=pourer

const DT := 1.0 / 60.0
const GLASS_POS := Vector2(256, 280)

var _events := {"vanished": 0, "landed": [], "popped": 0}


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var pourer: Pourer = main.pourer
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	pourer.vanished.connect(func(_at: Vector2) -> void: _events.vanished += 1)
	pourer.landed.connect(func(at: Vector2) -> void: _events.landed.append(at))
	pourer.popped.connect(func(_at: Vector2, _v: Vector2, _c: Color) -> void: _events.popped += 1)

	glass.setup(water)
	glass.place(GLASS_POS)
	pourer.setup(water)
	pourer.place(GLASS_POS + water.pourer_offset)
	expect(pourer.def == water, "pourer is set up with water")
	var glasses := pourer.full_volume / glass.target
	expect(glasses > 2.3 and glasses < 2.7, "a full pitcher holds ~2.5 glasses at the line (got %.2f)" % glasses)
	pourer.reset()
	expect(pourer.volume == pourer.full_volume and not pourer.refilling and not pourer.corked, "reset() = full, upright, not refilling")
	expect(pourer.rotation == 0.0, "a pitcher stands upright at rest")

	# The wall tint must not cover the interior (clip_polygons alone returns the
	# interior as a hole polygon, which fills it with frost).
	_walls_cover_interior(VesselArt.walls(pourer.def.pourer_outer, pourer.interior), pourer.interior, "walls")

	# pour_speed_mult scales the tilt speed (measured before any pouring starts).
	var base_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 2.0
	var fast_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 1.0
	var ratio := fast_tilt / base_tilt
	expect(ratio > 1.8 and ratio < 2.2, "pour_speed_mult 2 doubles the tilt speed (ratio %.2f)" % ratio)

	# Running dry while tilted: DOWN is ignored (same motion held or not), it
	# returns upright, then refills in place over stats.refill_time.
	var held := _drain_and_refill(pourer, true)
	var free := _drain_and_refill(pourer, false)
	expect(held.tilts == free.tilts, "refilling ignores DOWN")
	expect(held.upright_at > 0.0, "it returned upright before refilling")
	expect(absf(held.refill_s - 1.0) < 0.1, "refill takes refill_time once upright (took %.2f s)" % held.refill_s)
	expect(is_equal_approx(pourer.volume, pourer.full_volume) and not pourer.refilling, "refilled to full")
	GameState.stats.refill_time = 0.5
	var quick := _drain_and_refill(pourer, false)
	GameState.stats.refill_time = 1.0
	expect(absf(quick.refill_s - 0.5) < 0.1, "refill_time is read live (took %.2f s)" % quick.refill_s)
	eq(_events.vanished, 0, "a pitcher never vanishes")

	_check_arrival(pourer, water)
	_check_wine(pourer, glass, wine)
	_check_drawable_liquid(pourer, water, wine)
	for d: DrinkDef in [water, wine]:
		pourer.setup(d)
		var mat := (pourer.get_node("Liquid") as CanvasItem).material as ShaderMaterial
		eq([mat.get_shader_parameter("tint"), mat.get_shader_parameter("absorb"), mat.get_shader_parameter("scatter")],
			[d.liquid_color, d.liquid_absorb, d.liquid_scatter], "%s: the pourer's liquid shader gets the drink's look" % d.id)


## Clipping the interior at the surface can leave sub-pixel slivers where the
## surface passes a hair from a corner; Godot can't triangulate them and logs
## "Invalid polygon data, triangulation failed" when they're drawn. These exact
## states (volume, tilt, slosh) produced one (found by a random search).
func _check_drawable_liquid(pourer: Pourer, water: DrinkDef, wine: DrinkDef) -> void:
	for c in [[water, 17.631875417997293, 1.6116318, -0.17012388],
			[wine, 139.12759431155993, 0.8847026, 0.14675927],
			[wine, 2671.3016543810186, 1.0356424, -0.0041520596]]:
		pourer.setup(c[0])
		pourer.place(GLASS_POS + c[0].pourer_offset)
		pourer.volume = c[1]
		pourer.tilt = c[2]
		pourer.slosh = c[3]
		pourer._update_surface()
		for polys: Array[PackedVector2Array] in [pourer.liquid_polygons(), pourer.drawn_liquid_polygons()]:
			var drawable := true  # none at all is fine: a sub-pixel amount draws nothing
			for poly in polys:
				drawable = drawable and not Geometry2D.triangulate_polygon(poly).is_empty()
			expect(drawable, "%s at volume %.1f: every liquid polygon can be drawn (%d polygons)" % [c[0].id, c[1], polys.size()])
	# The drawn (rounded) liquid at a spread of amounts and tilts: always drawable, always inside.
	for d: DrinkDef in [water, wine]:
		pourer.setup(d)
		pourer.place(GLASS_POS + d.pourer_offset)
		var box := Rect2(pourer.interior[0], Vector2.ZERO)
		for p in pourer.interior:
			box = box.expand(p)
		box = box.grow(0.5)
		for vol in [0.6, 5.0, 50.0, pourer.full_volume * 0.5, pourer.full_volume]:
			for t in [0.0, 20.0, 45.0, 80.0, d.max_tilt_deg]:
				pourer.volume = vol
				pourer.tilt = deg_to_rad(t)
				pourer.slosh = 0.0
				pourer._update_surface()
				var ok := true
				for poly in pourer.drawn_liquid_polygons():
					ok = ok and not Geometry2D.triangulate_polygon(poly).is_empty()
					for p in poly:
						ok = ok and box.has_point(p)
				expect(ok, "%s at %.0f px², tilt %d: drawn liquid triangulates and stays inside" % [d.id, vol, t])


func _check_arrival(pourer: Pourer, water: DrinkDef) -> void:
	var home := GLASS_POS + water.pourer_offset
	_events.landed.clear()
	pourer.volume = pourer.full_volume * 0.3
	pourer.arrive(water, home)
	expect(is_equal_approx(pourer.volume, pourer.full_volume), "an arriving pourer is full")
	near(pourer.position.x, Pourer.OFFSCREEN_X, "it starts off-screen right")
	expect(not pourer.corked, "a pitcher has no cork")
	var t := 0.0
	var tilted_while_arriving := false
	while pourer.is_arriving() and t < 1.0:
		pourer.step(DT, true)  # DOWN held all along
		t += DT
		tilted_while_arriving = tilted_while_arriving or (pourer.is_arriving() and pourer.tilt > 0.0)
	expect(not tilted_while_arriving, "DOWN is ignored while it arrives")
	expect(absf(t - Arrival.ARRIVE_TIME) <= DT + 1e-6, "the slide takes ARRIVE_TIME (%.3f s)" % t)
	expect(pourer.position == home, "it ends exactly at home (%s)" % pourer.position)
	eq(_events.landed.size(), 1, "landed fires once")
	if _events.landed.size() == 1:
		expect(_events.landed[0].is_equal_approx(home + Vector2(11, 105)), "...at the pitcher's leading bottom corner (%s)" % _events.landed[0])
	pourer.step(DT, true)
	expect(pourer.tilt > 0.0, "once it has arrived, DOWN tilts it")
	pourer.arrive(water, home)
	pourer.step(DT, false)
	pourer.reset()
	expect(pourer.position == home and not pourer.is_busy(), "reset() mid-arrival puts it back home, ready (%s)" % pourer.position)


func _check_wine(pourer: Pourer, glass: Glass, wine: DrinkDef) -> void:
	var home := GLASS_POS + wine.pourer_offset
	glass.setup(wine)
	glass.place(GLASS_POS)
	pourer.setup(wine)
	pourer.place(home)
	var glasses := pourer.full_volume / glass.target
	expect(glasses >= 2.5 and glasses <= 3.5, "a full bottle holds 2.5-3.5 glasses at the line (got %.2f)" % glasses)
	near(pourer.rotation, -deg_to_rad(55.0), "the bottle is held at 55°")
	var poured := 0.0
	for i in 60:
		poured += pourer.step(DT, false)
	expect(poured == 0.0, "a full bottle held at rest doesn't pour")
	var t := 0.0
	while poured == 0.0 and t < 3.0:
		poured += pourer.step(DT, true)
		t += DT
	expect(poured > 0.0, "holding DOWN pours from the bottle (after %.2f s)" % t)

	# A drink change or round start: it arrives corked, ignores DOWN, and pops
	# POP_TIME after it lands.
	_events.popped = 0
	pourer.arrive(wine, home)
	expect(pourer.corked and pourer.is_busy(), "a bottle arrives corked")
	t = 0.0
	var tilted_while_corked := false
	while pourer.corked and t < 2.0:
		pourer.step(DT, true)
		t += DT
		tilted_while_corked = tilted_while_corked or (pourer.corked and pourer.tilt > 0.0)
	var want := Arrival.ARRIVE_TIME + Pourer.POP_TIME
	expect(absf(t - want) <= DT + 1e-6, "the cork pops %.2f s after it starts arriving (%.3f s)" % [want, t])
	eq(_events.popped, 1, "popped fires once")
	expect(not tilted_while_corked, "DOWN is ignored until the cork is out")
	pourer.step(DT, true)
	expect(pourer.tilt > 0.0 and not pourer.is_busy(), "then DOWN tilts it")

	# Running dry: the empty bottle vanishes, a new corked one arrives and is
	# uncorked, all within refill_time (never shorter than the slide + 0.1 s).
	for refill_time: float in [1.0, 0.5, 0.2]:
		GameState.stats.refill_time = refill_time
		_events.vanished = 0
		_events.popped = 0
		var held := _drain_and_refill(pourer, true)
		var free := _drain_and_refill(pourer, false)
		var want_s := maxf(refill_time, Arrival.ARRIVE_TIME + Pourer.MIN_UNCORK)
		expect(held.tilts == free.tilts, "a bottle refill ignores DOWN (refill_time %.1f)" % refill_time)
		expect(absf(held.refill_s - want_s) < 0.1, "a bottle refill takes %.1f s once upright (took %.2f s)" % [want_s, held.refill_s])
		eq(_events.vanished, 2, "the empty bottle vanishes once per refill (refill_time %.1f)" % refill_time)
		eq(_events.popped, 2, "the new bottle is uncorked once per refill (refill_time %.1f)" % refill_time)
		expect(is_equal_approx(pourer.volume, pourer.full_volume) and not pourer.corked and not pourer.refilling, "a full, open bottle after the refill")
		expect(pourer.position == home, "back at home after the refill (%s)" % pourer.position)
	GameState.stats.refill_time = 1.0


func _tilt_after_hold(pourer: Pourer, seconds: float) -> float:
	pourer.reset()
	var t := 0.0
	while t < seconds - 1e-6:
		pourer.step(DT, true)
		t += DT
	return pourer.tilt


## Tilts the pourer to 1 rad with an almost empty pourer, then steps until the
## refill ends. Returns {tilts: Array, upright_at: float, refill_s: float}.
func _drain_and_refill(pourer: Pourer, hold: bool) -> Dictionary:
	pourer.reset()
	pourer.tilt = 1.0
	pourer.volume = pourer.full_volume * 0.005
	var tilts: Array[float] = []
	var upright_at := -1.0
	var t := 0.0
	pourer.step(DT, hold)
	t += DT
	while pourer.refilling and t < 10.0:
		tilts.append(pourer.tilt)
		if upright_at < 0.0 and pourer.tilt == 0.0 and pourer.tilt_vel == 0.0:
			upright_at = t
		pourer.step(DT, hold)
		t += DT
	return {"tilts": tilts, "upright_at": upright_at, "refill_s": t - upright_at}


func _walls_cover_interior(walls: Array, interior: PackedVector2Array, what: String) -> void:
	var c := Vector2.ZERO
	for p in interior:
		c += p
	c /= interior.size()
	var covered := false
	for w in walls:
		if Geometry2D.is_point_in_polygon(c, w):
			covered = true
	expect(not covered, "%s: no wall polygon contains the interior centre" % what)
