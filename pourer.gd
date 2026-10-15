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

@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front


func _ready() -> void:
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front


func setup(d: DrinkDef) -> void:
	def = d
	interior = d.pourer_interior
	capacity = poly_area(interior)
	full_volume = capacity * d.pourer_full_fraction
	var box := _bounds(interior)
	var mat := _liquid.material as ShaderMaterial
	mat.set_shader_parameter("tint", d.liquid_color)
	mat.set_shader_parameter("center_x", box.get_center().x)
	mat.set_shader_parameter("half_width", box.size.x * 0.5)
	mat.set_shader_parameter("surface_y", 0.0)
	mat.set_shader_parameter("highlight_x", box.position.x + 4.0)
	reset()


## At its rest angle, still, not refilling or arriving, holding `fill` × full_volume.
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
	for layer: Node2D in [_liquid, _front]:
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


## The highlight stripe: the interior's left-most long, mostly vertical edge,
## moved 4 px inward and shortened 8 px at both ends.
func _highlight_segment() -> PackedVector2Array:
	var best := -1
	var best_x := INF
	for i in interior.size():
		var a := interior[i]
		var b := interior[(i + 1) % interior.size()]
		var d := b - a
		if absf(d.y) > absf(d.x) * 2.0 and absf(d.y) > 20.0 and (a.x + b.x) * 0.5 < best_x:
			best = i
			best_x = (a.x + b.x) * 0.5
	if best < 0:
		return PackedVector2Array()
	var a := interior[best]
	var b := interior[(best + 1) % interior.size()]
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	if n.dot(_bounds(interior).get_center() - a) < 0.0:
		n = -n
	return PackedVector2Array([a + n * 4.0 + dir * 8.0, b + n * 4.0 - dir * 8.0])


func _draw_liquid(ci: CanvasItem) -> void:
	if def == null or volume < 1.0:
		return
	for poly in _liquid_shape(_surf_point, _surf_angle):
		ci.draw_colored_polygon(poly, Color.WHITE)


func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	var outer := def.pourer_outer
	var g := def.pourer_glass_color
	ci.draw_colored_polygon(outer, g)
	for wall in DrawLayer.wall_polygons(outer, interior):
		ci.draw_colored_polygon(wall, Color(g, minf(g.a * 3.0, 1.0)))
	# Liquid surface sparkle.
	if volume >= 1.0:
		var u := Vector2.from_angle(_surf_angle)
		var line := PackedVector2Array([_surf_point - u * 200.0, _surf_point + u * 200.0])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, interior):
			ci.draw_polyline(seg, Color(Palette.WHITE, 0.55))
	DrawLayer.draw_outline(ci, outer, Color(g, 1.0), Color(g, 0.45))
	DrawLayer.draw_outline(ci, interior, Color(Palette.MIST, 0.6), Color(0, 0, 0, 0))
	if def.pourer_handle.size() >= 2:
		ci.draw_polyline(def.pourer_handle, Color(Palette.FROST, 0.9), 3.0)
		ci.draw_polyline(def.pourer_handle, Color(Palette.MIST, 0.8))
	var hl := _highlight_segment()
	if hl.size() == 2:
		ci.draw_line(hl[0], hl[1], Color(Palette.WHITE, 0.5))
	# Glint on the outer vertex nearest the spout lip.
	var lip := outer[0]
	for p in outer:
		if p.length() < lip.length():
			lip = p
	ci.draw_rect(Rect2(lip.floor(), Vector2.ONE), Palette.WHITE)
	if corked:
		var m := _mouth()
		ci.draw_rect(Rect2(m.x + 1.0, -3.0, m.y - 2.0, 5.0), Palette.CLAY)
		ci.draw_rect(Rect2(m.x + 1.0, -3.0, m.y - 2.0, 1.0), Palette.TAN)
