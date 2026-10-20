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
## the rim/opening helpers never see it. It holds the garnishes added while it
## is served: ice falls in and takes up room (surface_level, max_liquid — what
## is drawn and scored) and, once landed, bounces, floats and drifts in a small
## visual-only simulation (IcePhysics); a lime wedge drops onto the left rim.
## A beer glass holds a head (Foam) on top of the beer: it takes up room (a
## head over the rim is a spill) and drains beer back into the glass. It is
## also held tipped toward the pourer while pouring (step_tilt): tipping is
## gameplay — the liquid's surface stays level in the world, so in the glass's
## own frame it is a sloped line (calm_y) whose height for a volume is solved
## over the pixel columns, and a tipped glass holds less — but the glass is
## always upright again before it is served. The tilt turns the draw layers
## about the mouth (frame()); the node never rotates.

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
## Emitted when a garnish lands in or on the glass; `at` = where (global).
signal garnish_landed(g: GarnishDef, at: Vector2)

## Where an arriving glass starts: fully off-screen left.
const OFFSCREEN_X := -40.0
## Seconds from adding ice until it lands in the glass, and the lime on the rim.
const ICE_FALL_TIME := 0.35
const LIME_DROP_TIME := 0.25
## Where falling ice starts (local y, just above the camera's view).
const ICE_DROP_Y := -215.0
## How far the lime drops onto the rim (px).
const LIME_DROP_PX := 14.0
## The lime wedge: radius (px) and turn (rad; peel up and out to the left).
const LIME_RADIUS := 9.0
const LIME_ANGLE := -0.7
## Per cube while it falls in: x nudge (px), tilt (rad), tumble (rad), how much
## deeper it lands (px) — so the cubes don't drop like soldiers.
const CUBE_LOOKS := [Vector4(-0.6, -0.14, 2.6, 0.5), Vector4(0.4, 0.09, -3.1, -0.4)]
## The fastest a cube enters the glass (px/s): the scripted fall ends faster.
const ICE_ENTRY_SPEED := 220.0
## Sparkling water: how fast its bubbles rise (px/s, min and max; beer's rise
## 6–14), about how many cling to the walls, how long a pop's glint lasts (s).
const SPARKLE_RISE := Vector2(12.0, 24.0)
const WALL_BUBBLES := 8
const GLINT_TIME := 0.15
## Tipping while pouring: time constants (s) tipping in and coming back, how
## long a gap in the pour it rides out (s), and the angle (rad) it snaps upright from.
const TILT_IN := 0.1
const TILT_OUT := 0.12
const TILT_GRACE := 0.25
const TILT_SNAP := 0.002

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
## The garnishes added to this glass, in order (landed or still dropping).
var garnishes: Array[GarnishDef] = []
## Draw the scoring band and the fill line (off for a glass drawn elsewhere).
var show_marks := true
## The landed ice cubes' simulation (null until ice lands).
var ice: IcePhysics
var _garnish_t: Array[float] = []  # seconds since each garnish was added
var _floor_y := 0.0  # local y of the interior's floor
var _clock := 0.0  # visual time, for the cubes' drift
## The head on a beer (null for drinks without one).
var foam: Foam
var _foam_level := 0.0  # local y of the calm head's top
## How far it is tipped toward the pourer (rad; + = the top leans right,
## clockwise on screen). Gameplay: levels, room and landing use it.
var tilt := 0.0
var _tilt_idle := TILT_GRACE  # seconds since the pour last wanted it tipped
var _lean := 0.0  # the arrival's lean (rad)
var _mouth := Vector2.ZERO  # local: the middle of the opening, what it tips about
var _foam_seed := 0.0  # the head's lumpy top and bubbles (visual)
## Bubbles per second rising from the floor: the drink's own (beer) plus its
## upgrades' (sparkling water). Set in reset(); visual only.
var fizz := 0.0
var _sparkling := false  # fizz from an upgrade: quick fine bubbles, some on the walls, glints
var _fizz_x := PackedFloat32Array()  # where the fizz rises from the floor (local x; visual)
var _fizz_due := 0.0
var _wall_bubbles: Array[Vector3] = []  # sparkling: x, y (local), radius; shown below the surface
var _glints: Array[Vector3] = []  # sparkling: x, y (local) where a bubble popped, age (s)

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
	_mouth = Vector2((_row_left[0] + _row_right[0] + 1) * 0.5, _y0)
	tilt = 0.0
	_tilt_idle = TILT_GRACE
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
	garnishes.clear()
	_garnish_t.clear()
	ice = null
	foam = Foam.new(def) if def != null and def.has_foam() else null
	_foam_level = _level
	_foam_seed = randf() * TAU
	_fizz_x.clear()
	_fizz_due = 0.0
	_wall_bubbles.clear()
	_glints.clear()
	fizz = GameState.fizz(def) if def != null else 0.0
	_sparkling = def != null and GameState.upgrade_fizz(def) > 0.0
	if fizz > 0.0:
		var r := _row_area.size() - 1
		while r > 0 and _row_area[r] == 0:
			r -= 1
		for i in randi_range(3, 5):
			_fizz_x.append(randf_range(_row_left[r] + 1.0, _row_right[r]))
	if _sparkling:  # tiny bubbles clinging to the inside of the walls
		for i in randi_range(WALL_BUBBLES - 2, WALL_BUBBLES + 2):
			var row := randi_range(roundi(_target_y) - _y0 - 4, _row_area.size() - 3)
			var left := randf() < 0.5
			var x := float(_row_left[row]) + 0.9 if left else float(_row_right[row]) + 0.1
			_wall_bubbles.append(Vector3(x, float(_y0 + row) + 0.5, randf_range(0.35, 0.6)))


## Adds a garnish: ice starts falling, the lime starts dropping onto the rim.
## False if it is already on this glass.
func add_garnish(g: GarnishDef) -> bool:
	if garnishes.has(g):
		return false
	garnishes.append(g)
	_garnish_t.append(0.0)
	return true


func has_garnish(id: StringName) -> bool:
	for g in garnishes:
		if g.id == id:
			return true
	return false


## True while a garnish is still falling or dropping (a serve waits for it).
func garnish_busy() -> bool:
	for i in garnishes.size():
		if _garnish_t[i] < _drop_time(garnishes[i]):
			return true
	return false


static func _drop_time(g: GarnishDef) -> float:
	return ICE_FALL_TIME if g.kind == GarnishDef.Kind.ICE else LIME_DROP_TIME


## The ice that has landed in the glass (null if none).
func _ice() -> GarnishDef:
	for i in garnishes.size():
		if garnishes[i].kind == GarnishDef.Kind.ICE and _garnish_t[i] >= ICE_FALL_TIME:
			return garnishes[i]
	return null


## Local y of the calm surface holding `liquid` with whatever ice has landed:
## the cubes stand on the floor in shallow liquid (it fills the gaps around
## them) and float once it is deep enough, a float_share of them under the
## surface. Without ice it is level_for(liquid).
func surface_level(liquid: float) -> float:
	var ice := _ice()
	if ice == null:
		return level_for(liquid) if tilt == 0.0 else _sloped_level(liquid)
	var cubes_w := ice.cube_count * ice.cube_size
	var sub := ice.float_share * ice.cube_size
	var remaining := liquid
	for r in range(_row_area.size() - 1, -1, -1):
		var a := float(_row_area[r])
		if a == 0.0:
			continue
		# The row in depths above the floor, split where the cubes start to float.
		var d0 := _floor_y - (_y0 + r + 1)
		var split := clampf(sub, d0, d0 + 1.0)
		for piece: Vector3 in [Vector3(d0, split, maxf(a - cubes_w, 0.5)), Vector3(split, d0 + 1.0, a)]:
			var room := (piece.y - piece.x) * piece.z
			if room <= 0.0:
				continue
			if remaining <= room:
				return _floor_y - (piece.x + remaining / piece.z)
			remaining -= room
	return float(_y0)


## How much area the landed ice takes up below the surface holding `liquid`.
func displaced(liquid: float) -> float:
	var ice := _ice()
	if ice == null:
		return 0.0
	var depth := _floor_y - surface_level(liquid)
	return ice.cube_count * ice.cube_size * minf(depth, ice.float_share * ice.cube_size)


## The most liquid the glass holds before it spills (less with ice in it).
func max_liquid() -> float:
	var ice := _ice()
	if ice == null:
		if tilt == 0.0:
			return capacity
		# Tipped: up to the level line through the rim corner that is highest in the world.
		var k := tan(tilt)
		return _area_below(_y0 + maxf(k * (_row_left[0] - _mouth.x), k * (_row_right[0] + 1 - _mouth.x)))
	var cubes_w := ice.cube_count * ice.cube_size
	var sub := ice.float_share * ice.cube_size
	var room := 0.0
	for r in _row_area.size():
		var a := float(_row_area[r])
		if a == 0.0:
			continue
		var d0 := _floor_y - (_y0 + r + 1)
		var split := clampf(sub, d0, d0 + 1.0)
		room += (split - d0) * maxf(a - cubes_w, 0.5) + (d0 + 1.0 - split) * a
	return room


## Local y of the world-level line at local x whose height at the mouth's x
## is `level`: flat when upright, sloped while tipped.
func calm_y(x: float, level: float) -> float:
	return level - tan(tilt) * (x - _mouth.x)


## The area inside the glass under the level line of height `level` (see
## calm_y): each pixel column's run below the line. At tilt 0 this is what
## level_for inverts.
func _area_below(level: float) -> float:
	return _area_and_width(level).x


## (area under the level line of height `level`, how many columns it crosses —
## the rate the area changes as the line moves).
func _area_and_width(level: float) -> Vector2:
	var k := tan(tilt)
	var total := 0.0
	var width := 0.0
	var y := level - k * (_x0 + 0.5 - _mouth.x)
	for c in _col_top.size():
		var top := float(_col_top[c])
		var bottom := float(_col_bottom[c])
		if bottom > top:
			if y <= top:
				total += bottom - top
			elif y < bottom:
				total += bottom - y
				width += 1.0
		y -= k
	return Vector2(total, width)


## The height (at the mouth's x) of the tipped glass's level surface holding
## `vol`: Newton steps on the (piecewise linear) area, kept inside a shrinking
## bracket, starting from the upright level.
func _sloped_level(vol: float) -> float:
	var lo := float(_y0) - 80.0  # the area under a line this high is >= vol
	var hi := _floor_y + 80.0  # ...and under this one, 0
	var level := level_for(vol)
	for i in 40:
		var aw := _area_and_width(level)
		var diff := aw.x - vol
		if absf(diff) < 1e-4:
			break
		if diff > 0.0:
			lo = level
		else:
			hi = level
		var next := level + diff / aw.y if aw.y > 0.0 else (lo + hi) * 0.5
		if next <= lo or next >= hi:
			next = (lo + hi) * 0.5
		level = next
	return level


## Tips the glass toward the pourer while `pouring` (DOWN held, beer flowing
## or in the air), riding out gaps shorter than TILT_GRACE, and brings it back
## exactly upright after. It straightens as the beer nears the line. Nothing
## for a drink that isn't poured tipped, or while it slides in.
func step_tilt(dt: float, pouring: bool) -> void:
	if def == null or def.glass_pour_tilt_deg <= 0.0:
		return
	if pouring and visible and not is_arriving():
		_tilt_idle = 0.0
	else:
		_tilt_idle += dt
	var want := 0.0
	if _tilt_idle < TILT_GRACE:
		var held := volume + (foam.beer if foam != null else 0.0)
		want = deg_to_rad(lerpf(def.glass_pour_tilt_deg, def.glass_line_tilt_deg, clampf(held / target, 0.0, 1.0)))
	tilt += (want - tilt) * (1.0 - exp(-dt / (TILT_IN if want > tilt else TILT_OUT)))
	if want == 0.0 and absf(tilt) < TILT_SNAP:
		tilt = 0.0
	_apply_frame()


func is_upright() -> bool:
	return tilt == 0.0


## The middle of the opening (local): what the glass tips about.
func pivot() -> Vector2:
	return _mouth


## Local -> this node's space: the tilt about the mouth (identity when upright).
func frame() -> Transform2D:
	return Transform2D(tilt, _mouth - _mouth.rotated(tilt))


## Where liquid moving from `prev_world` to `world` (and not in yet) is
## relative to the tipped opening: 0 still above it, 1 it crossed between the
## lips (it's in), 2 it crossed outside them (missed). The rim turns as the
## glass straightens, so it may have passed the liquid rather than the other
## way round: then it is judged where it is now.
func entry(prev_world: Vector2, world: Vector2) -> int:
	var b := to_glass(world)
	if b.y < _y0:
		return 0
	var a := to_glass(prev_world)
	var x := lerpf(a.x, b.x, (_y0 - a.y) / (b.y - a.y)) if a.y < _y0 else b.x
	return 1 if x > _row_left[0] and x < _row_right[0] + 1 else 2


## `world` kept inside the tipped glass's walls at its height (liquid runs
## down the side instead of passing through it).
func keep_inside(world: Vector2) -> Vector2:
	var q := to_glass(world)
	var r := clampi(floori(q.y) - _y0, 0, _row_area.size() - 1)
	if _row_area[r] == 0:
		return world
	var x := clampf(q.x, _row_left[r] + 0.5, _row_right[r] + 0.5)
	return world if x == q.x else from_glass(Vector2(x, q.y))


## Local y where liquid falling at local x lands: the head's top, or the
## liquid's wavy surface.
func surface_local_at(x: float) -> float:
	var c := clampi(floori(x) - _x0, 0, _wave_h.size() - 1)
	if foam != null and foam.volume >= 0.5:
		return minf(calm_y(x, _foam_level), float(_col_bottom[c]))
	return _surface_local(c)


## A world point in the glass's own (tipped) frame, and back.
func to_glass(world: Vector2) -> Vector2:
	return frame().affine_inverse() * (world - global_position)


func from_glass(local: Vector2) -> Vector2:
	return global_position + frame() * local


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
	tilt = 0.0
	_tilt_idle = TILT_GRACE
	_apply_lean(0.0)


## The served glass disappears (Main leaves a puff where it was).
func vanish() -> void:
	visible = false
	_arrive_t = -1.0
	tilt = 0.0
	_tilt_idle = TILT_GRACE
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
	_lean = angle
	_apply_frame()


## The draw layers follow the arrival's lean and the tilt about the mouth.
func _apply_frame() -> void:
	var t := Transform2D(_lean, _pivot - _pivot.rotated(_lean)) * frame()
	for layer: Node2D in [_back, _liquid, _front]:
		layer.transform = t


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
	_floor_y = -INF
	for c in cols:
		_floor_y = maxf(_floor_y, float(_col_bottom[c]))


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


## How many pixel rows the settled surface holding `vol` (and any ice) sits
## from the fill line, as drawn (waves don't count).
func rows_from_line(vol: float) -> int:
	return absi(roundi(surface_level(vol)) - roundi(_target_y))


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


## Local x span of the target marker: from the bracket's spine to the
## glass's left wall at the line — it doesn't cross the glass.
func line_span() -> Vector2:
	return Vector2(bracket_x(), outer_x_at(line_y()).x)


## The liquid as drawn (local): the wave surface across the pixel columns down
## to the floor, cut to the rounded inside. Empty when there is (next to)
## nothing — Godot can't triangulate sub-pixel slivers.
func liquid_polygon() -> PackedVector2Array:
	if def == null or volume < 0.5:
		return PackedVector2Array()
	var n := _col_top.size()
	var bottom := float(_y0 + _row_area.size()) + 1.0
	var shape := PackedVector2Array([Vector2(_x0 - 1.0, minf(calm_y(_x0 - 1.0, _level) - _wave_h[0], bottom))])
	for c in n:
		shape.append(Vector2(_x0 + c + 0.5, minf(calm_y(_x0 + c + 0.5, _level) - _wave_h[c], bottom)))
	shape.append(Vector2(_x0 + n + 1.0, minf(calm_y(_x0 + n + 1.0, _level) - _wave_h[n - 1], bottom)))
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


## The head as drawn (local): from the liquid's wavy surface up to the head's
## lumpy top, cut to the rounded inside. Empty when there is (next to) none.
func foam_polygon() -> PackedVector2Array:
	if foam == null or foam.volume < 0.5:
		return PackedVector2Array()
	var n := _col_top.size()
	var top := _foam_level
	var shape := PackedVector2Array()
	var x := float(_x0) - 1.0
	while x <= _x0 + n + 1.0:  # the lumpy top, left to right
		shape.append(Vector2(x, calm_y(x, top) - FoamArt.bump(x, _foam_seed)))
		x += 1.0
	# ...then back along the beer's wavy surface (never above the lumps).
	shape.append(Vector2(_x0 + n + 1.0, maxf(calm_y(_x0 + n + 1.0, _level) - _wave_h[n - 1], calm_y(_x0 + n + 1.0, top) + 0.8)))
	for c in range(n - 1, -1, -1):
		var cx := _x0 + c + 0.5
		shape.append(Vector2(cx, maxf(calm_y(cx, _level) - _wave_h[c], calm_y(cx, top) + 0.8)))
	shape.append(Vector2(_x0 - 1.0, maxf(calm_y(_x0 - 1.0, _level) - _wave_h[0], calm_y(_x0 - 1.0, top) + 0.8)))
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
	return minf(calm_y(_x0 + c + 0.5, _level) - _wave_h[c], float(_col_bottom[c]))


## True if the pixel at local (x, y) is inside the glass.
func _inside(x: float, y: float) -> bool:
	var c := floori(x) - _x0
	var r := floori(y)
	return c >= 0 and c < _col_top.size() and r >= _col_top[c] and r < _col_bottom[c]


## Where liquid poured at `x_world` lands (world y): the surface with its
## waves, or the top of a head.
func surface_y_world_at(x_world: float) -> float:
	if foam != null and foam.volume >= 0.5:
		return global_position.y + foam_level()
	return global_position.y + _surface_local(_col(x_world))


## Local y of the calm top of the head (the liquid's level without one).
func foam_level() -> float:
	if foam == null:
		return surface_level(volume)
	return surface_level(volume + foam.volume)


## The liquid once the head has drained to dry foam: where the beer is
## heading if nothing more is poured (volume without a head).
func settled_volume() -> float:
	if foam == null:
		return volume
	return volume + maxf(foam.beer - foam.volume * def.foam_dry_share, 0.0)


func receive(x_world: float, vol: float, speed: float) -> void:
	receive_local(x_world - global_position.x, vol, speed)


## Liquid landing at local x (the glass's own frame, tipped or not).
func receive_local(x: float, vol: float, speed: float) -> void:
	volume += foam.land(vol) if foam != null else vol
	_overflow()
	if ice != null:
		ice.push(x, vol * speed * 0.004)
	var c := clampi(floori(x) - _x0, 0, _wave_h.size() - 1)
	var kick := vol * speed * impact_gain
	_wave_v[c] -= kick
	if c > 0:
		_wave_v[c - 1] -= kick * 0.5
	if c < _wave_v.size() - 1:
		_wave_v[c + 1] -= kick * 0.5
	if randf() < vol * speed * 0.0004 * (3.0 if fizz > 0.0 else 1.0) and _bubbles.size() < _bubble_cap():
		# Spawn under the impact, but never deeper than this column's floor.
		var bc := clampi(c + randi_range(-2, 2), 0, _col_top.size() - 1)
		var top := _surface_local(bc) + 2.0
		var floor_y := float(_col_bottom[bc]) - 1.0
		if floor_y > top:
			var y := minf(top + randf_range(1.0, 2.0 + speed * 0.06), floor_y)
			_bubbles.append(Vector3(float(_x0 + bc) + 0.5, y, randf_range(8.0, 22.0)))


## How many bubbles it shows at most: more for a fizzy drink.
func _bubble_cap() -> int:
	return 120 if fizz > 0.0 else 40


## Liquid beyond max_liquid() spills over the rim and runs down the outside;
## a head on top runs over first (its drips are foam: side ±2).
func _overflow() -> void:
	var room := max_liquid()
	if foam != null:
		var lost := foam.spill(room - volume)
		spilled += lost
		if lost > 0.0 and _drips.size() < 30:
			_drips.append(Vector3(2.0 if randf() < 0.5 else -2.0, float(_y0), randf_range(20.0, 40.0)))
	if volume > room:
		spilled += volume - room
		volume = room
		if _drips.size() < 30:
			_drips.append(Vector3(1.0 if randf() < 0.5 else -1.0, float(_y0), randf_range(30.0, 60.0)))


func _step_garnishes(dt: float) -> void:
	_clock += dt
	for i in garnishes.size():
		var g := garnishes[i]
		var was := _garnish_t[i]
		_garnish_t[i] += dt
		if was < _drop_time(g) and _garnish_t[i] >= _drop_time(g):
			if g.kind == GarnishDef.Kind.ICE:
				_overflow()
				var poses := _cube_poses(g)
				if volume >= 0.5:  # a splash: the cubes knock the surface down
					for pose in poses:
						var c := clampi(floori(pose.x) - _x0, 0, _wave_v.size() - 1)
						for k in range(maxi(c - 3, 0), mini(c + 4, _wave_v.size())):
							_wave_v[k] -= 9.0
				# From here the cubes move by themselves (visual randomness only).
				ice = IcePhysics.new(g.cube_size, g.float_share)
				for pose in poses:
					ice.add(Vector2(pose.x, pose.y), Vector2(randf_range(-40.0, 40.0), ICE_ENTRY_SPEED), pose.z, randf_range(-6.0, 6.0))
				garnish_landed.emit(g, to_global(Vector2(0.0, surface_level(volume))))
			else:
				garnish_landed.emit(g, to_global(_lime_slit()))


func step(dt: float) -> void:
	_step_arrival(dt)
	_step_garnishes(dt)
	if foam != null:
		volume += foam.step(dt)
		_overflow()
	_level = surface_level(volume)
	_foam_level = foam_level()
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

	if ice != null:
		ice.step(dt, interior, _surface_at)

	if fizz > 0.0 and volume >= 0.5 and not _fizz_x.is_empty():  # beer and sparkling water fizz all the time
		_fizz_due += fizz * dt
		while _fizz_due >= 1.0:
			_fizz_due -= 1.0
			if _bubbles.size() >= _bubble_cap():
				break
			var fx := _fizz_x[randi() % _fizz_x.size()] + randf_range(-0.6, 0.6)
			var fc := clampi(floori(fx) - _x0, 0, n - 1)
			var fy := float(_col_bottom[fc]) - randf_range(0.6, 1.6)
			if fy > _surface_local(fc) + 1.0:
				var rise := randf_range(SPARKLE_RISE.x, SPARKLE_RISE.y) if _sparkling else randf_range(6.0, 14.0)
				_bubbles.append(Vector3(float(_x0 + fc) + 0.5, fy, rise))

	for i in range(_bubbles.size() - 1, -1, -1):
		var b := _bubbles[i]
		b.y -= b.z * dt
		var wobbled := b.x + sin(b.y * 0.7) * 0.15
		if tilt != 0.0:  # rise toward world-up through the tipped glass
			b.y += b.z * dt * (1.0 - cos(tilt))
			wobbled -= b.z * dt * sin(tilt)
		if _inside(wobbled, b.y):
			b.x = wobbled
		var c := clampi(floori(b.x) - _x0, 0, n - 1)
		# It pops at the surface, or at the wall where a bowl narrows toward the rim.
		if volume < 0.5 or b.y <= maxf(_surface_local(c), float(_col_top[c])) + 1.0:
			if _sparkling and foam == null and _glints.size() < 12 and b.y <= _surface_local(c) + 1.0:
				_glints.append(Vector3(b.x, _surface_local(c) - 0.5, 0.0))
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
	for i in range(_glints.size() - 1, -1, -1):
		_glints[i].z += dt
		if _glints[i].z >= GLINT_TIME:
			_glints.remove_at(i)

	_back.queue_redraw()
	_liquid.queue_redraw()
	_front.queue_redraw()


## Where each ice cube is drawn (local x, y of its centre, tilt): once landed,
## wherever the simulation has it; while falling, on its way down from above
## the view, tumbling, to where it lands — spread across the glass, on the
## floor or, in liquid, floating with a sliver above the surface.
func _cube_poses(g: GarnishDef) -> Array[Vector3]:
	var poses: Array[Vector3] = []
	if ice != null:
		for c in ice.cubes:
			poses.append(Vector3(c.pos.x, c.pos.y, c.angle))
		return poses
	var t := _garnish_t[garnishes.find(g)]
	var s := g.cube_size
	var calm := surface_level(volume) if t >= ICE_FALL_TIME else level_for(volume)
	var bottom := minf(_floor_y, calm + g.float_share * s) if volume >= 0.5 else _floor_y
	var r := clampi(floori(bottom - s * 0.5) - _y0, 0, _row_area.size() - 1)
	var left := float(_row_left[r]) + s * 0.5 + 0.6
	var right := float(_row_right[r] + 1) - s * 0.5 - 0.6
	for i in g.cube_count:
		var look: Vector4 = CUBE_LOOKS[i % CUBE_LOOKS.size()]
		var x := lerpf(left, right, float(i) / maxf(g.cube_count - 1, 1)) + look.x
		var c := clampi(floori(x) - _x0, 0, _wave_h.size() - 1)
		var y := bottom - s * 0.5
		var angle := look.y
		if volume >= 0.5 and bottom < _floor_y:  # afloat: ride the waves, drift a little
			y += minf(look.w, _floor_y - bottom) - _wave_h[c]
			var l := _wave_h[maxi(c - 2, 0)]
			var rr := _wave_h[mini(c + 2, _wave_h.size() - 1)]
			angle += (l - rr) * 0.12 + sin(_clock * 1.3 + i * 2.1) * 0.04
		if t < ICE_FALL_TIME:
			var u := t / ICE_FALL_TIME
			y = lerpf(ICE_DROP_Y - i * 9.0, y, u * u)
			x = lerpf(x + (i - 1) * 3.0, x, u)
			angle += (1.0 - u) * look.z
		poses.append(Vector3(x, y, angle))
	return poses


## The liquid surface's local y at local x for the ice simulation (INF when empty).
func _surface_at(x: float) -> float:
	if volume < 0.5:
		return INF
	return calm_y(x, _level) - _wave_h[clampi(floori(x) - _x0, 0, _wave_h.size() - 1)]


## Where the lime's slit sits on the left rim (local).
func _lime_slit() -> Vector2:
	return Vector2(outer_x_at(float(_y0)).x + 2.0, float(_y0))


## How far above the rim the lime is drawn while it drops and bounces.
func _lime_lift(t: float) -> float:
	var u := clampf(t / LIME_DROP_TIME, 0.0, 1.0)
	if u < 0.7:
		return LIME_DROP_PX * (1.0 - pow(u / 0.7, 2.0))
	return 1.8 * sin(PI * (u - 0.7) / 0.3)


## Behind the liquid: the glass body's faint frost, a soft dark outline and
## the ice (the liquid drawn over it refracts and tints what is under the surface).
func _draw_back(ci: CanvasItem) -> void:
	if def == null:
		return
	var closed := _drawn_outer.duplicate()
	closed.append(_drawn_outer[0])
	ci.draw_colored_polygon(_drawn_outer, Color(Palette.FROST, 0.07))
	ci.draw_polyline(closed, Color(Palette.INK, 0.35), 0.7, true)
	for g in garnishes:
		if g.kind == GarnishDef.Kind.ICE:
			for pose in _cube_poses(g):
				GarnishArt.draw_ice_body(ci, Vector2(pose.x, pose.y), g.cube_size, pose.z)


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
	var head := foam_polygon()
	if not head.is_empty():
		var top := _foam_level
		var depth := func(p: Vector2) -> float: return (p.y - calm_y(p.x, top)) / maxf(_level - top, 1.0)
		FoamArt.draw(ci, head, depth, def.liquid_color, _foam_seed)
	for wall in _walls:
		VesselArt.draw_hgradient(ci, wall, box.position.x, box.end.x, VesselArt.clear_glass_walls())
	for g in garnishes:
		if g.kind == GarnishDef.Kind.ICE:
			for pose in _cube_poses(g):
				GarnishArt.draw_ice_edges(ci, Vector2(pose.x, pose.y), g.cube_size, pose.z)

	# The surface: a soft sheen with a bright line on top, following the waves.
	if volume >= 0.5:
		var surface := PackedVector2Array()
		for c in _col_top.size():
			var y := calm_y(_x0 + c + 0.5, _level) - _wave_h[c]
			if y >= _col_top[c] and y < _col_bottom[c]:
				surface.append(Vector2(_x0 + c + 0.5, y))
		if surface.size() >= 2 and not head.is_empty():  # where the beer meets its head: a thin wet line
			ci.draw_polyline(surface, Color(def.liquid_highlight, 0.6), 0.45, true)
		elif surface.size() >= 2:
			ci.draw_polyline(surface, Color(def.liquid_highlight.lerp(Palette.WHITE, 0.5), 0.3), 1.8, true)
			ci.draw_polyline(surface, Color(def.liquid_highlight.lerp(Palette.WHITE, 0.75), 0.9), 0.45, true)
	var bubble := def.liquid_highlight.lerp(Palette.WHITE, 0.6)
	for b in _bubbles:
		var at := Vector2(b.x, b.y)
		ci.draw_circle(at, 0.55, Color(bubble, 0.15))
		ci.draw_arc(at, 0.55, 0.0, TAU, 10, Color(bubble, 0.5), 0.22, true)
	if volume >= 0.5:  # sparkling: bubbles on the walls under the water, glints where they pop
		for b in _wall_bubbles:
			if b.y > calm_y(b.x, _level) + 1.0:
				ci.draw_circle(Vector2(b.x, b.y), b.z, Color(bubble, 0.2))
				ci.draw_arc(Vector2(b.x, b.y), b.z, 0.0, TAU, 8, Color(bubble, 0.6), 0.2, true)
		for g in _glints:
			var k := g.z / GLINT_TIME
			ci.draw_circle(Vector2(g.x, g.y - k * 0.8), 0.3 + k * 0.35, Color(Palette.WHITE, 0.75 * (1.0 - k)))

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
		var color := Palette.FOAM if absf(d.x) > 1.5 else def.liquid_highlight
		ci.draw_circle(Vector2(walls.y + 0.4 if d.x > 0.0 else walls.x - 0.4, d.y), 0.9 if absf(d.x) > 1.5 else 0.7, color)

	# The lime on the rim; the scoring marks stay on top of it.
	for i in garnishes.size():
		if garnishes[i].kind == GarnishDef.Kind.RIM:
			GarnishArt.draw_lime(ci, _lime_slit() - Vector2(0.0, _lime_lift(_garnish_t[i])), LIME_RADIUS, LIME_ANGLE)
	if show_marks:
		_draw_band(ci)
		_draw_fill_line(ci)


## The scoring band: a light bracket (spine + end ticks pointing at the glass)
## left of the glass spanning GOOD ENOUGH (±ok_rows), with short inner ticks
## where GOOD (±good_rows) ends, underlaid dark so it reads on any background.
## PERFECT (±perfect_rows) and the target itself are the fill line's marker.
func _draw_band(ci: CanvasItem) -> void:
	var x := bracket_x()
	var ok := band_edges(GameState.stats.ok_rows)
	var good := band_edges(GameState.stats.good_rows)
	var spine := PackedVector2Array([Vector2(x + 1.6, ok.x), Vector2(x, ok.x), Vector2(x, ok.y), Vector2(x + 1.6, ok.y)])
	for look: Array in [[Color(Palette.INK, 0.6), 1.5], [Color(Palette.FROST, 0.95), 0.55]]:
		ci.draw_polyline(spine, look[0], look[1], true)
		for y in [good.x, good.y]:
			ci.draw_line(Vector2(x, y), Vector2(x + 1.1, y), look[0], look[1], true)


## The fill line: a marker a little bolder than the band's ticks — the spine
## thickened across the PERFECT rows and a tick on the target's row from the
## spine to the glass's left wall (line_span()).
func _draw_fill_line(ci: CanvasItem) -> void:
	var ly := line_y()
	var span := line_span()
	var perfect := band_edges(GameState.stats.perfect_rows)
	for look: Array in [[Color(Palette.INK, 0.6), 2.3, 1.7], [Palette.WHITE, 1.0, 0.85]]:
		ci.draw_line(Vector2(span.x, perfect.x), Vector2(span.x, perfect.y), look[0], look[1], true)
		ci.draw_line(Vector2(span.x, ly), Vector2(span.y - 0.3, ly), look[0], look[2], true)
