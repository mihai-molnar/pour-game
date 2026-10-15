class_name Effects
extends Node2D
## Short-lived pixel effects that outlive what caused them: the puff a
## vanishing glass or pourer leaves, dust where an arrival lands on the
## counter, a popped cork and its spray. Visual only — it uses randf and never
## feeds back into gameplay. Main steps it from tick() so it keeps pace with
## the simulation.

const GRAVITY := 700.0
## The oldest bits are dropped beyond this many.
const MAX_BITS := 120
## Bits fade out over their last this-many seconds.
const FADE := 0.15


class Bit:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var size: Vector2
	var color: Color
	var gravity: float


var _bits: Array[Bit] = []


## A vanishing glass or pourer: 4-6 light pixels bursting out from `at`.
func puff(at: Vector2) -> void:
	for i in randi_range(4, 6):
		var dir := Vector2.from_angle(randf() * TAU)
		_add(at + dir * 4.0, dir * randf_range(30.0, 60.0), randf_range(0.25, 0.4), Vector2.ONE, Palette.WHITE, 0.0)


## Dust where an arrival lands on the counter: 3 sand pixels kicked sideways.
func dust(at: Vector2) -> void:
	for i in 3:
		_add(at + Vector2(randf_range(-3.0, 3.0), -1.0), Vector2(randf_range(-40.0, 40.0), -randf_range(10.0, 30.0)),
			0.3, Vector2.ONE, Palette.SAND, 200.0)


## A popped cork flying off along `velocity`, plus a little spray of `spray` drops.
func cork(at: Vector2, velocity: Vector2, spray: Color) -> void:
	_add(at, velocity, 2.0, Vector2(4, 3), Palette.BROWN, GRAVITY)
	for i in 4:
		_add(at, velocity.rotated(randf_range(-0.6, 0.6)) * randf_range(0.3, 0.6), 0.4, Vector2.ONE, spray, GRAVITY)


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


func _add(pos: Vector2, vel: Vector2, life: float, size: Vector2, color: Color, gravity: float) -> void:
	var b := Bit.new()
	b.pos = pos
	b.vel = vel
	b.life = life
	b.size = size
	b.color = color
	b.gravity = gravity
	_bits.append(b)
	if _bits.size() > MAX_BITS:
		_bits.pop_front()


func _draw() -> void:
	for b in _bits:
		var c := b.color
		c.a *= clampf(b.life / FADE, 0.0, 1.0)
		draw_rect(Rect2(b.pos.floor(), b.size), c)
