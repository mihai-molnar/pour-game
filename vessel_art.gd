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
static var _clear_walls: GradientTexture1D
static var _cork: GradientTexture1D
static var _cork_flecks: Array[Vector3] = []  # u, v (share of the cork), radius in px; negative radius = a light fleck


## The wall fill for clear glass (pass the outer's x range to draw_hgradient):
## brightest at the left edge, a rim of light on the right.
static func clear_glass_walls() -> GradientTexture1D:
	if _clear_walls == null:
		_clear_walls = gradient([[0.0, Color(Palette.WHITE, 0.52)], [0.18, Color(Palette.FROST, 0.22)],
			[0.6, Color(Palette.FROST, 0.13)], [1.0, Color(Palette.WHITE, 0.38)]])
	return _clear_walls


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


## Fills `poly` with `tex` running left to right from x0 to x1, tinted by `modulate`.
static func draw_hgradient(ci: CanvasItem, poly: PackedVector2Array, x0: float, x1: float, tex: GradientTexture1D, modulate := Color.WHITE) -> void:
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(Vector2((p.x - x0) / (x1 - x0), 0.5))
	ci.draw_polygon(poly, PackedColorArray([modulate]), uvs, tex)


## A natural cork filling `r` (upright, top edge up): light tan, darker toward
## its sides like a cylinder, bevelled top edges and flecked. The flecks are
## fixed, so the cork looks the same every frame.
static func draw_cork(ci: CanvasItem, r: Rect2, alpha := 1.0) -> void:
	if _cork == null:
		_cork = gradient([[0.0, Palette.TAN.darkened(0.3)], [0.3, Palette.PEACH], [0.55, Palette.SAND.lerp(Palette.PEACH, 0.4)], [1.0, Palette.TAN.darkened(0.35)]])
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 30:
			var radius := rng.randf_range(0.1, 0.3)
			_cork_flecks.append(Vector3(rng.randf_range(0.1, 0.9), rng.randf_range(0.08, 0.95), -radius if i % 4 == 0 else radius))
	var bevel := minf(r.size.x * 0.18, 1.2)
	var body := rounded(PackedVector2Array([r.position + Vector2(bevel, 0), Vector2(r.end.x - bevel, r.position.y),
		Vector2(r.end.x, r.position.y + bevel), r.end, Vector2(r.position.x, r.end.y), r.position + Vector2(0, bevel)]), 0.4)
	draw_hgradient(ci, body, r.position.x, r.end.x, _cork, Color(1, 1, 1, alpha))
	ci.draw_line(r.position + Vector2(bevel, 0.35), Vector2(r.end.x - bevel, r.position.y + 0.35), Color(Palette.SAND, 0.85 * alpha), 0.6, true)
	for f in _cork_flecks:
		var color := Color(Palette.SAND, 0.6 * alpha) if f.z < 0.0 else Color(Palette.BROWN, 0.55 * alpha)
		ci.draw_circle(r.position + Vector2(f.x, f.y) * r.size, absf(f.z), color)


## A crown cap filling `r`: a rounded top, straight sides and a crimped
## lower edge (9 teeth).
static func crown_cap_polygon(r: Rect2) -> PackedVector2Array:
	var teeth := 9
	var tooth := minf(r.size.y * 0.3, 0.9)
	var pts := PackedVector2Array([r.position + Vector2(0.6, 0.0), Vector2(r.end.x - 0.6, r.position.y), Vector2(r.end.x, r.position.y + 0.6)])
	for i in teeth * 2 + 1:
		pts.append(Vector2(r.end.x - r.size.x * i / (teeth * 2), r.end.y - (0.0 if i % 2 == 1 else tooth)))
	pts.append(r.position + Vector2(0.0, 0.6))
	return pts


static var _cap: GradientTexture1D


## A gold crown cap filling `r`: shaded round, a lighter top, a dark outline, a glint.
static func draw_crown_cap(ci: CanvasItem, r: Rect2, alpha := 1.0) -> void:
	if _cap == null:
		_cap = gradient([[0.0, Palette.CAP_GOLD.darkened(0.4)], [0.3, Palette.CAP_GOLD.lightened(0.3)], [0.6, Palette.CAP_GOLD], [1.0, Palette.CAP_GOLD.darkened(0.5)]])
	var poly := crown_cap_polygon(r)
	draw_hgradient(ci, poly, r.position.x, r.end.x, _cap, Color(1, 1, 1, alpha))
	ci.draw_rect(Rect2(r.position.x + 0.6, r.position.y + 0.15, r.size.x - 1.2, r.size.y * 0.3), Color(Palette.CAP_GOLD.lightened(0.45), 0.55 * alpha))
	var closed := poly.duplicate()
	closed.append(poly[0])
	ci.draw_polyline(closed, Color(Palette.INK, 0.45 * alpha), 0.35, true)
	ci.draw_line(r.position + Vector2(r.size.x * 0.22, 0.5), r.position + Vector2(r.size.x * 0.22, r.size.y - 1.2), Color(Palette.WHITE, 0.6 * alpha), 0.4, true)


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


## Draws a closed outline of `poly` whose opacity follows x: transparent left
## of `from` (a share of the width), `color` at the right edge — light caught
## by the right-hand wall.
static func draw_rim_light(ci: CanvasItem, poly: PackedVector2Array, color: Color, width: float, from := 0.72) -> void:
	var x0 := INF
	var x1 := -INF
	for p in poly:
		x0 = minf(x0, p.x)
		x1 = maxf(x1, p.x)
	var pts := poly.duplicate()
	pts.append(poly[0])
	var colors := PackedColorArray()
	for p in pts:
		colors.append(Color(color, color.a * clampf(((p.x - x0) / (x1 - x0) - from) / (1.0 - from), 0.0, 1.0)))
	ci.draw_polyline_colors(pts, colors, width, true)


## Draws `pts` as a soft highlight: `color` at the first point fading to 15 % at the last.
static func draw_streak(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var colors := PackedColorArray()
	for i in pts.size():
		colors.append(Color(color, color.a * lerpf(1.0, 0.15, float(i) / (pts.size() - 1))))
	ci.draw_polyline_colors(pts, colors, width, true)


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
