class_name Autopilot
extends RefCounted
## A simple scripted player for --autoplay and tools/checks/check_round.gd: pours
## until the glass (plus liquid in the air) nears the line, releases early to
## allow for the overshoot, then serves once everything has landed.

## Release DOWN when this share of the target is in the glass or the air, per
## drink id — the lower the line, the bigger the overshoot's share of the target.
var release_at := {&"water": 0.86, &"wine": 0.75}
var _released := false


func decide(main: Main) -> Dictionary:
	var out := {"hold": false, "serve": false}
	if not main.is_serving_phase() or main.is_swapping():
		_released = false
		return out
	if main.pourer.is_busy():
		return out
	var share: float = release_at.get(main.drink.id, 0.86)
	var poured := main.glass.volume + main.stream.in_flight_volume()
	if not _released and poured < main.glass.target * share:
		out.hold = true
	else:
		_released = true
		if main.pourer.at_rest() and main.stream.is_empty():
			out.serve = true
	return out
