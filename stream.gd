class_name Stream
extends Node2D
## Liquid in flight between the spout and wherever it lands. Each physics tick
## of pouring emits one parcel carrying that tick's volume; parcels fly
## ballistically, so liquid already poured keeps arriving after the pitcher
## stops. Consecutive parcels are drawn joined as one smooth ribbon that thins
## as it falls and speeds up; at low flow the stream breaks into separate drops.

@export var gravity := 1400.0
## Below this flow (px²/s) the stream breaks into drops.
@export var drip_flow := 60.0
@export var drip_volume := 6.0
@export var table_y := 280.0
@export var splash_gain := 0.0015

class Parcel:
	var pos: Vector2
	var vel: Vector2
	var vol: float
	var tick: int
	var width: float  # drawn width at the spout (px); 0 for a lone drop
	var speed0: float  # speed when it left the spout
	var state := 0  # 0 = above the rim, 1 = inside the glass, 2 = missed it

var spilled := 0.0
var liquid_color := Palette.WATER
var liquid_highlight := Palette.WATER_LIGHT

var _parcels: Array[Parcel] = []
var _droplets: Array[Vector4] = []  # x, y, vx, vy — splash visuals only
var _droplet_floor: Array[float] = []
var _tick := 0
var _pending := 0.0
var _emitted := false
var _streaming := false
var _last_origin := Vector2.ZERO
var _last_vel := Vector2.ZERO
var _landing := Vector2.ZERO
var _landing_parcel_tick := -10
var _landing_tick := -10


func emit(origin: Vector2, velocity: Vector2, vol: float, dt: float) -> void:
	var flow := vol / dt
	_last_origin = origin
	_last_vel = velocity
	_emitted = true
	_streaming = flow >= drip_flow
	if flow < drip_flow:
		_pending += vol
		if _pending < drip_volume:
			return
		vol = _pending
		_pending = 0.0
		_spawn(origin, velocity, vol, 0.0)
		return
	_spawn(origin, velocity, vol, clampf(1.0 + sqrt(flow) / 14.0, 1.0, 4.0) * 1.2)


func set_drink(d: DrinkDef) -> void:
	liquid_color = d.liquid_color
	liquid_highlight = d.liquid_highlight


func _spawn(origin: Vector2, velocity: Vector2, vol: float, width: float) -> void:
	var p := Parcel.new()
	p.pos = origin
	p.vel = velocity
	p.vol = vol
	p.tick = _tick
	p.width = width
	p.speed0 = maxf(velocity.length(), 1.0)
	_parcels.append(p)


func is_empty() -> bool:
	return _parcels.is_empty() and _pending <= 0.0


func parcel_count() -> int:
	return _parcels.size()


## Liquid poured but not landed yet (px²), including a drop still forming on the lip.
func in_flight_volume() -> float:
	var total := _pending
	for p in _parcels:
		total += p.vol
	return total


func clear() -> void:
	_parcels.clear()
	_pending = 0.0


func step(dt: float, glass: Glass) -> void:
	# The pour stopped with a partial drop still hanging on the lip: let it go.
	if not _emitted and _pending > 0.0:
		_spawn(_last_origin, _last_vel, _pending, 0.0)
		_pending = 0.0
	if not _emitted:
		_streaming = false
	_emitted = false

	var rim := glass.rim_y_world()
	var opening := glass.opening_world()
	var alive: Array[Parcel] = []
	for p in _parcels:
		var prev_y := p.pos.y
		p.vel.y += gravity * dt
		p.pos += p.vel * dt
		if p.state == 0 and prev_y < rim and p.pos.y >= rim:
			p.state = 1 if p.pos.x > opening.x and p.pos.x < opening.y else 2
		if p.state == 1:
			p.pos.x = clampf(p.pos.x, opening.x + 0.5, opening.y - 0.5)
			var surface := glass.surface_y_world_at(p.pos.x)
			if p.pos.y >= surface:
				glass.receive(p.pos.x, p.vol, p.vel.length())
				_splash(Vector2(p.pos.x, surface), p)
				_landing = Vector2(p.pos.x, surface)
				_landing_parcel_tick = p.tick
				_landing_tick = _tick
				continue
		elif p.pos.y >= table_y:
			spilled += p.vol
			_splash(Vector2(p.pos.x, table_y), p)
			continue
		alive.append(p)
	_parcels = alive

	for i in range(_droplets.size() - 1, -1, -1):
		var d := _droplets[i]
		d.w += gravity * dt
		d.x += d.z * dt
		d.y += d.w * dt
		if d.w > 0.0 and d.y >= _droplet_floor[i]:
			_droplets.remove_at(i)
			_droplet_floor.remove_at(i)
		else:
			_droplets[i] = d
	_tick += 1
	queue_redraw()


func _splash(at: Vector2, p: Parcel) -> void:
	var energy := p.vol * p.vel.length() * splash_gain
	var count := int(energy) + (1 if randf() < fmod(energy, 1.0) else 0)
	for i in mini(count, 4):
		if _droplets.size() >= 80:
			return
		_droplets.append(Vector4(at.x, at.y - 1.0, randf_range(-45.0, 45.0), -randf_range(60.0, 160.0)))
		_droplet_floor.append(at.y)


## The closed outline of a stream through `points` with the given widths:
## the left edge forward, then the right edge back, each offset along the
## point's normal (from its neighbours' direction).
static func ribbon(points: PackedVector2Array, widths: PackedFloat32Array) -> PackedVector2Array:
	var n := points.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var dir := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-dir.y, dir.x) * widths[i] * 0.5
		left.append(points[i] + normal)
		right.append(points[i] - normal)
	right.reverse()
	return left + right


func _draw() -> void:
	var body := Color(liquid_color.lerp(liquid_highlight, 0.35), 0.85)
	var core := Color(liquid_highlight.lerp(Palette.WHITE, 0.25), 0.7)
	# Runs of parcels emitted on consecutive ticks are one continuous stream.
	var run: Array[Parcel] = []
	for p in _parcels:
		if not run.is_empty() and p.tick != run[-1].tick + 1:
			_draw_run(run, body, core)
			run = []
		run.append(p)
	if not run.is_empty():
		_draw_run(run, body, core)
	for d in _droplets:
		draw_circle(Vector2(d.x, d.y), 0.5, core)


## One continuous run (oldest first): from where it lands, if it is landing
## now, up to the spout, if it is still pouring.
func _draw_run(run: Array[Parcel], body: Color, core: Color) -> void:
	if run.size() == 1 and run[0].width <= 0.0:
		draw_circle(run[0].pos, 0.65, core)
		return
	var pts := PackedVector2Array()
	var widths := PackedFloat32Array()
	var oldest := run[0]
	if oldest.tick == _landing_parcel_tick + 1 and _tick - _landing_tick <= 2:
		pts.append(_landing)
		widths.append(_drawn_width(oldest))
	for p in run:
		pts.append(p.pos)
		widths.append(_drawn_width(p))
	var newest := run[-1]
	if _streaming and newest.tick == _tick - 1:
		pts.append(_last_origin)
		widths.append(maxf(newest.width, 0.6))
	if pts.size() < 2:
		draw_circle(pts[0], maxf(widths[0] * 0.45, 0.55), core)
		return
	var outline := ribbon(pts, widths)
	if not Geometry2D.triangulate_polygon(outline).is_empty():
		draw_colored_polygon(outline, body)
	else:  # a sharp kink folded the outline: draw it piece by piece
		for i in pts.size() - 1:
			var piece := ribbon(pts.slice(i, i + 2), widths.slice(i, i + 2))
			draw_colored_polygon(piece, body)
	var mean := 0.0
	for w in widths:
		mean += w
	draw_polyline(pts, core, maxf(mean / widths.size() * 0.25, 0.25), true)


## A parcel's width as it falls: the same flow moving faster is thinner.
func _drawn_width(p: Parcel) -> float:
	return maxf(maxf(p.width, 0.6) * sqrt(p.speed0 / maxf(p.vel.length(), p.speed0)), 0.5)
