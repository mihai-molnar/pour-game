class_name Glass
extends Node2D
## A glass (tumbler, mug, cup …) configured by a DrinkDef. Its inside is
## rasterized once into pixel columns/rows, so the volume → level mapping is
## exact to what's drawn. The surface is a 1D wave (one spring column per
## pixel) that the stream and glass motion excite; waves are visual only — the
## volume is the gameplay truth. The fill line is fixed per drink
## (fill_fraction × capacity) and the ±good_tol band is drawn beside it.

@export_group("Waves")
@export var wave_speed := 40.0
@export var wave_spring := 30.0
@export var wave_damp := 3.0
@export var wave_max := 6.0
## Downward kick per (volume × speed) of liquid landing.
@export var impact_gain := 0.0005
## Slosh from the glass sliding (liquid lags the motion).
@export var move_slosh := 0.0012

var def: DrinkDef
var interior := PackedVector2Array()
var outer := PackedVector2Array()
var volume := 0.0
var target := 0.0
var spilled := 0.0
var capacity := 0.0

var _x0 := 0
var _y0 := 0
var _col_top := PackedInt32Array()
var _col_bottom := PackedInt32Array()
var _row_area := PackedInt32Array()
var _row_left := PackedInt32Array()
var _row_right := PackedInt32Array()
var _wave_h := PackedFloat32Array()
var _wave_v := PackedFloat32Array()
var _level := 0.0
var _target_y := 0.0
var _bubbles: Array[Vector3] = []  # x, y (local), rise speed
var _drips: Array[Vector3] = []    # side (-1/1), y (local), speed
var _last_x := 0.0
var _last_vx := 0.0

@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front
@onready var _mat := _liquid.material as ShaderMaterial


func _ready() -> void:
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front
	_last_x = global_position.x


func setup(d: DrinkDef) -> void:
	def = d
	interior = d.glass_interior
	outer = d.glass_outer
	_rasterize()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in interior:
		lo = lo.min(p)
		hi = hi.max(p)
	_mat.set_shader_parameter("tint", d.liquid_color)
	_mat.set_shader_parameter("center_x", (lo.x + hi.x) * 0.5)
	_mat.set_shader_parameter("half_width", (hi.x - lo.x) * 0.5)
	_mat.set_shader_parameter("highlight_x", lo.x + 4.0)
	target = d.fill_fraction * capacity
	_target_y = level_for(target)
	reset()


## Empties the glass for the next serve (the fill line stays where it is).
func reset() -> void:
	volume = 0.0
	spilled = 0.0
	_level = level_for(0.0)
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
	_row_left.resize(rows)
	_row_left.fill(1 << 30)
	_row_right.resize(rows)
	_row_right.fill(-(1 << 30))
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
				_row_left[r] = mini(_row_left[r], _x0 + c)
				_row_right[r] = maxi(_row_right[r], _x0 + c)
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


func target_y() -> float:
	return _target_y


## Local rows of the ±good_tol band edges: x = upper (+tol), y = lower (−tol).
func band_levels() -> Vector2:
	var tol: float = GameState.stats.good_tol
	return Vector2(roundf(level_for(target * (1.0 + tol))), roundf(level_for(target * (1.0 - tol))))


func rim_y_world() -> float:
	return global_position.y + _y0


## World x range of the opening (the interior's top pixel row).
func opening_world() -> Vector2:
	return Vector2(global_position.x + _row_left[0], global_position.x + _row_right[0] + 1)


## Outer wall x (left, right) at local y.
func outer_x_at(y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := outer.size()
	for i in n:
		var a := outer[i]
		var b := outer[(i + 1) % n]
		if a.y != b.y and (a.y - y) * (b.y - y) <= 0.0:
			var x := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
			lo = minf(lo, x)
			hi = maxf(hi, x)
	return Vector2(lo, hi)


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
			_drips.append(Vector3(1.0 if randf() < 0.5 else -1.0, float(_y0), randf_range(30.0, 60.0)))
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


func _draw_liquid(ci: CanvasItem) -> void:
	if def == null or volume < 0.5:
		return
	for c in _col_top.size():
		var top := maxi(roundi(_surface_local(c)), _col_top[c])
		if top < _col_bottom[c]:
			ci.draw_rect(Rect2(_x0 + c, top, 1, _col_bottom[c] - top), Color.WHITE)


func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	ci.draw_colored_polygon(outer, Color(Palette.FROST, 0.08))
	for wall in DrawLayer.wall_polygons(outer, interior):
		ci.draw_colored_polygon(wall, Color(Palette.FROST, 0.3))

	# Meniscus + bubbles.
	if volume >= 0.5:
		for c in _col_top.size():
			var top := maxi(roundi(_surface_local(c)), _col_top[c])
			if top < _col_bottom[c]:
				ci.draw_rect(Rect2(_x0 + c, top, 1, 1), Color(Palette.WHITE, 0.55))
	for b in _bubbles:
		ci.draw_rect(Rect2(floorf(b.x), floorf(b.y), 1, 1), Color(Palette.WHITE, 0.7))

	_draw_band(ci)
	_draw_fill_line(ci)

	# Walls: outlines inset/outset half a pixel so 1 px lines land on the glass's own pixels.
	for poly in Geometry2D.offset_polygon(outer, -0.5, Geometry2D.JOIN_MITER):
		DrawLayer.draw_outline(ci, poly, Palette.FROST, Color(Palette.FROST, 0.7))
	for poly in Geometry2D.offset_polygon(interior, 0.5, Geometry2D.JOIN_MITER):
		DrawLayer.draw_outline(ci, poly, Color(Palette.MIST, 0.5), Color(0, 0, 0, 0))
	# Highlights, derived from the interior's row spans.
	var rows := _row_left.size()
	for r in range(6, rows - 6):
		ci.draw_rect(Rect2(_row_left[r] + 3, _y0 + r, 1, 1), Color(Palette.WHITE, 0.55))
	for r in range(8, mini(22, rows)):
		ci.draw_rect(Rect2(_row_right[r] - 3, _y0 + r, 1, 1), Color(Palette.WHITE, 0.35))

	# Drips running down the outside after an overflow.
	for d in _drips:
		var walls := outer_x_at(d.y)
		var px := floorf(walls.y) if d.x > 0.0 else floorf(walls.x) - 1.0
		ci.draw_rect(Rect2(px, floorf(d.y), 1, 2), def.liquid_highlight)


## The ±good_tol band: a light bracket (spine + end ticks pointing at the
## glass) just outside the left wall, outlined dark so it reads on any background.
func _draw_band(ci: CanvasItem) -> void:
	var band := band_levels()
	var y_top := int(band.x)
	var y_bot := int(band.y)
	var x := floori(outer_x_at(float(y_top)).x) - 4
	var h := y_bot - y_top + 1
	ci.draw_rect(Rect2(x - 1, y_top - 1, 3, h + 2), Palette.INK)
	ci.draw_rect(Rect2(x - 1, y_top - 1, 5, 3), Palette.INK)
	ci.draw_rect(Rect2(x - 1, y_bot - 1, 5, 3), Palette.INK)
	ci.draw_rect(Rect2(x, y_top, 1, h), Palette.FROST)
	ci.draw_rect(Rect2(x, y_top, 3, 1), Palette.FROST)
	ci.draw_rect(Rect2(x, y_bot, 3, 1), Palette.FROST)


## The fill line: a 1 px white line with dark rows above and below across the
## inside, plus outlined ticks outside the walls. The left tick runs from the
## band bracket to the wall, so it reads as the bracket's centre mark.
func _draw_fill_line(ci: CanvasItem) -> void:
	var ty := roundi(_target_y)
	var r := ty - _y0
	if r < 0 or r >= _row_left.size():
		return
	var left := _row_left[r]
	var width := _row_right[r] - left + 1
	ci.draw_rect(Rect2(left, ty - 1, width, 3), Palette.INK)
	ci.draw_rect(Rect2(left, ty, width, 1), Palette.WHITE)
	var walls := outer_x_at(float(ty) + 0.5)
	var bracket_x := floori(outer_x_at(band_levels().x).x) - 4
	var left_end := floori(walls.x) - 2
	ci.draw_rect(Rect2(bracket_x - 1, ty - 1, left_end - bracket_x + 2, 3), Palette.INK)
	ci.draw_rect(Rect2(bracket_x, ty, left_end - bracket_x, 1), Palette.WHITE)
	# Short right tick: the pourer's wall sits ~4 px to the right of the glass.
	var right_start := ceili(walls.y) + 1
	ci.draw_rect(Rect2(right_start - 1, ty - 1, 4, 3), Palette.INK)
	ci.draw_rect(Rect2(right_start, ty, 2, 1), Palette.WHITE)
