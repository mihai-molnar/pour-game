class_name FoamArt
extends RefCounted
## How a beer's head is drawn (Glass): creamy off-white, wetter and tinted by
## the beer where it meets it, a soft lumpy top that stays put (it doesn't wave
## like the liquid), and small bubbles against the glass, bigger near the top.
## Static helpers; coordinates are the glass's local px. Visual only.

const BUBBLES := 46


## The head's lumpy top at local x: how far (px) it rises above the calm top,
## within ±0.8, the same every frame for one glass (`seed_value`).
static func bump(x: float, seed_value: float) -> float:
	return 0.45 * sin(x * 0.55 + seed_value) + 0.3 * sin(x * 1.37 + seed_value * 2.7)


## Fills the head `poly`: FOAM at the top, wetter and tinted toward `beer`
## at the bottom (`depth` maps a point to 0 at the top .. 1 where the beer
## starts), then bubbles inside it.
static func draw(ci: CanvasItem, poly: PackedVector2Array, depth: Callable, beer: Color, seed_value: float) -> void:
	var wet := beer.lerp(Palette.FOAM, 0.5)
	var colors := PackedColorArray()
	for p in poly:
		var d: float = clampf(depth.call(p), 0.0, 1.0)
		colors.append(Color(Palette.FOAM.lerp(wet, smoothstep(0.45, 1.0, d)), lerpf(0.97, 0.88, d)))
	ci.draw_polygon(poly, colors)
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value * 1000.0)
	for i in BUBBLES:
		var at := box.position + Vector2(rng.randf(), rng.randf()) * box.size
		var size := rng.randf_range(0.7, 1.0)
		if not Geometry2D.is_point_in_polygon(at, poly):
			continue
		var d: float = clampf(depth.call(at), 0.0, 1.0)
		var r := lerpf(0.85, 0.35, d) * size
		ci.draw_arc(at, r, 0.0, TAU, 10, Color(beer.darkened(0.25), 0.3), 0.2, true)
		ci.draw_circle(at + Vector2(-r * 0.35, -r * 0.35), r * 0.3, Color(Palette.WHITE, 0.7))
