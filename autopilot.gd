class_name Autopilot
extends RefCounted
## A simple scripted player for --autoplay and tools/checks/check_round.gd: adds
## the garnishes it owns as soon as a glass lands, pours until the glass (plus
## liquid in the air, plus the ice) nears the line, releases early to allow for
## the overshoot, then serves once everything has landed. In the shop it buys
## ice, lime and wine as soon as it can afford them.

## Release DOWN when this share of the target is in the glass or the air, per
## drink id — the lower the line, the bigger the overshoot's share of the target.
var release_at := {&"water": 0.94, &"wine": 0.86}
var _released := false


## What to buy, in order, whenever it can be afforded.
const SHOPPING := [&"ice", &"lime", &"wine"]


## This tick's input: "hold" (DOWN), "serve" (Space), "keys" (garnish keys to press).
func decide(main: Main) -> Dictionary:
	var keys: Array[Key] = []
	var out := {"hold": false, "serve": false, "keys": keys}
	if not main.is_serving_phase() or main.is_swapping():
		_released = false
		return out
	for g in main.drink.garnishes:
		if GameState.owns_garnish(g) and not main.glass.has_garnish(g.id):
			keys.append(g.key)
	if main.pourer.is_busy():
		return out
	var share: float = release_at.get(main.drink.id, 0.86)
	var poured := main.glass.volume + main.stream.in_flight_volume() + main.glass.displaced(main.glass.volume)
	if not _released and poured < main.glass.target * share:
		out.hold = true
	else:
		_released = true
		if main.pourer.at_rest() and main.stream.is_empty():
			out.serve = true
	return out


## Buys what it can in SHOPPING order, through the shop (so its cards show it).
func shop(main: Main) -> void:
	for id in SHOPPING:
		for d: DrinkDef in GameState.DRINKS:
			if d.id == id:
				main.shop.buy(d)
			for g in d.garnishes:
				if g.id == id:
					main.shop.buy(g)
