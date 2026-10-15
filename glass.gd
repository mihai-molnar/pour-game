class_name Glass
extends Node2D
## A water tumbler. Its inside is rasterized once into pixel columns/rows, so
## the volume → level mapping is exact to what's drawn. The surface is a 1D
## wave (one spring column per pixel) that the stream and glass motion excite;
## waves are visual only — the volume is the gameplay truth.

@export_group("Target")
@export_range(0.1, 1.0) var target_min := 0.55
@export_range(0.1, 1.0) var target_max := 0.85
## |error| within this share of the target = PERFECT.
@export var perfect_tol := 0.03
## |error| within this share = GOOD (coins scale down toward the edge).
@export var good_tol := 0.10
@export var perfect_coins := 10
@export var good_coins_max := 8
@export var good_coins_min := 2

@export_group("Waves")
@export var wave_speed := 40.0
@export var wave_spring := 30.0
@export var wave_damp := 3.0
@export var wave_max := 6.0
## Downward kick per (volume × speed) of liquid landing.
@export var impact_gain := 0.0005
## Slosh from the glass sliding (liquid lags the motion).
@export var move_slosh := 0.0012

var interior := PackedVector2Array([Vector2(-15, -5), Vector2(15, -5), Vector2(19, -74), Vector2(-19, -74)])
var outer := PackedVector2Array([Vector2(-17, 0), Vector2(17, 0), Vector2(21, -74), Vector2(-21, -74)])
const RIM_Y := -74

var volume := 0.0
var target := 0.0
var spilled := 0.0
var capacity := 0.0

var _x0 := 0
var _y0 := 0
var _col_top := PackedInt32Array()
var _col_bottom := PackedInt32Array()
var _row_area := PackedInt32Array()
var _wave_h := PackedFloat32Array()
var _wave_v := PackedFloat32Array()
var _level := 0.0
var _target_y := 0.0
var _bubbles: Array[Vector3] = []  # x, y (local), rise speed
var _drips: Array[Vector3] = []    # x side (-1/1), y (local), speed
var _last_x := 0.0
var _last_vx := 0.0

@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front
@onready var _mat := _liquid.material as ShaderMaterial


func _ready() -> void:
	_rasterize()
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front
	_mat.set_shader_parameter("center_x", 0.0)
	_mat.set_shader_parameter("half_width", 19.0)
	_mat.set_shader_parameter("highlight_x", -15.0)
	_last_x = global_position.x
	reset()


func reset() -> void:
	volume = 0.0
	spilled = 0.0
	target = randf_range(target_min, target_max) * capacity
	_target_y = level_for(target)
	_wave_h.fill(0.0)
	_wave_v.fill(0.0)
	_bubbles.clear()
	_drips.clear()


func _rasterize() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in interior:
		lo = lo.min(p)
		hi = hi.max(p)
	_x0 = floori(lo.x)
	_y0 = floori(lo.y)
	var cols := ceili(hi.x) - _x0
	var rows := ceili(hi.y) - _y0
	_col_top.resize(cols)
	_col_bottom.resize(cols)
	_row_area.resize(rows)
	_row_area.fill(0)
	_wave_h.resize(cols)
	_wave_v.resize(cols)
	capacity = 0.0
	for c in cols:
		var top := 1 << 30
		var bottom := -(1 << 30)
		for r in rows:
			if Geometry2D.is_point_in_polygon(Vector2(_x0 + c + 0.5, _y0 + r + 0.5), interior):
				top = mini(top, _y0 + r)
				bottom = maxi(bottom, _y0 + r + 1)
				_row_area[r] += 1
				capacity += 1.0
		_col_top[c] = top
		_col_bottom[c] = bottom


## Local y of the calm surface holding `vol`.
func level_for(vol: float) -> float:
	var remaining := vol
	for r in range(_row_area.size() - 1, -1, -1):
		var a := float(_row_area[r])
		if a == 0.0:
			continue
		if remaining <= a:
			return _y0 + r + 1 - remaining / a
		remaining -= a
	return float(_y0)


func rim_y_world() -> float:
	return global_position.y + RIM_Y


## World x range of the opening at the rim.
func opening_world() -> Vector2:
	return Vector2(global_position.x + interior[3].x, global_position.x + interior[2].x)


func _col(x_world: float) -> int:
	return clampi(floori(x_world - global_position.x) - _x0, 0, _wave_h.size() - 1)


func _surface_local(c: int) -> float:
	if volume < 0.5:
		return float(_col_bottom[c])
	return minf(_level - _wave_h[c], float(_col_bottom[c]))


## True if the pixel at local (x, y) is inside the glass.
func _inside(x: float, y: float) -> bool:
	var c := floori(x) - _x0
	var r := floori(y)
	return c >= 0 and c < _col_top.size() and r >= _col_top[c] and r < _col_bottom[c]


func surface_y_world_at(x_world: float) -> float:
	return global_position.y + _surface_local(_col(x_world))


func receive(x_world: float, vol: float, speed: float) -> void:
	volume += vol
	if volume > capacity:
		spilled += volume - capacity
		volume = capacity
		if _drips.size() < 30:
			_drips.append(Vector3(1.0 if randf() < 0.5 else -1.0, RIM_Y, randf_range(30.0, 60.0)))
	var c := _col(x_world)
	var kick := vol * speed * impact_gain
	_wave_v[c] -= kick
	if c > 0:
		_wave_v[c - 1] -= kick * 0.5
	if c < _wave_v.size() - 1:
		_wave_v[c + 1] -= kick * 0.5
	if randf() < vol * speed * 0.0004 and _bubbles.size() < 40:
		# Spawn under the impact, but never deeper than this column's floor.
		var bc := clampi(c + randi_range(-2, 2), 0, _col_top.size() - 1)
		var top := _surface_local(bc) + 2.0
		var floor_y := float(_col_bottom[bc]) - 1.0
		if floor_y > top:
			var y := minf(top + randf_range(1.0, 2.0 + speed * 0.06), floor_y)
			_bubbles.append(Vector3(float(_x0 + bc) + 0.5, y, randf_range(8.0, 22.0)))


func step(dt: float) -> void:
	_level = level_for(volume)
	_mat.set_shader_parameter("surface_y", _level)

	var vx := (global_position.x - _last_x) / dt
	var ax := (vx - _last_vx) / dt
	_last_x = global_position.x
	_last_vx = vx

	var n := _wave_h.size()
	var mid := (n - 1) * 0.5
	var c2 := wave_speed * wave_speed
	var sdt := dt * 0.5
	for sub in 2:
		for i in n:
			var l := _wave_h[maxi(i - 1, 0)]
			var r := _wave_h[mini(i + 1, n - 1)]
			var acc := c2 * (l + r - 2.0 * _wave_h[i]) - wave_spring * _wave_h[i] - wave_damp * _wave_v[i]
			acc -= ax * move_slosh * (i - mid)
			_wave_v[i] += acc * sdt
		for i in n:
			_wave_h[i] = clampf(_wave_h[i] + _wave_v[i] * sdt, -wave_max, wave_max)

	for i in range(_bubbles.size() - 1, -1, -1):
		var b := _bubbles[i]
		b.y -= b.z * dt
		var wobbled := b.x + sin(b.y * 0.7) * 0.15
		if _inside(wobbled, b.y):
			b.x = wobbled
		var c := clampi(floori(b.x) - _x0, 0, n - 1)
		if volume < 0.5 or b.y <= _surface_local(c) + 1.0:
			_bubbles.remove_at(i)
		else:
			_bubbles[i] = b
	for i in range(_drips.size() - 1, -1, -1):
		var d := _drips[i]
		d.y += d.z * dt
		if d.y >= 0.0:
			_drips.remove_at(i)
		else:
			_drips[i] = d

	_liquid.queue_redraw()
	_front.queue_redraw()


## Scores the current fill. Returns {band, coins, error} where error is signed (share of target).
func evaluate() -> Dictionary:
	var err := (volume - target) / target
	var a := absf(err)
	if spilled > 0.5:
		return {"band": "SPILL", "coins": 0, "error": err}
	if a <= perfect_tol:
		return {"band": "PERFECT", "coins": perfect_coins, "error": err}
	if a <= good_tol:
		var t := (a - perfect_tol) / (good_tol - perfect_tol)
		return {"band": "GOOD", "coins": roundi(lerpf(good_coins_max, good_coins_min, t)), "error": err}
	return {"band": "MISS", "coins": 0, "error": err}


func _wall_x(y: float, side: float) -> float:
	# Outer wall x at local y (walls taper from 17 at the base to 21 at the rim).
	return side * (17.0 + 4.0 * (-y) / 74.0)


func _draw_liquid(ci: CanvasItem) -> void:
	if volume < 0.5:
		return
	for c in _col_top.size():
		var top := maxi(roundi(_surface_local(c)), _col_top[c])
		if top < _col_bottom[c]:
			ci.draw_rect(Rect2(_x0 + c, top, 1, _col_bottom[c] - top), Color.WHITE)


func _px(ci: CanvasItem, a: Vector2, b: Vector2, color: Color) -> void:
	ci.draw_line(a + Vector2(0.5, 0.5), b + Vector2(0.5, 0.5), color)


func _draw_front(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(outer, Color(Palette.FROST, 0.08))
	ci.draw_rect(Rect2(-17, -5, 34, 5), Color(Palette.FROST, 0.3))

	# Meniscus + bubbles.
	if volume >= 0.5:
		for c in _col_top.size():
			var top := maxi(roundi(_surface_local(c)), _col_top[c])
			if top < _col_bottom[c]:
				ci.draw_rect(Rect2(_x0 + c, top, 1, 1), Color(Palette.WHITE, 0.55))
	for b in _bubbles:
		ci.draw_rect(Rect2(floorf(b.x), floorf(b.y), 1, 1), Color(Palette.WHITE, 0.7))

	# Fill line: dashes inside, ticks outside.
	var ty := roundi(_target_y)
	var half := int(17.0 + 4.0 * (-ty) / 74.0) - 2
	for x in range(-half, half, 4):
		ci.draw_rect(Rect2(x, ty, 2, 1), Color(Palette.GOLD, 0.9))
	var outer_x := int(_wall_x(ty, 1.0))
	ci.draw_rect(Rect2(outer_x + 2, ty, 4, 1), Palette.GOLD)
	ci.draw_rect(Rect2(-outer_x - 6, ty, 4, 1), Palette.GOLD)

	# Walls.
	_px(ci, Vector2(-21, -74), Vector2(-17, -1), Palette.FROST)
	_px(ci, Vector2(20, -74), Vector2(16, -1), Palette.FROST)
	_px(ci, Vector2(-17, -1), Vector2(16, -1), Palette.FROST)
	_px(ci, Vector2(-19, -73), Vector2(-15, -6), Color(Palette.MIST, 0.5))
	_px(ci, Vector2(18, -73), Vector2(14, -6), Color(Palette.MIST, 0.5))
	_px(ci, Vector2(-21, -74), Vector2(20, -74), Color(Palette.FROST, 0.7))
	# Highlights.
	_px(ci, Vector2(-16, -68), Vector2(-13, -12), Color(Palette.WHITE, 0.55))
	_px(ci, Vector2(15, -66), Vector2(14, -52), Color(Palette.WHITE, 0.35))
	ci.draw_rect(Rect2(-21, -74, 1, 1), Palette.WHITE)
	ci.draw_rect(Rect2(20, -74, 1, 1), Palette.WHITE)

	for d in _drips:
		ci.draw_rect(Rect2(floorf(_wall_x(d.y, d.x)) + (0.0 if d.x > 0 else -1.0), floorf(d.y), 1, 2), Palette.WATER_LIGHT)
