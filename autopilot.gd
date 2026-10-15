class_name Autopilot
extends RefCounted
## A simple scripted player for --autoplay and tools/checks/check_round.gd: pours
## until the glass (plus liquid in the air) nears the line, releases early to
## allow for the overshoot, then serves once everything has landed.

## Release DOWN when this share of the target is in the glass or the air.
var release_at := 0.86
var _released := false


func decide(main: Main) -> Dictionary:
	var out := {"hold": false, "serve": false}
	if not main.is_serving_phase() or main.is_swapping():
		_released = false
		return out
	if main.pourer.refilling:
		return out
	var poured := main.glass.volume + main.stream.in_flight_volume()
	if not _released and poured < main.glass.target * release_at:
		out.hold = true
	else:
		_released = true
		if main.pourer.at_rest() and main.stream.is_empty():
			out.serve = true
	return out
