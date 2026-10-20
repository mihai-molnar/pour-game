class_name Autopilot
extends RefCounted
## A simple scripted player for --autoplay and tools/checks/check_round.gd: adds
## the garnishes it owns as soon as a glass lands, pours until the glass (plus
## liquid in the air, plus the ice) nears the line, releases early to allow for
## the overshoot, then serves once everything has landed. Beer it feathers:
## DOWN on while the flow is under BEER_FLOW, off above it, until the beer the
## glass will hold once its head drains nears the line; it serves once the
## beer has crept up to the line (or the head has drained). In the shop it buys
## ice, lime, wine and beer, then sparkling, premium, vintage and the refill
## speeds, as soon as it can afford them (SHOPPING).

## Release DOWN when this share of the target is in the glass or the air, per
## drink id — the lower the line, the bigger the overshoot's share of the target.
var release_at := {&"water": 0.94, &"wine": 0.86, &"beer": 1.02}
var _released := false

## The flow (px²/s) it feathers a beer pour at.
const BEER_FLOW := 700.0
## It serves a beer once the beer is this close (px², about a row) under the
## line, or once less than this is still to drain from the head.
const BEER_SETTLE := 40.0
## About this share of what is over the bottle's lip still pours out once DOWN
## is let go (the rest runs back as the bottle eases back).
const LIP_SHARE := 1.0


## What to buy, in order, whenever it can be afforded.
const SHOPPING := [&"ice", &"lime", &"wine", &"beer", &"sparkling", &"premium", &"vintage", &"water_refill", &"wine_refill"]


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
	if main.drink.has_foam():
		return _decide_beer(main, out)
	var share: float = release_at.get(main.drink.id, 0.86)
	var poured := main.glass.volume + main.stream.in_flight_volume() + main.glass.displaced(main.glass.volume)
	if not _released and poured < main.glass.target * share:
		out.hold = true
	else:
		_released = true
		if main.pourer.at_rest() and main.stream.is_empty():
			out.serve = true
	return out


func _decide_beer(main: Main, out: Dictionary) -> Dictionary:
	var glass := main.glass
	if not _released and beer_coming(main.glass, main.stream, main.pourer) < glass.target * release_at[&"beer"]:
		out.hold = feather(main.pourer)
	else:
		_released = true
		var crept := glass.volume >= glass.target - BEER_SETTLE or glass.settled_volume() - glass.volume < BEER_SETTLE
		if not main.pourer.is_pouring() and main.stream.is_empty() and glass.is_upright() and crept:
			out.serve = true
	return out


## The beer the glass will hold once everything poured has landed and its
## head has drained: what is settling in it, what is in the air, and what of
## what is over the bottle's lip still pours out after DOWN is let go.
static func beer_coming(glass: Glass, stream: Stream, pourer: Pourer) -> float:
	return glass.settled_volume() + stream.in_flight_volume() + pourer.excess * LIP_SHARE


## Feathering DOWN: on while the flow is under BEER_FLOW (and before it pours), off above it.
static func feather(pourer: Pourer, aim := BEER_FLOW) -> bool:
	return pourer.flow < aim


## Buys what it can in SHOPPING order, through the shop (so its menu shows it).
func shop(main: Main) -> void:
	for id in SHOPPING:
		main.shop.buy(GameState.item_by_id(id))
