class_name VesselArt
extends RefCounted
## Geometry and fills for drawing vessels smooth: rounded copies of the shared
## DrinkDef polygons (the physics keeps the sharp originals), the wall area
## between an outer and an interior shape with the top left open, horizontal
## gradient fills, the highlight streak inside a left wall, and soft round
## shadows. Static helpers only; all coordinates are the caller's local px.

## About one arc point per this many radians of turn.
const ARC_STEP := deg_to_rad(15.0)

static var _soft: GradientTexture2D


## `poly` with every corner (convex or concave) replaced by an arc of
## `radius`, shrunk where an edge is too short to fit it. `keep_top` leaves the
## vertices along the top (within 0.5 px of it) sharp — a vessel's opening.
static func rounded(poly: PackedVector2Array, radius: float, keep_top := false) -> PackedVector2Array:
	var top := INF
	for p in poly:
		top = minf(top, p.y)
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var p0 := poly[(i - 1 + n) % n]
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var d1 := (p0 - p1).normalized()
		var d2 := (p2 - p1).normalized()
		var angle := acos(clampf(d1.dot(d2), -1.0, 1.0))  # between the two edges
		var turn := PI - angle
		if (keep_top and p1.y - top <= 0.5) or turn < 0.01 or angle < 0.01:
			out.append(p1)
			continue
		var t := minf(radius / tan(angle * 0.5), minf(p0.distance_to(p1), p1.distance_to(p2)) * 0.5)
		var r := t * tan(angle * 0.5)
		var a := p1 + d1 * t
		var b := p1 + d2 * t
		var center := p1 + (d1 + d2).normalized() * (r / sin(angle * 0.5))
		var start := (a - center).angle()
		var sweep := wrapf((b - center).angle() - start, -PI, PI)
		var steps := maxi(2, ceili(turn / ARC_STEP))
		for s in steps + 1:
			out.append(center + Vector2.from_angle(start + sweep * s / steps) * r)
	return out


## The wall area between `outer` and `interior`, open at the top: `outer`
## minus the interior extended straight up through its opening (the span of
## its top vertices). Clipping against the plain interior would return it as a
## hole polygon, and filling that would cover the inside.
static func walls(outer: PackedVector2Array, interior: PackedVector2Array) -> Array[PackedVector2Array]:
	var top := INF
	for p in interior:
		top = minf(top, p.y)
	var x0 := INF
	var x1 := -INF
	for p in interior:
		if p.y - top <= 0.5:
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
	var chimney := PackedVector2Array([Vector2(x0, top - 50.0), Vector2(x1, top - 50.0), Vector2(x1, top + 0.5), Vector2(x0, top + 0.5)])
	var cut := interior
	var merged := Geometry2D.merge_polygons(interior, chimney)
	if merged.size() > 0:
		cut = merged[0]
	var result: Array[PackedVector2Array] = []
	for poly in Geometry2D.clip_polygons(outer, cut):
		if not Geometry2D.is_polygon_clockwise(poly):  # Godot returns holes clockwise
			result.append(poly)
	return result


## A texture of `stops` ([[offset, Color], …]) for draw_hgradient. Build it once and keep it.
static func gradient(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	return tex


## Fills `poly` with `tex` running left to right from x0 to x1.
static func draw_hgradient(ci: CanvasItem, poly: PackedVector2Array, x0: float, x1: float, tex: GradientTexture1D) -> void:
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(Vector2((p.x - x0) / (x1 - x0), 0.5))
	ci.draw_polygon(poly, PackedColorArray([Color.WHITE]), uvs, tex)


## Left and right x where the horizontal line at `y` crosses `poly` (INF/-INF if it misses).
static func span_at(poly: PackedVector2Array, y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if a.y != b.y and (a.y - y) * (b.y - y) <= 0.0:
			var x := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
			lo = minf(lo, x)
			hi = maxf(hi, x)
	return Vector2(lo, hi)


## Points following the inside of `interior`'s left wall, `inset` px in, from
## y0 to y1 (one per 1.5 px) — the path of a highlight streak.
static func inner_streak(interior: PackedVector2Array, y0: float, y1: float, inset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var y := y0
	while y <= y1:
		var span := span_at(interior, y)
		if span.x < span.y:
			pts.append(Vector2(span.x + inset, y))
		y += 1.5
	return pts


## A soft round shadow or glow: `color` at the centre fading to nothing at `radii`.
static func draw_soft_ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	if _soft == null:
		_soft = GradientTexture2D.new()
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 128
		_soft.height = 128
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		_soft.gradient = g
	ci.draw_texture_rect(_soft, Rect2(center - radii, radii * 2.0), false, color)
