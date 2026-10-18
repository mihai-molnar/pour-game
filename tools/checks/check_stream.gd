extends CheckBase
## Checks the stream's ribbon outline: two points per stream point, the given
## width at each end, and a shape Godot can triangulate. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=stream


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
