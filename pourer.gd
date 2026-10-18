class_name Pourer
extends Node2D
## The container you pour from (pitcher, bottle …), configured by a DrinkDef.
## It tilts around its spout lip (this node's origin), counting from the angle
## it is held at (DrinkDef.pourer_rest_deg; its shapes are authored upright).
## Pouring is pure geometry: the liquid surface stays (almost) level in the
## world while the pourer rotates, and whatever volume no longer fits below
## the line through the spout lip leaves through the spout. Volumes are areas
## in px², the same unit the glass uses. It arrives by sliding in from the
## right (arrive()); a bottle arrives corked and can't pour until the cork
## pops. When it runs dry it refills over GameState.stats.refill_time: a
## pitcher fills in place, an empty bottle is replaced by a new one that gets
## uncorked. Input is ignored while it is busy (is_busy()).

## The pourer vanished (an empty bottle being replaced); `at` = its centre (global).
signal vanished(at: Vector2)
## An arrival stopped sliding; `at` = the corner it tips over (global).
signal landed(at: Vector2)
## The cork popped: where (global), its launch velocity, and the spray colour.
signal popped(at: Vector2, velocity: Vector2, spray: Color)

## Excess below this is treated as "not pouring" so the stream can end cleanly.
const MIN_EXCESS := 0.5
## Below this share of full_volume the pourer counts as empty and refills.
const EMPTY_SHARE := 0.01
## Where an arriving pourer's spout lip starts: fully off-screen right.
const OFFSCREEN_X := 680.0
## A bottle arriving on a drink change or at round start pops its cork this
## long after it lands.
const POP_TIME := 0.15
## The shortest uncork in a bottle refill, however low refill_time goes.
const MIN_UNCORK := 0.1
## The refill uncork wiggle: the angle (°) it builds up to by the pop, and its speed (rad/s).
const WIGGLE_DEG := 4.0
const WIGGLE_FREQ := 45.0
## How fast the popped cork leaves the neck (px/s).
const CORK_SPEED := 160.0

var def: DrinkDef
var interior := PackedVector2Array()
## Interior area (px²).
var capacity := 0.0
## What "full" holds: capacity × def.pourer_full_fraction.
var full_volume := 0.0
## Where the spout lip rests (in Main's space).
var home := Vector2.ZERO

var tilt := 0.0
var tilt_vel := 0.0
var slosh := 0.0
var slosh_vel := 0.0
var volume := 0.0
var flow := 0.0
var excess := 0.0
var exit_speed := 0.0
var refilling := false
## A bottle that hasn't been uncorked yet; it can't pour.
var corked := false

var _refill_t := -1.0  # < 0 while still swinging back upright
var _refill_from := 0.0
var _surf_angle := 0.0
var _surf_point := Vector2.ZERO
var _arrive_t := -1.0  # < 0 when not arriving (covers the slide, the wobble and the uncork)
var _uncork_time := 0.0
var _wiggle := false
var _pivot := Vector2.ZERO
var _drawn_outer := PackedVector2Array()
var _drawn_interior := PackedVector2Array()
var _walls: Array[PackedVector2Array] = []
var _wall_tex: GradientTexture1D

@onready var _back: DrawLayer = $Back
@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front


func _ready() -> void:
	_back.draw_func = _draw_back
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front


func setup(d: DrinkDef) -> void:
	def = d
	interior = d.pourer_interior
	capacity = poly_area(interior)
	full_volume = capacity * d.pourer_full_fraction
	_drawn_outer = VesselArt.rounded(d.pourer_outer, d.pourer_corner_radius)
	_drawn_interior = VesselArt.rounded(interior, d.pourer_corner_radius, true)
	_walls = VesselArt.walls(_drawn_outer, _drawn_interior)
	var g := d.pourer_glass_color
	var wall_a := clampf(g.a * 3.0, 0.3, 0.85)
	_wall_tex = VesselArt.gradient([[0.0, Color(g.lightened(0.55), wall_a)], [0.2, Color(g.lightened(0.15), wall_a * 0.75)],
		[0.65, Color(g, wall_a * 0.7)], [1.0, Color(g.lightened(0.55), wall_a * 0.9)]])
	var box := _bounds(interior)
	var mat := _liquid.material as ShaderMaterial
	mat.set_shader_parameter("tint", d.liquid_color)
	mat.set_shader_parameter("center_x", box.get_center().x)
	mat.set_shader_parameter("half_width", box.size.x * 0.5)
	mat.set_shader_parameter("surface_y", 0.0)
	mat.set_shader_parameter("highlight_x", box.position.x + 4.0)
	reset()


## At home and its rest angle, still, not refilling or arriving, holding
## `fill` × full_volume.
func reset(fill := 1.0) -> void:
	tilt = 0.0
	tilt_vel = 0.0
	slosh = 0.0
	slosh_vel = 0.0
	volume = full_volume * fill
	flow = 0.0
	excess = 0.0
	refilling = false
	corked = false
	_refill_t = -1.0
	_arrive_t = -1.0
	position = home
	rotation = -_rest()
	_apply_lean(0.0)
	_update_surface()


## Sets the pourer up for `d` (full; corked if it's a bottle), puts it
## off-screen right and starts sliding it to `at`. A bottle pops its cork
## POP_TIME after it lands. Input is ignored until it's ready.
func arrive(d: DrinkDef, at: Vector2) -> void:
	setup(d)
	home = at
	_start_arrival(POP_TIME, false)


## Puts the pourer at `at` at once, ready to pour — for the sweep and checks.
func place(at: Vector2) -> void:
	home = at
	position = at
	corked = false
	_arrive_t = -1.0
	_apply_lean(0.0)


## True while sliding in; the wobble and the uncork after it don't count.
func is_arriving() -> bool:
	return _arrive_t >= 0.0 and _arrive_t < Arrival.ARRIVE_TIME


## True while it can't pour: arriving, corked or refilling. DOWN is ignored
## and Main won't serve.
func is_busy() -> bool:
	return refilling or corked or is_arriving()


func center_global() -> Vector2:
	return to_global(_bounds(def.pourer_outer).get_center())


## Advances one physics tick. Returns the volume that left the spout this tick.
func step(dt: float, hold: bool) -> float:
	if not refilling and volume < full_volume * EMPTY_SHARE:
		refilling = true
		_refill_t = -1.0
	_step_arrival(dt)
	if is_busy():
		hold = false
	var prev_vel := tilt_vel
	var acc: float
	if hold:
		var speed := def.pour_tilt_speed_deg if excess > 0.0 else def.tilt_speed_deg
		acc = (deg_to_rad(speed * GameState.stats.pour_speed_mult) - tilt_vel) * def.tilt_response
	else:
		acc = -def.return_force - def.return_damp * tilt_vel
	tilt_vel += acc * dt
	tilt += tilt_vel * dt
	var max_tilt := deg_to_rad(def.max_tilt_deg)
	if tilt < 0.0:
		tilt = 0.0
		# Clunk back onto the table; small speeds just settle.
		tilt_vel = -tilt_vel * def.rest_bounce if tilt_vel < -0.2 else 0.0
	elif tilt > max_tilt:
		tilt = max_tilt
		tilt_vel = minf(tilt_vel, 0.0)
	rotation = -(_rest() + tilt)

	var tilt_acc := (tilt_vel - prev_vel) / dt
	slosh_vel += (-def.slosh_spring * slosh - def.slosh_damp * slosh_vel - def.slosh_gain * tilt_acc) * dt
	slosh = clampf(slosh + slosh_vel * dt, -def.slosh_max, def.slosh_max)

	if refilling:
		_step_refill(dt)

	excess = volume - _area_below(Vector2.ZERO, _local_surface_angle())
	var out := 0.0
	if excess > MIN_EXCESS:
		exit_speed = def.stream_speed_min + def.stream_speed_k * sqrt(excess)
		out = minf(excess * (1.0 - exp(-def.pour_rate * dt)), def.max_flow * dt)
		volume -= out
	flow = out / dt
	_update_surface()
	return out


func _step_refill(dt: float) -> void:
	var bottle := def.refill_style == DrinkDef.RefillStyle.NEW_BOTTLE
	if _refill_t < 0.0:
		if tilt > 0.0 or tilt_vel != 0.0:
			return  # still swinging back upright
		_refill_t = 0.0
		_refill_from = volume
		if bottle:
			# You don't refill a bottle: this one goes, a new corked one comes and is uncorked.
			vanished.emit(center_global())
			volume = full_volume
			_start_arrival(maxf(GameState.stats.refill_time - Arrival.ARRIVE_TIME, MIN_UNCORK), true)
			return
	if bottle:
		if not corked:
			refilling = false  # the cork just popped
		return
	_refill_t += dt
	var duration: float = GameState.stats.refill_time
	var t := clampf(_refill_t / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	volume = lerpf(_refill_from, full_volume, t)
	if t >= 1.0:
		refilling = false


func _start_arrival(uncork_time: float, wiggle: bool) -> void:
	position = Vector2(OFFSCREEN_X, home.y)
	_arrive_t = 0.0
	_uncork_time = uncork_time
	_wiggle = wiggle
	corked = def.refill_style == DrinkDef.RefillStyle.NEW_BOTTLE
	_pivot = Arrival.pivot(def.pourer_outer, -_rest(), -1.0)
	_apply_lean(0.0)


func _step_arrival(dt: float) -> void:
	if _arrive_t < 0.0:
		return
	var was_sliding := is_arriving()
	_arrive_t += dt
	position.x = home.x + Arrival.offset(_arrive_t, OFFSCREEN_X - home.x)
	if was_sliding and not is_arriving():
		landed.emit(to_global(_pivot))
	var angle := Arrival.lean(_arrive_t, -1.0)
	if corked:
		var uncorking := _arrive_t - Arrival.ARRIVE_TIME
		if _wiggle and uncorking > 0.0:
			angle += deg_to_rad(WIGGLE_DEG) * (uncorking / _uncork_time) * sin(uncorking * WIGGLE_FREQ)
		if uncorking >= _uncork_time - 1e-6:
			corked = false
			var m := _mouth()
			popped.emit(to_global(Vector2(m.x + m.y * 0.5, -2.0)), Vector2(0.0, -CORK_SPEED).rotated(rotation), def.liquid_highlight)
	_apply_lean(angle)
	if not corked and Arrival.done(_arrive_t):
		_arrive_t = -1.0
		_apply_lean(0.0)


## Turns the drawing (not the node: tilt, the spout and the stream don't see
## it) by `angle` about the arrival pivot.
func _apply_lean(angle: float) -> void:
	for layer: Node2D in [_back, _liquid, _front]:
		layer.rotation = angle
		layer.position = _pivot - _pivot.rotated(angle)


## The rest angle (radians); tilt counts from it.
func _rest() -> float:
	return deg_to_rad(def.pourer_rest_deg) if def != null else 0.0


## The interior's top edge — a bottle's mouth — as x = left, y = width.
func _mouth() -> Vector2:
	var top := INF
	for p in interior:
		top = minf(top, p.y)
	var lo := INF
	var hi := -INF
	for p in interior:
		if p.y - top < 0.5:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return Vector2(lo, hi - lo)


func exit_velocity() -> Vector2:
	return def.spout_dir.normalized().rotated(rotation) * exit_speed


func is_pouring() -> bool:
	return flow > 0.0


func at_rest() -> bool:
	return tilt <= 0.0001 and absf(tilt_vel) < 0.01 and not is_pouring()


## Surface angle in local space: world-level (rotated back by rest + tilt) plus slosh.
func _local_surface_angle() -> float:
	return _rest() + tilt + slosh


func _update_surface() -> void:
	_surf_angle = _local_surface_angle()
	var shown := minf(volume, _area_below(Vector2.ZERO, _surf_angle))
	var u := Vector2.from_angle(_surf_angle)
	var n := Vector2(-u.y, u.x)
	# Binary search how far below the lip the surface sits for this volume.
	var lo := 0.0
	var hi := 200.0
	for i in 22:
		var mid := (lo + hi) * 0.5
		if _area_below(n * mid, _surf_angle) > shown:
			lo = mid
		else:
			hi = mid
	_surf_point = n * lo
	_back.queue_redraw()
	_liquid.queue_redraw()
	_front.queue_redraw()


## Interior ∩ half-plane below the line through `point` at `angle` (local).
func _liquid_shape(point: Vector2, angle: float) -> Array[PackedVector2Array]:
	var u := Vector2.from_angle(angle)
	var n := Vector2(-u.y, u.x)
	var half := PackedVector2Array([
		point - u * 400.0, point + u * 400.0, point + u * 400.0 + n * 400.0, point - u * 400.0 + n * 400.0,
	])
	return Geometry2D.intersect_polygons(interior, half)


func _area_below(point: Vector2, angle: float) -> float:
	var total := 0.0
	for poly in _liquid_shape(point, angle):
		total += poly_area(poly)
	return total


static func poly_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


## The liquid as drawn: the interior below the current surface, minus
## sub-pixel slivers. Clipping can leave a near-zero-area sliver where the
## surface passes a hair from a corner (or when almost nothing sits below the
## lip); Godot can't triangulate those, and they're invisible anyway.
func liquid_polygons() -> Array[PackedVector2Array]:
	var polys: Array[PackedVector2Array] = []
	for poly in _liquid_shape(_surf_point, _surf_angle):
		if poly_area(poly) >= 0.5:
			polys.append(poly)
	return polys


## liquid_polygons() cut to the rounded inside the pourer is drawn with, minus slivers.
func drawn_liquid_polygons() -> Array[PackedVector2Array]:
	var polys: Array[PackedVector2Array] = []
	for liquid in liquid_polygons():
		for poly in Geometry2D.intersect_polygons(liquid, _drawn_interior):
			if poly_area(poly) >= 0.5:
				polys.append(poly)
	return polys


## Behind the liquid: the glass body's tint and a soft dark outline (the handle's too).
func _draw_back(ci: CanvasItem) -> void:
	if def == null:
		return
	var closed := _drawn_outer.duplicate()
	closed.append(_drawn_outer[0])
	ci.draw_colored_polygon(_drawn_outer, def.pourer_glass_color)
	ci.draw_polyline(closed, Color(Palette.INK, 0.35), 0.7, true)
	if def.pourer_handle.size() >= 2:
		ci.draw_polyline(def.pourer_handle, Color(Palette.INK, 0.3), 4.0, true)


func _draw_liquid(ci: CanvasItem) -> void:
	if def == null or volume < 1.0:
		return
	for poly in drawn_liquid_polygons():
		ci.draw_colored_polygon(poly, Color.WHITE)  # the liquid shader colours it


func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	var g := def.pourer_glass_color
	var box := _bounds(_drawn_outer)
	# Tinted glass shades the liquid behind its front wall.
	ci.draw_colored_polygon(_drawn_interior, Color(g.darkened(0.3), minf(g.a * 0.55, 0.35)))
	for wall in _walls:
		VesselArt.draw_hgradient(ci, wall, box.position.x, box.end.x, _wall_tex)
	if volume >= 1.0:
		var u := Vector2.from_angle(_surf_angle)
		var line := PackedVector2Array([_surf_point - u * 200.0, _surf_point + u * 200.0])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, _drawn_interior):
			ci.draw_polyline(seg, Color(def.liquid_highlight.lerp(Palette.WHITE, 0.5), 0.3), 1.8, true)
			ci.draw_polyline(seg, Color(def.liquid_highlight.lerp(Palette.WHITE, 0.75), 0.85), 0.45, true)
	if def.pourer_label.has_area():
		_draw_label(ci, def.pourer_label)
	if def.pourer_foil.has_area():
		_draw_foil(ci, def.pourer_foil)
	var inner := _bounds(_drawn_interior)
	VesselArt.draw_streak(ci, VesselArt.inner_streak(_drawn_interior, inner.position.y + 3.0, inner.end.y - 6.0, 2.3), Color(Palette.WHITE, 0.45), 1.8)
	VesselArt.draw_streak(ci, VesselArt.inner_streak(_drawn_interior, inner.position.y + 20.0, lerpf(inner.position.y, inner.end.y, 0.6), 4.8), Color(Palette.WHITE, 0.25), 0.6)
	VesselArt.draw_rim_light(ci, _drawn_outer, Color(Palette.WHITE, 0.6), 0.45)
	var m := _mouth()
	if def.refill_style == DrinkDef.RefillStyle.NEW_BOTTLE:
		var ring := VesselArt.rounded(_rect_poly(Rect2(m.x - 2.8, box.position.y - 0.8, m.y + 5.6, 3.4)), 1.2)
		ci.draw_colored_polygon(ring, Color(g.lightened(0.45), 0.8))
	else:
		var rim := VesselArt.span_at(_drawn_outer, box.position.y + 0.3)
		ci.draw_line(Vector2(rim.x + 0.4, box.position.y + 0.35), Vector2(rim.y - 0.4, box.position.y + 0.35), Color(Palette.WHITE, 0.6), 0.5, true)
	if def.pourer_handle.size() >= 2:
		ci.draw_polyline(def.pourer_handle, Color(Palette.FROST, 0.32), 3.0, true)
		var shine := def.pourer_handle.duplicate()
		for i in shine.size():
			shine[i] += Vector2(-0.6, -0.4)
		ci.draw_polyline(shine, Color(Palette.WHITE, 0.55), 0.6, true)
	if corked:
		var cork := VesselArt.rounded(_rect_poly(Rect2(m.x + 0.6, -3.4, m.y - 1.2, 5.4)), 0.8)
		ci.draw_colored_polygon(cork, Palette.BROWN)
		ci.draw_line(Vector2(m.x + 1.0, -3.0), Vector2(m.x + m.y - 1.0, -3.0), Palette.TAN, 0.8, true)


## A paper label round the body: cream, shaded toward the edges, thin rules and a small grape emblem.
func _draw_label(ci: CanvasItem, r: Rect2) -> void:
	VesselArt.draw_hgradient(ci, _rect_poly(r), r.position.x, r.end.x, _label_tex())
	var ink := Color(Palette.WINE, 0.85)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 3.0, r.size.x, 0.6), ink)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 3.6, r.size.x, 0.6), ink)
	var c := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.38)
	ci.draw_arc(c, 6.0, 0.0, TAU, 32, ink, 0.6, true)
	for d in [Vector2(-1.6, -1.4), Vector2(1.6, -1.4), Vector2(0, 1.4), Vector2(-1.6, 4.0), Vector2(1.6, 4.0), Vector2(0, -4.0)]:
		ci.draw_circle(c + d * Vector2(1, 0.75) + Vector2(0, -1.0), 1.0, ink)
	ci.draw_rect(Rect2(c.x - 12.0, r.end.y - 14.0, 24.0, 1.4), ink)
	ci.draw_rect(Rect2(c.x - 8.0, r.end.y - 9.5, 16.0, 0.9), Color(ink, 0.5))


## A foil capsule round the neck: dark red, a band of light down it.
func _draw_foil(ci: CanvasItem, r: Rect2) -> void:
	VesselArt.draw_hgradient(ci, VesselArt.rounded(_rect_poly(r), 0.8), r.position.x, r.end.x, _foil_tex())
	ci.draw_line(Vector2(r.position.x + 0.4, r.position.y + 0.3), Vector2(r.end.x - 0.4, r.position.y + 0.3), Color(Palette.SAND, 0.5), 0.5, true)


static var _label: GradientTexture1D
static var _foil: GradientTexture1D


static func _label_tex() -> GradientTexture1D:
	if _label == null:
		_label = VesselArt.gradient([[0.0, Palette.TAN], [0.28, Palette.LABEL], [0.7, Palette.LABEL.darkened(0.06)], [1.0, Palette.TAN.darkened(0.1)]])
	return _label


static func _foil_tex() -> GradientTexture1D:
	if _foil == null:
		_foil = VesselArt.gradient([[0.0, Palette.WINE.darkened(0.65)], [0.35, Palette.WINE.darkened(0.1)], [0.65, Palette.WINE.darkened(0.45)], [1.0, Palette.WINE.darkened(0.75)]])
	return _foil


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
