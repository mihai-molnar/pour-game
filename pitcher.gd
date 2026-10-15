class_name Pitcher
extends Node2D
## A glass water pitcher that tilts around its spout lip (this node's origin).
##
## Pouring is pure geometry: the liquid surface stays (almost) level in the
## world while the pitcher rotates, and whatever volume no longer fits below
## the line through the spout lip leaves through the spout. Volumes are areas
## in px², the same unit the glass uses.

@export_group("Tilt")
## Tilt speed (°/s) while DOWN is held and the liquid hasn't reached the lip yet.
@export var tilt_speed_deg := 45.0
## Tilt speed (°/s) while DOWN is held and it is pouring (careful hands).
@export var pour_tilt_speed_deg := 15.0
## How quickly it reaches that speed (1/s). Lower = heavier pitcher.
@export var tilt_response := 6.0
## Constant pull back toward upright once DOWN is released (rad/s²).
## Lower = more momentum: it keeps tilting further after release.
@export var return_force := 3.0
## Velocity damping while returning (1/s); caps the return speed at return_force / return_damp.
@export var return_damp := 2.0
@export_range(30.0, 175.0) var max_tilt_deg := 140.0
## Fraction of speed kept when the pitcher clunks back onto the table.
@export var rest_bounce := 0.2

@export_group("Pour")
## Share of the over-the-lip excess that leaves per second.
@export var pour_rate := 7.0
## Hard cap on flow (px²/s).
@export var max_flow := 3000.0
@export var stream_speed_min := 15.0
## Exit speed grows with sqrt(excess), like a weir.
@export var stream_speed_k := 5.0
@export_range(0.1, 1.0) var start_fill := 0.85
@export var refill_on_serve := true

@export_group("Slosh")
@export var slosh_spring := 60.0
@export var slosh_damp := 4.0
## How strongly tilt acceleration sloshes the surface (braking surges liquid toward the spout).
@export var slosh_gain := 0.04
@export var slosh_max := 0.25

## Inside of the pitcher, local px, origin = spout lip, y down.
var interior := PackedVector2Array([
	Vector2(0, 0), Vector2(58, 0), Vector2(58, 82), Vector2(13, 82), Vector2(13, 13),
])
var outer := PackedVector2Array([
	Vector2(-3, -1), Vector2(60, -1), Vector2(60, 87), Vector2(11, 87), Vector2(11, 15),
])
var handle := PackedVector2Array([
	Vector2(60, 10), Vector2(68, 10), Vector2(73, 15), Vector2(73, 58), Vector2(68, 63), Vector2(60, 63),
])
const SPOUT_DIR := Vector2(-1.0, -0.25)
## Excess below this is treated as "not pouring" so the stream can end cleanly.
const MIN_EXCESS := 0.5

var tilt := 0.0
var tilt_vel := 0.0
var slosh := 0.0
var slosh_vel := 0.0
var volume := 0.0
var capacity := 0.0
var flow := 0.0
var excess := 0.0
var exit_speed := 0.0

var _surf_angle := 0.0
var _surf_point := Vector2.ZERO

@onready var _liquid: DrawLayer = $Liquid
@onready var _front: DrawLayer = $Front


func _ready() -> void:
	capacity = _poly_area(interior)
	_liquid.draw_func = _draw_liquid
	_front.draw_func = _draw_front
	var mat := _liquid.material as ShaderMaterial
	mat.set_shader_parameter("center_x", 35.5)
	mat.set_shader_parameter("half_width", 22.5)
	mat.set_shader_parameter("surface_y", 0.0)
	mat.set_shader_parameter("highlight_x", 17.0)
	reset()


func reset() -> void:
	tilt = 0.0
	tilt_vel = 0.0
	slosh = 0.0
	slosh_vel = 0.0
	volume = capacity * start_fill
	flow = 0.0
	excess = 0.0
	_update_surface()


func refill() -> void:
	create_tween().tween_property(self, "volume", capacity * start_fill, 0.4)


## Advances one physics tick. Returns the volume that left the spout this tick.
func step(dt: float, hold: bool) -> float:
	var prev_vel := tilt_vel
	var acc: float
	if hold:
		var speed := pour_tilt_speed_deg if excess > 0.0 else tilt_speed_deg
		acc = (deg_to_rad(speed) - tilt_vel) * tilt_response
	else:
		acc = -return_force - return_damp * tilt_vel
	tilt_vel += acc * dt
	tilt += tilt_vel * dt
	var max_tilt := deg_to_rad(max_tilt_deg)
	if tilt < 0.0:
		tilt = 0.0
		# Clunk back onto the table; small speeds just settle.
		tilt_vel = -tilt_vel * rest_bounce if tilt_vel < -0.2 else 0.0
	elif tilt > max_tilt:
		tilt = max_tilt
		tilt_vel = minf(tilt_vel, 0.0)
	rotation = -tilt

	var tilt_acc := (tilt_vel - prev_vel) / dt
	slosh_vel += (-slosh_spring * slosh - slosh_damp * slosh_vel - slosh_gain * tilt_acc) * dt
	slosh = clampf(slosh + slosh_vel * dt, -slosh_max, slosh_max)

	excess = volume - _area_below(Vector2.ZERO, _local_surface_angle())
	var out := 0.0
	if excess > MIN_EXCESS:
		exit_speed = stream_speed_min + stream_speed_k * sqrt(excess)
		out = minf(excess * (1.0 - exp(-pour_rate * dt)), max_flow * dt)
		volume -= out
	flow = out / dt
	_update_surface()
	return out


func exit_velocity() -> Vector2:
	return SPOUT_DIR.normalized().rotated(rotation) * exit_speed


func is_pouring() -> bool:
	return flow > 0.0


func at_rest() -> bool:
	return tilt <= 0.0001 and absf(tilt_vel) < 0.01 and not is_pouring()


## Surface angle in local space: world-level (rotated back by the tilt) plus slosh.
func _local_surface_angle() -> float:
	return tilt + slosh


func _update_surface() -> void:
	_surf_angle = _local_surface_angle()
	var shown := minf(volume, _area_below(Vector2.ZERO, _surf_angle))
	var u := Vector2.from_angle(_surf_angle)
	var n := Vector2(-u.y, u.x)
	# Binary search how far below the lip the surface sits for this volume.
	var lo := 0.0
	var hi := 160.0
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
		total += _poly_area(poly)
	return total


static func _poly_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _draw_liquid(ci: CanvasItem) -> void:
	if volume < 1.0:
		return
	for poly in _liquid_shape(_surf_point, _surf_angle):
		ci.draw_colored_polygon(poly, Color.WHITE)


func _draw_front(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(outer, Color(Palette.FROST, 0.10))
	ci.draw_rect(Rect2(11, 82, 49, 5), Color(Palette.FROST, 0.35))
	# Liquid surface sparkle.
	if volume >= 1.0:
		var u := Vector2.from_angle(_surf_angle)
		var line := PackedVector2Array([_surf_point - u * 200.0, _surf_point + u * 200.0])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, interior):
			ci.draw_polyline(seg, Color(Palette.WHITE, 0.55))
	# Walls.
	ci.draw_polyline(PackedVector2Array([outer[0], outer[4], outer[3], outer[2], outer[1]]), Palette.FROST)
	ci.draw_polyline(PackedVector2Array([interior[0], interior[4], interior[3], interior[2], interior[1]]), Color(Palette.MIST, 0.6))
	ci.draw_line(outer[0], outer[1], Color(Palette.FROST, 0.45))
	# Handle.
	ci.draw_polyline(handle, Color(Palette.FROST, 0.9), 3.0)
	ci.draw_polyline(handle, Color(Palette.MIST, 0.8))
	# Highlights.
	ci.draw_line(Vector2(17, 8), Vector2(17, 74), Color(Palette.WHITE, 0.5))
	ci.draw_line(Vector2(54, 10), Vector2(54, 30), Color(Palette.WHITE, 0.3))
	ci.draw_rect(Rect2(-3, -1, 1, 1), Palette.WHITE)
