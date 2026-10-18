class_name GarnishArt
extends RefCounted
## Drawing for garnishes, shared by the glass and the shop cards: ice cubes
## (a frosty see-through body, drawn behind a glass's liquid, and bright edges
## drawn in front) and a lime wedge slit onto a rim. Static helpers only; all
## coordinates are the caller's local px.


## A cube's outline: a rounded square of side `size` turned by `angle` about `center`.
static func ice_outline(center: Vector2, size: float, angle: float) -> PackedVector2Array:
	var h := size * 0.5
	var square := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var out := VesselArt.rounded(square, size * 0.22)
	for i in out.size():
		out[i] = center + out[i].rotated(angle)
	return out


## The cube itself: clear and frosty, lighter toward its top-left, a faint
## shade along the bottom-right.
static func draw_ice_body(ci: CanvasItem, center: Vector2, size: float, angle: float) -> void:
	ci.draw_colored_polygon(ice_outline(center, size, angle), Color(Palette.FROST, 0.28))
	var lit := Vector2(-0.12, -0.12).rotated(angle) * size
	ci.draw_colored_polygon(ice_outline(center + lit, size * 0.62, angle), Color(Palette.WHITE, 0.14))
	var shade := Vector2(0.16, 0.16).rotated(angle) * size
	ci.draw_colored_polygon(ice_outline(center + shade, size * 0.5, angle), Color(Palette.STEEL, 0.12))


## The cube's edges: a soft outline, a bright glint along its top-left and a
## faint crack inside.
static func draw_ice_edges(ci: CanvasItem, center: Vector2, size: float, angle: float) -> void:
	var outline := ice_outline(center, size, angle)
	outline.append(outline[0])
	ci.draw_polyline(outline, Color(Palette.WHITE, 0.5), 0.45, true)
	var h := size * 0.5
	var glint := PackedVector2Array([Vector2(-h + 0.9, h * 0.25), Vector2(-h + 0.9, -h + 1.4), Vector2(-h + 1.6, -h + 0.9), Vector2(h * 0.2, -h + 0.9)])
	for i in glint.size():
		glint[i] = center + glint[i].rotated(angle)
	ci.draw_polyline(glint, Color(Palette.WHITE, 0.85), 0.55, true)
	ci.draw_line(center + Vector2(-h * 0.1, h * 0.35).rotated(angle), center + Vector2(h * 0.4, -h * 0.05).rotated(angle),
		Color(Palette.WHITE, 0.3), 0.35, true)


## A half-disc of `radius` on a chord through `slit`, turned by `angle`
## (0 = chord level, the round side up).
static func _half_disc(slit: Vector2, radius: float, angle: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		pts.append(slit + Vector2.from_angle(PI + PI * i / 16.0).rotated(angle) * radius)
	return pts


## The wedge's shapes, outside in: the peel, the pale pith, the flesh.
static func lime_polygons(slit: Vector2, radius: float, angle: float) -> Array[PackedVector2Array]:
	return [_half_disc(slit, radius, angle), _half_disc(slit, radius * 0.86, angle), _half_disc(slit, radius * 0.78, angle)]


## A lime wedge slit onto a rim at `slit`: the peel round the outside, the
## flesh with its segments, a juicy shine, the slit itself.
static func draw_lime(ci: CanvasItem, slit: Vector2, radius: float, angle: float) -> void:
	var polys := lime_polygons(slit, radius, angle)
	ci.draw_colored_polygon(polys[0], Palette.LIME_PEEL)
	ci.draw_colored_polygon(polys[1], Palette.LIME_FLESH.lightened(0.55))
	ci.draw_colored_polygon(polys[2], Palette.LIME_FLESH)
	var inner := radius * 0.78
	for k in range(1, 6):
		var dir := Vector2.from_angle(PI + PI * k / 6.0).rotated(angle)
		ci.draw_line(slit + dir * radius * 0.12, slit + dir * inner * 0.95, Color(Palette.WHITE, 0.55), 0.35, true)
	ci.draw_arc(slit, radius * 0.12, PI + angle, TAU + angle, 8, Color(Palette.WHITE, 0.6), 0.4, true)
	var shine := PackedVector2Array()
	for i in 6:
		shine.append(slit + Vector2.from_angle(PI * 1.15 + PI * 0.3 * i / 5.0).rotated(angle) * inner * 0.62)
	ci.draw_polyline(shine, Color(Palette.WHITE, 0.7), 0.6, true)
	var rim := PackedVector2Array()
	for i in 9:
		rim.append(slit + Vector2.from_angle(PI * 1.1 + PI * 0.45 * i / 8.0).rotated(angle) * (radius - 0.35))
	ci.draw_polyline(rim, Color(Palette.GREEN, 0.7), 0.45, true)
	var chord := Vector2.RIGHT.rotated(angle)
	ci.draw_line(slit - chord * radius, slit + chord * radius, Color(Palette.LIME_FLESH.lightened(0.6), 0.9), 0.4, true)
	ci.draw_line(slit, slit + Vector2.UP.rotated(angle) * radius * 0.45, Color(Palette.LIME_PEEL.darkened(0.5), 0.9), 0.4, true)
