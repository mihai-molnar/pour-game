class_name DrawLayer
extends Node2D
## Forwards _draw to a callable, so one vessel script can draw several layers
## (e.g. the shaded liquid behind and the glass walls in front).

var draw_func: Callable


func _draw() -> void:
	if draw_func.is_valid():
		draw_func.call(self)


## Draws a polygon's edges as 1 px lines; edges along its top (the rim or
## opening) use `rim` instead (a transparent `rim` skips them).
static func draw_outline(ci: CanvasItem, poly: PackedVector2Array, wall: Color, rim: Color) -> void:
	var top := INF
	for p in poly:
		top = minf(top, p.y)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var c := rim if a.y - top < 1.0 and b.y - top < 1.0 else wall
		if c.a > 0.0:
			ci.draw_line(a, b, c)


## The wall polygons between `outer` and `interior`, for tinting the glass.
## `Geometry2D.clip_polygons(outer, interior)` returns the outer outline PLUS
## the interior as a hole polygon when the interior lies fully inside `outer`,
## and filling both frosts the interior too. So the interior's top vertices
## are first moved 2 px above the outer's top, which opens the shape into a
## U; any hole left over is dropped. In Godot 4.5 hole results come back with
## the opposite winding to the outer boundary (is_polygon_clockwise true when
## the boundary is false), so holes are the clockwise ones.
static func wall_polygons(outer: PackedVector2Array, interior: PackedVector2Array) -> Array[PackedVector2Array]:
	var outer_top := INF
	var inner_top := INF
	for p in outer:
		outer_top = minf(outer_top, p.y)
	for p in interior:
		inner_top = minf(inner_top, p.y)
	var opened := interior.duplicate()
	for i in opened.size():
		if opened[i].y - inner_top <= 1.0:
			opened[i].y = outer_top - 2.0
	var walls: Array[PackedVector2Array] = []
	for poly in Geometry2D.clip_polygons(outer, opened):
		if not Geometry2D.is_polygon_clockwise(poly):
			walls.append(poly)
	return walls
