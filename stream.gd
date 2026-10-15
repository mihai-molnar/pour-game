class_name Stream
extends Node2D
## Liquid in flight between the spout and wherever it lands. Each physics tick
## of pouring emits one parcel carrying that tick's volume; parcels fly
## ballistically, so liquid already poured keeps arriving after the pitcher
## stops. Consecutive parcels are drawn joined as a continuous stream; at low
## flow the stream breaks into separate drops.

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
	var width: int
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
	_spawn(origin, velocity, vol, clampi(int(1.0 + sqrt(flow) / 14.0), 1, 4))


func set_drink(d: DrinkDef) -> void:
	liquid_color = d.liquid_color
	liquid_highlight = d.liquid_highlight


func _spawn(origin: Vector2, velocity: Vector2, vol: float, width: int) -> void:
	var p := Parcel.new()
	p.pos = origin
	p.vel = velocity
	p.vol = vol
	p.tick = _tick
	p.width = width
	_parcels.append(p)


func is_empty() -> bool:
	return _parcels.is_empty() and _pending <= 0.0


func parcel_count() -> int:
	return _parcels.size()


func clear() -> void:
	_parcels.clear()
	_pending = 0.0


func step(dt: float, glass: Glass) -> void:
	# The pour stopped with a partial drop still hanging on the lip: let it go.
	if not _emitted and _pending > 0.0:
		_spawn(_last_origin, _last_vel, _pending, 1)
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


func _draw() -> void:
	var body := Color(liquid_color, 0.9)
	var core := Color(liquid_highlight, 0.9)
	var prev: Parcel = null
	for p in _parcels:
		if prev != null and p.tick == prev.tick + 1:
			_segment(prev.pos, p.pos, p.width, body, core)
		elif p.width == 1 and (prev == null or p.tick != prev.tick + 1):
			draw_rect(Rect2(p.pos.floor(), Vector2(1, 2)), core)
		prev = p
	if not _parcels.is_empty():
		var oldest := _parcels[0]
		if oldest.tick == _landing_parcel_tick + 1 and _tick - _landing_tick <= 2:
			_segment(oldest.pos, _landing, oldest.width, body, core)
		var newest := _parcels[-1]
		if _streaming and newest.tick == _tick - 1:
			_segment(_last_origin, newest.pos, newest.width, body, core)
	for d in _droplets:
		draw_rect(Rect2(floorf(d.x), floorf(d.y), 1, 1), core)


func _segment(a: Vector2, b: Vector2, width: int, body: Color, core: Color) -> void:
	if width <= 1:
		draw_line(a, b, core)
	else:
		draw_line(a, b, body, float(width))
		draw_line(a, b, core)
