extends CheckBase
## Checks the stream's ribbon outline: two points per stream point, the given
## width at each end, and a shape Godot can triangulate; and a beer poured
## into its tipped glass landing inside it, through no wall, all accounted
## for. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=stream

const DT := 1.0 / 60.0


func run() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(-2, 10), Vector2(-3, 30)])
	var r := Stream.ribbon(pts, PackedFloat32Array([3.0, 2.0, 1.0]))
	eq(r.size(), 6, "two points per stream point")
	near(r[0].distance_to(r[5]), 3.0, "full width at the spout", 0.01)
	near(r[2].distance_to(r[3]), 1.0, "tapers to the last width", 0.01)
	near(r[1].distance_to(r[4]), 2.0, "the middle width in between", 0.01)
	expect(not Geometry2D.triangulate_polygon(r).is_empty(), "the ribbon triangulates")
	var straight := Stream.ribbon(PackedVector2Array([Vector2(5, 0), Vector2(5, 8)]), PackedFloat32Array([2.0, 2.0]))
	expect(straight[0].is_equal_approx(Vector2(6, 0)) or straight[0].is_equal_approx(Vector2(4, 0)), "a vertical stream's edges sit width/2 to the sides (%s)" % straight[0])
	_tipped_pour()


## A feathered beer pour: the glass tips while it pours and stands up after;
## nothing misses it, nothing in it passes through a wall, every px² poured
## ends up in it (liquid, head or spilled).
func _tipped_pour() -> void:
	var main: Main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var beer: DrinkDef = GameState.BEER
	main.glass.setup(beer)
	main.glass.place(Main.GLASS_POS)
	main.pourer.setup(beer)
	main.pourer.place(Main.GLASS_POS + beer.pourer_offset)
	main.stream.set_drink(beer)
	var start: float = main.pourer.volume
	var most := 0.0
	var outside := 0
	var t := 0.0
	while t < 8.0:
		main._step_sim(DT, t < 3.0 and fmod(t, 0.5) < 0.35)  # feathered for 3 s, then let go
		most = maxf(most, main.glass.tilt)
		for p in main.stream._parcels:
			if p.state == 1:
				var q := main.glass.to_glass(p.pos)
				if not Geometry2D.is_point_in_polygon(q, beer.glass_interior) and _edge_gap(q, beer.glass_interior) > 1.0:
					outside += 1
		t += DT
	expect(most > deg_to_rad(10.0), "the glass tipped while pouring (%.1f°)" % rad_to_deg(most))
	expect(main.glass.is_upright(), "...and is upright once it's over")
	eq(main.stream.spilled, 0.0, "nothing missed the tipped glass")
	eq(outside, 0, "nothing in the glass passed through a wall")
	near(main.glass.volume + main.glass.foam.beer + main.glass.spilled, start - main.pourer.volume, "everything poured is in the glass", 0.5)
	main.free()


func _edge_gap(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best
