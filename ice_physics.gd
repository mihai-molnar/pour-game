class_name IcePhysics
extends RefCounted
## A small rigid-body simulation of the ice cubes in a glass, for looks only:
## square cubes fall under gravity, bounce, slide with friction and tip onto a
## face against the glass's walls and floor and each other, float with a
## float_share of them under the surface and bob on its waves, and get pushed
## by liquid landing beside them. The glass steps it from tick(); nothing in
## gameplay reads it (how much the ice raises the level is Glass.surface_level).
## Coordinates are the glass's local px.

const GRAVITY := 700.0
const RESTITUTION := 0.3
## Slower impacts than this (px/s) don't bounce, so resting cubes don't jitter.
const REST_SPEED := 15.0
const FRICTION := 0.4
const SUBSTEPS := 4
## The pull toward lying flat on a face, and its damping.
const SETTLE_K := 70.0
const SETTLE_DAMP := 11.0
## The most a single landing parcel can push a cube (px/s).
const PUSH_MAX := 4.0
## Extra lift (px/s² per share of the cube) once a cube is deeper than it
## floats: real ice rises lazily; this pops it back up the way it reads.
const SINK_LIFT := 3000.0


class Cube:
	var pos: Vector2
	var vel: Vector2
	var angle: float
	var spin: float
	var touching := false


var cubes: Array[Cube] = []
var size: float
var float_share: float
var _inertia: float


func _init(cube_size: float, share: float) -> void:
	size = cube_size
	float_share = share
	_inertia = cube_size * cube_size / 6.0


func add(pos: Vector2, vel: Vector2, angle: float, spin: float) -> void:
	var c := Cube.new()
	c.pos = pos
	c.vel = vel
	c.angle = angle
	c.spin = spin
	cubes.append(c)


## Advances the cubes by `dt`. `interior` is the glass's (convex) inside, its
## top edge the open rim; `surface.call(x)` is the liquid surface's local y at
## x, INF when there is no liquid.
func step(dt: float, interior: PackedVector2Array, surface: Callable) -> void:
	var edges := _walls(interior)
	var h := dt / SUBSTEPS
	for i in SUBSTEPS:
		for c in cubes:
			_integrate(c, h, surface)
			c.touching = false
		for c in cubes:
			_collide_walls(c, edges)
		for a in cubes.size():
			for b in range(a + 1, cubes.size()):
				_collide_pair(cubes[a], cubes[b])
		for c in cubes:
			_collide_walls(c, edges)


## Liquid landing at x: cubes close by are pushed away from it and down.
func push(x: float, strength: float) -> void:
	var s := minf(strength, PUSH_MAX)
	for c in cubes:
		if absf(c.pos.x - x) < size * 1.2:
			c.vel += Vector2(signf(c.pos.x - x) * s if c.pos.x != x else s, s * 0.5)


func corners(c: Cube) -> PackedVector2Array:
	var hs := size * 0.5
	var out := PackedVector2Array()
	for k in [Vector2(-hs, -hs), Vector2(hs, -hs), Vector2(hs, hs), Vector2(-hs, hs)]:
		out.append(c.pos + k.rotated(c.angle))
	return out


func max_speed() -> float:
	var m := 0.0
	for c in cubes:
		m = maxf(m, c.vel.length())
	return m


func max_spin() -> float:
	var m := 0.0
	for c in cubes:
		m = maxf(m, absf(c.spin))
	return m


func _integrate(c: Cube, dt: float, surface: Callable) -> void:
	var reach := size * 0.5 * (absf(cos(c.angle)) + absf(sin(c.angle)))
	var sy: float = surface.call(c.pos.x)
	var sub := 0.0
	if sy < INF:
		sub = clampf((c.pos.y + reach - sy) / (2.0 * reach), 0.0, 1.0)
	var lift := GRAVITY * sub / float_share + SINK_LIFT * maxf(sub - float_share, 0.0)
	c.vel.y += (GRAVITY - lift) * dt
	# Water drag grows with speed, so a plunge stays shallow and the bobbing dies down.
	c.vel *= maxf(1.0 - (0.4 + (4.0 + 0.03 * c.vel.length()) * sub) * dt, 0.0)
	c.spin *= maxf(1.0 - (0.6 + 6.0 * sub) * dt, 0.0)
	if c.touching or sub > 0.05:  # held by the glass or the liquid: tip onto a face
		var flat := roundf(c.angle / (PI * 0.5)) * PI * 0.5
		c.spin += (-SETTLE_K * (c.angle - flat) - SETTLE_DAMP * c.spin) * dt
	c.pos += c.vel * dt
	c.angle += c.spin * dt


## The interior's edges except the rim, each [point, inward normal].
static func _walls(interior: PackedVector2Array) -> Array:
	var top := INF
	var centre := Vector2.ZERO
	for p in interior:
		top = minf(top, p.y)
		centre += p
	centre /= interior.size()
	var out := []
	var n := interior.size()
	for i in n:
		var a := interior[i]
		var b := interior[(i + 1) % n]
		if a.y - top < 0.5 and b.y - top < 0.5:
			continue  # the open rim
		var normal := (b - a).orthogonal().normalized()
		if (centre - a).dot(normal) < 0.0:
			normal = -normal
		out.append([a, normal])
	return out


func _collide_walls(c: Cube, edges: Array) -> void:
	for e in edges:
		var a: Vector2 = e[0]
		var n: Vector2 = e[1]
		for k in 4:
			var p: Vector2 = corners(c)[k]
			var depth := (p - a).dot(n)
			if depth >= 0.0:
				continue
			var r := p - c.pos
			c.pos -= n * depth
			c.touching = true
			var v := c.vel + Vector2(-c.spin * r.y, c.spin * r.x)
			var vn := v.dot(n)
			if vn >= 0.0:
				continue
			var t0 := Vector2(-n.y, n.x)
			if vn > -REST_SPEED:
				# Resting contact: stop it at the centre, no spin (two corners on
				# the floor would otherwise take turns spinning it), with friction.
				c.vel -= n * c.vel.dot(n)
				var vt := c.vel.dot(t0)
				c.vel -= t0 * clampf(vt, -FRICTION * -vn, FRICTION * -vn)
				continue
			var e_n := RESTITUTION
			var rn := r.cross(n)
			var jn := -(1.0 + e_n) * vn / (1.0 + rn * rn / _inertia)
			var t := t0
			var rt := r.cross(t)
			var jt := clampf(-v.dot(t) / (1.0 + rt * rt / _inertia), -FRICTION * jn, FRICTION * jn)
			var j := n * jn + t * jt
			c.vel += j
			c.spin += r.cross(j) / _inertia


## Two cubes overlapping: pushed apart along the axis of least overlap, with a
## bounce if they hit hard.
func _collide_pair(a: Cube, b: Cube) -> void:
	var ca := corners(a)
	var cb := corners(b)
	var best := INF
	var axis := Vector2.ZERO
	for ax: Vector2 in [Vector2.RIGHT.rotated(a.angle), Vector2.DOWN.rotated(a.angle), Vector2.RIGHT.rotated(b.angle), Vector2.DOWN.rotated(b.angle)]:
		var pa := _project(ca, ax)
		var pb := _project(cb, ax)
		var overlap := minf(pa.y, pb.y) - maxf(pa.x, pb.x)
		if overlap <= 0.0:
			return
		if overlap < best:
			best = overlap
			axis = ax
	if (b.pos - a.pos).dot(axis) < 0.0:
		axis = -axis
	a.pos -= axis * best * 0.5
	b.pos += axis * best * 0.5
	a.touching = true
	b.touching = true
	var rel := (b.vel - a.vel).dot(axis)
	if rel < 0.0:
		var e := RESTITUTION if rel < -REST_SPEED else 0.0
		var j := -(1.0 + e) * rel * 0.5
		a.vel -= axis * j
		b.vel += axis * j


static func _project(pts: PackedVector2Array, axis: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in pts:
		var d := p.dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)
