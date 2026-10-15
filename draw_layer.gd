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
