class_name MenuArt
extends RefCounted
## The shop menu's printed look: its two fonts (Oswald for titles, names and
## tabs; Courier Prime for descriptions, prices and notes) and small ink
## illustrations drawn from the game's own shapes — an even dark outline over
## flat, slightly translucent fills, like the hand-drawn drinks on a menu —
## plus the black marker bars over lines not unlocked yet and a small
## ornament. Static helpers only; coordinates are the caller's local units.

const OSWALD := preload("res://fonts/Oswald-VariableFont_wght.ttf")
const COURIER := preload("res://fonts/CourierPrime-Regular.ttf")
const COURIER_BOLD := preload("res://fonts/CourierPrime-Bold.ttf")
## Outline width of the illustrations.
const LINE := 0.8

static var _titles := {}


## Oswald at `weight` (variable, 200 to 700).
static func title_font(weight := 700) -> FontVariation:
	if not _titles.has(weight):
		var f := FontVariation.new()
		f.base_font = OSWALD
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_titles[weight] = f
	return _titles[weight]


static func type_font(bold := false) -> Font:
	return COURIER_BOLD if bold else COURIER


static func _outline(ci: CanvasItem, poly: PackedVector2Array, color: Color, width := LINE) -> void:
	var closed := poly.duplicate()
	closed.append(poly[0])
	ci.draw_polyline(closed, color, width, true)


## Two rounded cubes, one tucked behind the other, about `size` across.
static func ice_polygons(center: Vector2, size: float) -> Array[PackedVector2Array]:
	return [GarnishArt.ice_outline(center + Vector2(-size * 0.2, size * 0.1), size * 0.6, -0.2),
		GarnishArt.ice_outline(center + Vector2(size * 0.2, -size * 0.1), size * 0.6, 0.16)]


static func draw_ice(ci: CanvasItem, center: Vector2, size: float) -> void:
	for poly in ice_polygons(center, size):
		ci.draw_colored_polygon(poly, Color(Palette.WATER_LIGHT, 0.32))
		_outline(ci, poly, Palette.MENU_INK)
	for k in 2:
		var c := center + (Vector2(-size * 0.2, size * 0.1) if k == 0 else Vector2(size * 0.2, -size * 0.1))
		var a := -0.2 if k == 0 else 0.16
		var h := size * 0.3
		ci.draw_line(c + Vector2(-h + 1.2, h * 0.2).rotated(a), c + Vector2(-h + 1.2, -h + 1.4).rotated(a), Color(Palette.WHITE, 0.9), 0.7, true)


## A lime wedge about 2 × `radius` across, centred on `center`.
static func draw_lime(ci: CanvasItem, center: Vector2, radius: float) -> void:
	var angle := -0.35
	var slit := center + Vector2.DOWN.rotated(angle) * radius * 0.42
	var polys := GarnishArt.lime_polygons(slit, radius, angle)
	ci.draw_colored_polygon(polys[0], Color(Palette.LIME_PEEL, 0.9))
	ci.draw_colored_polygon(polys[1], Palette.LIME_FLESH.lightened(0.6))
	ci.draw_colored_polygon(polys[2], Color(Palette.LIME_FLESH, 0.95))
	for k in range(1, 6):
		var dir := Vector2.from_angle(PI + PI * k / 6.0).rotated(angle)
		ci.draw_line(slit + dir * radius * 0.1, slit + dir * radius * 0.74, Color(Palette.WHITE, 0.8), 0.4, true)
	_outline(ci, polys[0], Palette.MENU_INK)


## Points of `poly` scaled to fit `box` (centred), keeping proportions.
static func _fit(poly: PackedVector2Array, bounds: Rect2, box: Rect2) -> PackedVector2Array:
	var k := minf(box.size.x / bounds.size.x, box.size.y / bounds.size.y)
	var out := PackedVector2Array()
	for p in poly:
		out.append(box.get_center() + (p - bounds.get_center()) * k)
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## A drink's glass fitted into `box`: [its outline, the liquid up to `fill`
## of the inside's height] (the liquid is left out when there is none).
static func glass_polygons(d: DrinkDef, box: Rect2, fill: float) -> Array[PackedVector2Array]:
	var bounds := _bounds(d.glass_outer)
	var outer := _fit(VesselArt.rounded(d.glass_outer, d.glass_corner_radius), bounds, box)
	var inside := _fit(VesselArt.rounded(d.glass_interior, d.glass_corner_radius, true), bounds, box)
	var out: Array[PackedVector2Array] = [outer]
	var r := _bounds(inside)
	var level := r.end.y - fill * r.size.y
	var below := PackedVector2Array([Vector2(r.position.x - 1.0, level), Vector2(r.end.x + 1.0, level), Vector2(r.end.x + 1.0, r.end.y + 1.0), Vector2(r.position.x - 1.0, r.end.y + 1.0)])
	var best := PackedVector2Array()
	var best_area := 0.5
	for poly in Geometry2D.intersect_polygons(inside, below):
		var area := Pourer.poly_area(poly)
		if area >= best_area:
			best = poly
			best_area = area
	if not best.is_empty():
		out.append(best)
	return out


static func draw_glass(ci: CanvasItem, d: DrinkDef, box: Rect2, fill: float) -> void:
	var polys := glass_polygons(d, box, fill)
	ci.draw_colored_polygon(polys[0], Color(Palette.FROST, 0.35))
	if polys.size() > 1:
		ci.draw_colored_polygon(polys[1], Color(d.liquid_color, 0.6))
	var bounds := _bounds(d.glass_outer)
	var inside := _fit(VesselArt.rounded(d.glass_interior, d.glass_corner_radius, true), bounds, box)
	_outline(ci, inside, Color(Palette.MENU_INK, 0.4), 0.5)
	_outline(ci, polys[0], Palette.MENU_INK)
	var r := _bounds(inside)
	ci.draw_line(Vector2(r.position.x + 1.6, r.position.y + 2.0), Vector2(r.position.x + 1.6, r.end.y - 2.5), Color(Palette.WHITE, 0.8), 0.7, true)


## A drink's pourer, upright, fitted into `box`: [its outline, the label, the
## foil] (those it has).
static func bottle_polygons(d: DrinkDef, box: Rect2) -> Array[PackedVector2Array]:
	var pts := d.pourer_outer + d.pourer_handle
	var bounds := _bounds(pts)
	var out: Array[PackedVector2Array] = [_fit(VesselArt.rounded(d.pourer_outer, d.pourer_corner_radius), bounds, box)]
	for r: Rect2 in [d.pourer_label, d.pourer_foil]:
		if r.has_area():
			out.append(_fit(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), bounds, box))
	return out


static func draw_bottle(ci: CanvasItem, d: DrinkDef, box: Rect2) -> void:
	var polys := bottle_polygons(d, box)
	var bottle := d.refill_style == DrinkDef.RefillStyle.NEW_BOTTLE
	ci.draw_colored_polygon(polys[0], Color(d.pourer_glass_color, 0.85) if bottle else Color(Palette.FROST, 0.35))
	var i := 1
	if d.pourer_label.has_area():
		ci.draw_colored_polygon(polys[i], Palette.LABEL)
		_outline(ci, polys[i], Color(Palette.MENU_INK, 0.6), 0.4)
		i += 1
	if d.pourer_foil.has_area():
		ci.draw_colored_polygon(polys[i], Palette.WINE)
	if d.pourer_handle.size() >= 2:
		ci.draw_polyline(_fit(d.pourer_handle, _bounds(d.pourer_outer + d.pourer_handle), box), Palette.MENU_INK, LINE, true)
	_outline(ci, polys[0], Palette.MENU_INK)
	var r := _bounds(polys[0])
	ci.draw_line(Vector2(r.position.x + r.size.x * 0.22, r.position.y + r.size.y * 0.45), Vector2(r.position.x + r.size.x * 0.22, r.end.y - 2.0), Color(Palette.WHITE, 0.5), 0.7, true)


## A hand-drawn marker bar over `box`: slightly slanted, its edges wobbling
## (the same every time for the same `seed_value`).
static func redacted_polygon(box: Rect2, seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var slant := rng.randf_range(-0.025, 0.025)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var steps := maxi(ceili(box.size.x / 3.0), 2)
	for i in steps + 1:
		var x := box.position.x + box.size.x * i / steps
		var lean := slant * (x - box.position.x)
		top.append(Vector2(x, box.position.y + lean + rng.randf_range(-0.7, 0.7)))
		bottom.append(Vector2(x, box.end.y + lean + rng.randf_range(-0.7, 0.7)))
	var out := top.duplicate()
	out.append(Vector2(box.end.x + rng.randf_range(0.6, 1.6), box.get_center().y + slant * box.size.x))
	bottom.reverse()
	out.append_array(bottom)
	out.append(Vector2(box.position.x - rng.randf_range(0.6, 1.6), box.get_center().y))
	return out


static func draw_redacted(ci: CanvasItem, box: Rect2, seed_value: int) -> void:
	ci.draw_colored_polygon(redacted_polygon(box, seed_value), Color(Palette.INK, 0.93))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7919
	for k in 2:  # the marker's streaks
		var y := box.position.y + box.size.y * rng.randf_range(0.25, 0.75)
		ci.draw_line(Vector2(box.position.x + 2.0, y), Vector2(box.end.x - 2.0, y + rng.randf_range(-0.6, 0.6)), Color(Palette.WHITE, 0.07), 0.6, true)


## Two thin rules with a small diamond between them, `width` across.
static func draw_ornament(ci: CanvasItem, center: Vector2, width: float) -> void:
	var ink := Color(Palette.MENU_INK, 0.7)
	ci.draw_line(center - Vector2(width * 0.5, 0), center - Vector2(5, 0), ink, 0.6, true)
	ci.draw_line(center + Vector2(5, 0), center + Vector2(width * 0.5, 0), ink, 0.6, true)
	ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -2.4), center + Vector2(2.4, 0), center + Vector2(0, 2.4), center + Vector2(-2.4, 0)]), ink)
	for side in [-1.0, 1.0]:
		ci.draw_circle(center + Vector2(side * (width * 0.5 + 2.5), 0), 0.8, ink)
