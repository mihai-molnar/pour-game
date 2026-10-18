class_name Foam
extends RefCounted
## A beer's head (docs/superpowers/specs/2026-10-18-beer-design.md): foam is
## mostly gas holding a little beer. Beer landing fast churns part of itself
## into foam (land()); fresh foam is wet and drains toward dry foam within a
## second or two, so the beer under it creeps up while the head barely shrinks,
## and the head itself collapses slowly (step()). Foam over the rim runs over
## first (spill()). Volumes are areas in px², like the glass's; the glass owns
## one Foam per serve and adds what it releases to its liquid. Deterministic:
## gameplay, stepped from main.tick().

## A finger of head, in world px (for tuning tables and checks).
const FINGER := 10.0
## How long (s) the landing rate is smoothed over: "how fast you pour".
const RATE_TIME := 0.2

## The room the head takes up (px²).
var volume := 0.0
## The beer held in it (px²).
var beer := 0.0
## How fast beer has been landing lately (px²/s).
var rate := 0.0

var _def: DrinkDef
var _landed := 0.0  # landed since the last step


func _init(d: DrinkDef) -> void:
	_def = d


## The share of landing beer that turns into foam when it lands at `r` px²/s:
## foam_share_slow at a trickle, foam_share_fast at full speed, linear between.
func share(r: float) -> float:
	var k := clampf((r - _def.foam_rate_slow) / (_def.foam_rate_fast - _def.foam_rate_slow), 0.0, 1.0)
	return lerpf(_def.foam_share_slow, _def.foam_share_fast, k)


## Lands `vol` of beer: a share of it (by the landing rate so far) becomes wet
## foam, the rest is returned for the liquid.
func land(vol: float) -> float:
	_landed += vol
	var foamed := vol * share(rate)
	beer += foamed
	volume += foamed / _def.foam_wet_share
	return vol - foamed


## One tick: the landing rate catches up, wet foam drains toward dry, the head
## collapses a little. Returns the beer released into the liquid.
func step(dt: float) -> float:
	rate += (_landed / dt - rate) * (1.0 - exp(-dt / RATE_TIME))
	_landed = 0.0
	var out := 0.0
	var wet := beer - volume * _def.foam_dry_share
	if wet > 0.0:
		var d := wet * (1.0 - exp(-dt / _def.foam_drain_time))
		beer -= d
		out += d
	if volume > 0.0:
		var c := volume * (1.0 - exp(-dt / _def.foam_collapse_time))
		var held := beer * c / volume
		volume -= c
		beer -= held
		out += held
	if volume < 0.05:  # the last wisp
		out += beer
		volume = 0.0
		beer = 0.0
	return out


## Foam beyond `room` (the space left above the liquid, px²; may be <= 0) runs
## over the rim. Returns the beer it held.
func spill(room: float) -> float:
	if volume <= room or volume <= 0.0:
		return 0.0
	var over := volume - maxf(room, 0.0)
	var lost := beer * over / volume
	volume -= over
	beer -= lost
	if volume <= 0.0:
		volume = 0.0
		beer = 0.0
	return lost
