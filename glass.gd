class_name Glass
extends Node2D
## A glass (tumbler, mug, cup …) configured by a DrinkDef. Its inside is
## rasterized once into pixel columns/rows (world px), so the volume → level
## mapping is exact. The surface is a 1D wave (one spring column per pixel
## column) that the stream and glass motion excite; waves are visual only — the
## volume is the gameplay truth. The fill line is fixed per drink
## (fill_fraction × capacity); scoring counts rows from it (rows_from_line) and
## the scoring band is drawn beside it, on exactly the rows scoring rounds to.
## It is drawn smooth from rounded copies of the DrinkDef shapes.
## A new glass arrives by sliding in from the left (arrive()); the lean only
## turns the Liquid and Front layers, never this node, so landing liquid and
## the rim/opening helpers never see it.

@export_group("Waves")
@export var wave_speed := 40.0
@export var wave_spring := 30.0
@export var wave_damp := 3.0
@export var wave_max := 6.0
## Downward kick per (volume × speed) of liquid landing.
@export var impact_gain := 0.0005
## Slosh from the glass sliding (liquid lags the motion).
@export var move_slosh := 0.0012

## Emitted when an arrival stops sliding; `at` = the foot corner it tips over (global).
signal landed(at: Vector2)

## Where an arriving glass starts: fully off-screen left.
const OFFSCREEN_X := -40.0

var def: DrinkDef
var interior := PackedVector2Array()
var outer := PackedVector2Array()
var volume := 0.0
var target := 0.0
var spilled := 0.0
var capacity := 0.0
## Where it rests (in Main's space).
var home := Vector2.ZERO

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
var _drawn_outer := PackedVector2Array()
var _drawn_interior := PackedVector2Array()
var _walls: Array[PackedVector2Array] = []
var _bubbles: Array[Vector3] = []  # x, y (local), rise speed
var _drips: Array[Vector3] = []    # side (-1/1), y (local), speed
var _last_x := 0.0
var _last_vx := 0.0
var _arrive_t := -1.0  # < 0 when not arriving (covers the slide and the wobble)
var _pivot := Vector2.ZERO

@onready var _back: DrawLayer = $Back
@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front
@onready var _mat := _liquid.material as ShaderMaterial


func _ready() -> void:
	_back.draw_func = _draw_back
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front
	_last_x = global_position.x


func setup(d: DrinkDef) -> void:
	def = d
	interior = d.glass_interior
	outer = d.glass_outer
	_rasterize()
	_drawn_outer = VesselArt.rounded(outer, d.glass_corner_radius)
	_drawn_interior = VesselArt.rounded(interior, d.glass_corner_radius, true)
	_walls = VesselArt.walls(_drawn_outer, _drawn_interior)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in interior:
		lo = lo.min(p)
		hi = hi.max(p)
	_mat.set_shader_parameter("tint", d.liquid_color)
	_mat.set_shader_parameter("absorb", d.liquid_absorb)
	_mat.set_shader_parameter("scatter", d.liquid_scatter)
	_mat.set_shader_parameter("center_x", (lo.x + hi.x) * 0.5)
	_mat.set_shader_parameter("half_width", (hi.x - lo.x) * 0.5)
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


## Sets the glass up for `d` (empty), puts it off-screen left and starts
## sliding it to `at`.
func arrive(d: DrinkDef, at: Vector2) -> void:
	setup(d)
	home = at
	position = Vector2(OFFSCREEN_X, at.y)
	visible = true
	_last_x = position.x
	_last_vx = 0.0
	_pivot = Arrival.pivot(outer, 0.0, 1.0)
	_arrive_t = 0.0
	_apply_lean(0.0)


## Puts the glass at `at` at once, no arrival — for the sweep and checks.
func place(at: Vector2) -> void:
	home = at
	position = at
	visible = true
	_last_x = at.x
	_last_vx = 0.0
	_arrive_t = -1.0
	_apply_lean(0.0)


## The served glass disappears (Main leaves a puff where it was).
func vanish() -> void:
	visible = false
	_arrive_t = -1.0
	_apply_lean(0.0)


## True while sliding in; the wobble after it doesn't count.
func is_arriving() -> bool:
	return _arrive_t >= 0.0 and _arrive_t < Arrival.ARRIVE_TIME


func center_global() -> Vector2:
	var box := Rect2(outer[0], Vector2.ZERO)
	for p in outer:
		box = box.expand(p)
	return to_global(box.get_center())


func _step_arrival(dt: float) -> void:
	if _arrive_t < 0.0:
		return
	var was_sliding := is_arriving()
	_arrive_t += dt
	position.x = home.x + Arrival.offset(_arrive_t, OFFSCREEN_X - home.x)
	if was_sliding and not is_arriving():
		landed.emit(to_global(_pivot))
	_apply_lean(Arrival.lean(_arrive_t, 1.0))
	if Arrival.done(_arrive_t):
		_arrive_t = -1.0
		_apply_lean(0.0)


## Turns the drawing by `angle` about the arrival pivot (the node stays put).
func _apply_lean(angle: float) -> void:
	for layer: Node2D in [_back, _liquid, _front]:
		layer.rotation = angle
		layer.position = _pivot - _pivot.rotated(angle)


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


## How many pixel rows the settled surface holding `vol` sits from the fill
## line, as drawn (waves don't count).
func rows_from_line(vol: float) -> int:
	return absi(roundi(level_for(vol)) - roundi(_target_y))


## Local y the fill line is drawn on: the target's row, which is what
## rows_from_line rounds the target to.
func line_y() -> float:
	return float(roundi(_target_y))


## Local y (top, bottom) of "within `rows` rows of the line" as scoring rounds
## it — line_y() ± (rows + 0.5) — cut to the inside of the glass.
func band_edges(rows: int) -> Vector2:
	var ly := line_y()
	return Vector2(maxf(ly - rows - 0.5, float(_y0)), minf(ly + rows + 0.5, float(_y0 + _row_area.size())))


## Local x of the band bracket's spine: 3 px left of the outer wall's leftmost
## point across the GOOD ENOUGH band, so it also clears bowls that bulge.
func bracket_x() -> float:
	var band := band_edges(GameState.stats.ok_rows)
	var left := INF
	var y := band.x
	while y <= band.y:
		left = minf(left, outer_x_at(y).x)
		y += 0.5
	return left - 3.0


## The liquid as drawn (local): the wave surface across the pixel columns down
## to the floor, cut to the rounded inside. Empty when there is (next to)
## nothing — Godot can't triangulate sub-pixel slivers.
func liquid_polygon() -> PackedVector2Array:
	if def == null or volume < 0.5:
		return PackedVector2Array()
	var n := _col_top.size()
	var bottom := float(_y0 + _row_area.size()) + 1.0
	var shape := PackedVector2Array([Vector2(_x0 - 1.0, _level - _wave_h[0])])
	for c in n:
		shape.append(Vector2(_x0 + c + 0.5, _level - _wave_h[c]))
	shape.append(Vector2(_x0 + n + 1.0, _level - _wave_h[n - 1]))
	shape.append(Vector2(_x0 + n + 1.0, bottom))
	shape.append(Vector2(_x0 - 1.0, bottom))
	var best := PackedVector2Array()
	var best_area := 0.5
	for poly in Geometry2D.intersect_polygons(_drawn_interior, shape):
		var a := Pourer.poly_area(poly)
		if a >= best_area:
			best = poly
			best_area = a
	return best


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
	_step_arrival(dt)
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
			if volume >= 0.5:  # an empty glass has nothing to slosh (arrivals would leave waves)
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
		# It pops at the surface, or at the wall where a bowl narrows toward the rim.
		if volume < 0.5 or b.y <= maxf(_surface_local(c), float(_col_top[c])) + 1.0:
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

	_back.queue_redraw()
	_liquid.queue_redraw()
	_front.queue_redraw()


## Behind the liquid: the glass body's faint frost and a soft dark outline.
func _draw_back(ci: CanvasItem) -> void:
	if def == null:
		return
	var closed := _drawn_outer.duplicate()
	closed.append(_drawn_outer[0])
	ci.draw_colored_polygon(_drawn_outer, Color(Palette.FROST, 0.07))
	ci.draw_polyline(closed, Color(Palette.INK, 0.35), 0.7, true)


## Draws this glass into another canvas item (already transformed) for its
## reflection in the counter: body, the liquid as flat colour, walls — no
## light, no marks.
func draw_reflection(ci: CanvasItem) -> void:
	_draw_back(ci)
	var poly := liquid_polygon()
	if not poly.is_empty():
		ci.draw_colored_polygon(poly, def.liquid_color)
	var box := Rect2(_drawn_outer[0], Vector2.ZERO)
	for p in _drawn_outer:
		box = box.expand(p)
	for wall in _walls:
		VesselArt.draw_hgradient(ci, wall, box.position.x, box.end.x, VesselArt.clear_glass_walls())


func _draw_liquid(ci: CanvasItem) -> void:
	var poly := liquid_polygon()
	if not poly.is_empty():
		ci.draw_colored_polygon(poly, Color.WHITE)  # the liquid shader colours it


func _draw_front(ci: CanvasItem) -> void:
	if def == null:
		return
	var box := Rect2(_drawn_outer[0], Vector2.ZERO)
	for p in _drawn_outer:
		box = box.expand(p)
	for wall in _walls:
		VesselArt.draw_hgradient(ci, wall, box.position.x, box.end.x, VesselArt.clear_glass_walls())

	# The surface: a soft sheen with a bright line on top, following the waves.
	if volume >= 0.5:
		var surface := PackedVector2Array()
		for c in _col_top.size():
			var y := _level - _wave_h[c]
			if y >= _col_top[c] and y < _col_bottom[c]:
				surface.append(Vector2(_x0 + c + 0.5, y))
		if surface.size() >= 2:
			ci.draw_polyline(surface, Color(def.liquid_highlight.lerp(Palette.WHITE, 0.5), 0.3), 1.8, true)
			ci.draw_polyline(surface, Color(def.liquid_highlight.lerp(Palette.WHITE, 0.75), 0.9), 0.45, true)
	var fizz := def.liquid_highlight.lerp(Palette.WHITE, 0.6)
	for b in _bubbles:
		var at := Vector2(b.x, b.y)
		ci.draw_circle(at, 0.55, Color(fizz, 0.15))
		ci.draw_arc(at, 0.55, 0.0, TAU, 10, Color(fizz, 0.5), 0.22, true)

	# Light: streaks down the inside of the left wall, a rim of light on the right, the rim on top.
	var top := box.position.y
	var bottom := float(_y0 + _row_area.size())
	VesselArt.draw_streak(ci, VesselArt.inner_streak(_drawn_interior, top + 5.0, bottom - 7.0, 2.3), Color(Palette.WHITE, 0.5), 1.8)
	VesselArt.draw_streak(ci, VesselArt.inner_streak(_drawn_interior, top + 9.0, lerpf(top, bottom, 0.5), 4.4), Color(Palette.WHITE, 0.3), 0.6)
	VesselArt.draw_rim_light(ci, _drawn_outer, Color(Palette.WHITE, 0.7), 0.45)
	var rim := VesselArt.span_at(_drawn_outer, top + 0.3)
	var ellipse := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		ellipse.append(Vector2((rim.x + rim.y) * 0.5 + cos(a) * ((rim.y - rim.x) * 0.5 - 0.5), top + 0.35 + sin(a) * 1.8))
	ci.draw_polyline(ellipse, Color(Palette.WHITE, 0.22), 0.4, true)
	ci.draw_line(Vector2(rim.x + 0.4, top + 0.35), Vector2(rim.y - 0.4, top + 0.35), Color(Palette.WHITE, 0.78), 0.55, true)

	# Drips running down the outside after an overflow.
	for d in _drips:
		var walls := outer_x_at(d.y)
		ci.draw_circle(Vector2(walls.y + 0.4 if d.x > 0.0 else walls.x - 0.4, d.y), 0.7, def.liquid_highlight)

	_draw_band(ci)
	_draw_fill_line(ci)


## The scoring band: a light bracket (spine + end ticks pointing at the glass)
## left of the glass spanning GOOD ENOUGH (±ok_rows), with short inner ticks
## where GOOD (±good_rows) ends, underlaid dark so it reads on any background.
## PERFECT (±perfect_rows) is the fill line's dark band.
func _draw_band(ci: CanvasItem) -> void:
	var x := bracket_x()
	var ok := band_edges(GameState.stats.ok_rows)
	var good := band_edges(GameState.stats.good_rows)
	var spine := PackedVector2Array([Vector2(x + 1.6, ok.x), Vector2(x, ok.x), Vector2(x, ok.y), Vector2(x + 1.6, ok.y)])
	for look: Array in [[Color(Palette.INK, 0.6), 1.5], [Color(Palette.FROST, 0.95), 0.55]]:
		ci.draw_polyline(spine, look[0], look[1], true)
		for y in [good.x, good.y]:
			ci.draw_line(Vector2(x, y), Vector2(x + 1.1, y), look[0], look[1], true)


## The fill line: a thin white line on the target's row from the bracket to just
## past the right wall, over a dark band spanning the PERFECT rows.
func _draw_fill_line(ci: CanvasItem) -> void:
	var ly := line_y()
	var x0 := bracket_x()
	var x1 := outer_x_at(ly).y + 1.5
	var perfect := band_edges(GameState.stats.perfect_rows)
	ci.draw_rect(Rect2(x0, perfect.x, x1 - x0, perfect.y - perfect.x), Color(Palette.INK, 0.45))
	ci.draw_line(Vector2(x0, ly), Vector2(x1, ly), Palette.WHITE, 0.6, true)
