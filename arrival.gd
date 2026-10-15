class_name Arrival
## Slide-in motion for a glass or pourer arriving from off-screen: pure
## functions of the time since the arrival started (no state, no tweens), so
## vessels step them from their own step() inside main.tick() and stay
## deterministic. See docs/superpowers/specs/2026-10-15-second-drink-design.md
## ("Arrivals").

## Seconds from off-screen to home.
const ARRIVE_TIME := 0.3
## Share of ARRIVE_TIME spent braking into the overshoot; the rest settles back.
const BRAKE_SHARE := 0.7
## How far past home it overshoots (px).
const OVERSHOOT_PX := 3.0
## Peak lean (°) as it brakes.
const LEAN_DEG := 6.0
## The wobble may run this long after the slide ends.
const WOBBLE_TIME := 0.15
## Half-swings in the wobble (2.5 = forward, back, forward, settle).
const WOBBLE_SWINGS := 2.5


## Offset from home along x at time `t`, starting at `from` (e.g. -296 for a
## glass coming from the left): eases out to OVERSHOOT_PX past home, then
## settles to exactly 0 at ARRIVE_TIME.
static func offset(t: float, from: float) -> float:
	if t >= ARRIVE_TIME:
		return 0.0
	var past := -signf(from) * OVERSHOOT_PX
	var brake := ARRIVE_TIME * BRAKE_SHARE
	if t < brake:
		var s := maxf(t, 0.0) / brake
		return lerpf(from, past, 1.0 - pow(1.0 - s, 3.0))
	var u := (t - brake) / (ARRIVE_TIME - brake)
	return past * (1.0 - u * u * (3.0 - 2.0 * u))


## Lean (radians) at time `t` for travel direction `dir` (+1 = moving right):
## tips toward the travel direction while braking, then wobbles back upright;
## exactly 0 from ARRIVE_TIME + WOBBLE_TIME on.
static func lean(t: float, dir: float) -> float:
	if t <= 0.0:
		return 0.0
	var peak := deg_to_rad(LEAN_DEG) * dir
	var brake := ARRIVE_TIME * BRAKE_SHARE
	if t < brake:
		return peak * sin(t / brake * PI * 0.5)
	var u := (t - brake) / (ARRIVE_TIME + WOBBLE_TIME - brake)
	if u >= 1.0:
		return 0.0
	var fade := 1.0 - u
	return peak * cos(u * WOBBLE_SWINGS * PI) * fade * fade


## True once the slide and its wobble are over.
static func done(t: float) -> bool:
	return t >= ARRIVE_TIME + WOBBLE_TIME


## The point a vessel tips over: its lowest point once turned by
## `frame_rotation` (its rest rotation, radians), ties broken toward the travel
## direction `dir`. Returned in the vessel's own unrotated coordinates.
static func pivot(points: PackedVector2Array, frame_rotation: float, dir: float) -> Vector2:
	var best := points[0]
	var best_key := Vector2(-INF, -INF)
	for p in points:
		var w := p.rotated(frame_rotation)
		var key := Vector2(snappedf(w.y, 0.01), w.x * dir)
		if key > best_key:
			best_key = key
			best = p
	return best
