extends CheckBase
## Checks the smooth-drawing helpers: rounded copies of the vessel shapes
## (area kept, corners added, the opening left sharp on request), open-top wall
## polygons that leave the inside clear and triangulate, and the inner streak.
## Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=vessel_art


func run() -> void:
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.WINE

	var r := VesselArt.rounded(water.glass_outer, 2.0)
	near(Pourer.poly_area(r) / Pourer.poly_area(water.glass_outer), 1.0, "rounding keeps the area", 0.02)
	expect(r.size() > water.glass_outer.size(), "rounded corners add points (%d)" % r.size())
	expect(_within(r, water.glass_outer, 0.01), "a rounded convex shape stays inside the original")
	var kept := VesselArt.rounded(water.glass_interior, 2.0, true)
	expect(kept.has(Vector2(-19, -74)) and kept.has(Vector2(19, -74)), "keep_top leaves the opening's corners sharp")
	expect(not kept.has(Vector2(-15, -5)), "...but rounds the others")
	var spout := VesselArt.rounded(water.pourer_interior, 2.5, true)
	near(Pourer.poly_area(spout) / Pourer.poly_area(water.pourer_interior), 1.0, "a concave corner (the spout) rounds too, area kept", 0.02)
	expect(not Geometry2D.triangulate_polygon(VesselArt.rounded(wine.glass_outer, 5.0)).is_empty(), "the rounded wine glass (thin stem) triangulates")

	for d: DrinkDef in GameState.DRINKS:
		for pair in [[d.glass_outer, d.glass_interior], [d.pourer_outer, d.pourer_interior]]:
			var walls := VesselArt.walls(pair[0], pair[1])
			var a := 0.0
			for p in walls:
				a += Pourer.poly_area(p)
				expect(not Geometry2D.triangulate_polygon(p).is_empty(), "%s: wall polygon triangulates" % d.id)
			var expected := Pourer.poly_area(pair[0]) - Pourer.poly_area(pair[1])
			expect(a <= expected + 1.0 and a > expected * 0.8, "%s: open-top wall area (%.0f of %.0f)" % [d.id, a, expected])
			expect(not walls.is_empty() and not _covers(walls, _centroid(pair[1])), "%s: walls leave the inside clear" % d.id)

	expect(not Geometry2D.triangulate_polygon(VesselArt.crown_cap_polygon(Rect2(-1.5, -3, 10, 3.4))).is_empty(), "the crown cap triangulates")
	var label := wine.pourer_label
	var crest := VesselArt.crest_polygon(Pourer.crest_center(label), Pourer.CREST_SIZE)
	expect(not Geometry2D.triangulate_polygon(crest).is_empty(), "the vintage label's crest triangulates")
	var box := Rect2(crest[0], Vector2.ZERO)
	for p in crest:
		box = box.expand(p)
	expect(label.encloses(box.grow(1.0)), "...and sits on the label (%s in %s)" % [box, label])
	expect(not Geometry2D.triangulate_polygon(VesselArt.crown_polygon(Pourer.crest_center(label) + Vector2(0, -6.4), 6.0)).is_empty(), "...and the crown over it")
	expect(not Geometry2D.triangulate_polygon(VesselArt.rounded(GameState.BEER.glass_outer, GameState.BEER.glass_corner_radius)).is_empty(), "the rounded beer glass (ringed foot) triangulates")

	var s := VesselArt.inner_streak(water.glass_interior, -68.0, -12.0, 2.3)
	expect(s.size() > 30, "the streak has a point per 1.5 px (%d)" % s.size())
	var inside := true
	for p in s:
		inside = inside and Geometry2D.is_point_in_polygon(p, water.glass_interior)
	expect(inside, "the streak runs inside the left wall")
	near(s[0].x, -15.0 - 4.0 * 63.0 / 69.0 + 2.3, "...2.3 px in from it (the wall is at x -18.65 on row -68)", 0.05)

	var g := VesselArt.gradient([[0.0, Color.WHITE], [1.0, Color(1, 1, 1, 0)]])
	expect(g is GradientTexture1D and g.gradient.get_point_count() == 2, "gradient() builds a 1D texture from stops")


func _within(poly: PackedVector2Array, outer: PackedVector2Array, tolerance: float) -> bool:
	for p in poly:
		if not Geometry2D.is_point_in_polygon(p, outer) and _edge_distance(p, outer) > tolerance:
			return false
	return true


func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


func _covers(polys: Array[PackedVector2Array], p: Vector2) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()
