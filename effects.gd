class_name Effects
extends Node2D
## Short-lived soft effects that outlive what caused them: the puff a
## vanishing glass or pourer leaves, dust where an arrival lands on the
## counter, a popped cork or crown cap and its spray, the splash of ice landing. Visual only — it uses randf and never
## feeds back into gameplay. Main steps it from tick() so it keeps pace with
## the simulation.

const GRAVITY := 700.0
## The oldest bits are dropped beyond this many.
const MAX_BITS := 120
## Bits fade out over their last this-many seconds.
const FADE := 0.15


## PUFF: a soft cloud blob; DOT: a small round drop or speck; CORK: the flying
## cork; CAP: a beer bottle's crown cap.
enum Kind { PUFF, DOT, CORK, CAP }


class Bit:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var size: float  # radius (px)
	var color: Color
	var gravity: float
	var kind: Kind


var _bits: Array[Bit] = []


## A vanishing glass or pourer: 4-6 soft light blobs bursting out from `at`.
func puff(at: Vector2) -> void:
	for i in randi_range(4, 6):
		var dir := Vector2.from_angle(randf() * TAU)
		_add(at + dir * 4.0, dir * randf_range(30.0, 60.0), randf_range(0.25, 0.4), randf_range(3.0, 5.0), Palette.WHITE, 0.0, Kind.PUFF)


## Dust where an arrival lands on the counter: 3 sand specks kicked sideways.
func dust(at: Vector2) -> void:
	for i in 3:
		_add(at + Vector2(randf_range(-3.0, 3.0), -1.0), Vector2(randf_range(-40.0, 40.0), -randf_range(10.0, 30.0)),
			0.3, 0.5, Palette.SAND, 200.0, Kind.DOT)


## Ice landing in liquid: 3-6 drops of `color` thrown up and out from `at`.
func splash(at: Vector2, color: Color) -> void:
	for i in randi_range(3, 6):
		var v := Vector2(randf_range(-45.0, 45.0), -randf_range(50.0, 95.0))
		_add(at + Vector2(randf_range(-6.0, 6.0), 0.0), v, 0.5, randf_range(0.4, 0.7), color, GRAVITY, Kind.DOT)


## The width (px) of a popped cork — the same cork the bottle's mouth was showing.
const CORK_W := 6.6


## A popped cork flying off along `velocity`, plus a little spray of `spray` drops.
func cork(at: Vector2, velocity: Vector2, spray: Color) -> void:
	_add(at, velocity, 2.0, CORK_W, Palette.WHITE, GRAVITY, Kind.CORK)
	for i in 4:
		_add(at, velocity.rotated(randf_range(-0.6, 0.6)) * randf_range(0.3, 0.6), 0.4, 0.5, spray, GRAVITY, Kind.DOT)


## The width (px) of a popped crown cap — Pourer.cap_rect()'s on the beer bottle.
const CAP_W := 13.0


## A crown cap flipping off along `velocity`, plus a little foamy spray.
func cap(at: Vector2, velocity: Vector2, _spray: Color) -> void:
	_add(at, velocity, 2.0, CAP_W, Palette.WHITE, GRAVITY, Kind.CAP)
	for i in 5:
		_add(at, velocity.rotated(randf_range(-0.7, 0.7)) * randf_range(0.25, 0.55), 0.45, 0.55, Palette.FOAM, GRAVITY, Kind.DOT)


## Drops every bit (a new round starts clean).
func clear() -> void:
	_bits.clear()
	queue_redraw()


func count() -> int:
	return _bits.size()


func step(dt: float) -> void:
	var alive: Array[Bit] = []
	for b in _bits:
		b.life -= dt
		b.vel.y += b.gravity * dt
		b.pos += b.vel * dt
		if b.life > 0.0 and b.pos.y < 400.0:
			alive.append(b)
	_bits = alive
	queue_redraw()


func _add(pos: Vector2, vel: Vector2, life: float, size: float, color: Color, gravity: float, kind: Kind) -> void:
	var b := Bit.new()
	b.pos = pos
	b.vel = vel
	b.life = life
	b.size = size
	b.color = color
	b.gravity = gravity
	b.kind = kind
	_bits.append(b)
	if _bits.size() > MAX_BITS:
		_bits.pop_front()


func _draw() -> void:
	for b in _bits:
		var c := b.color
		c.a *= clampf(b.life / FADE, 0.0, 1.0)
		match b.kind:
			Kind.PUFF:
				VesselArt.draw_soft_ellipse(self, b.pos, Vector2.ONE * b.size, Color(c, c.a * 0.7))
			Kind.DOT:
				draw_circle(b.pos, b.size, c)
			Kind.CORK:  # the whole cork, tumbling as it flies
				draw_set_transform(b.pos, b.life * 9.0)
				VesselArt.draw_cork(self, Rect2(-b.size * 0.5, -b.size * 0.9, b.size, b.size * 1.8), c.a)
				draw_set_transform(Vector2.ZERO)
			Kind.CAP:  # the cap, flipping as it flies
				draw_set_transform(b.pos, b.life * 11.0)
				VesselArt.draw_crown_cap(self, Rect2(-b.size * 0.5, -1.7, b.size, 3.4), c.a)
				draw_set_transform(Vector2.ZERO)
