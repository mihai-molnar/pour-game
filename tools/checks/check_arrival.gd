extends CheckBase
## Checks the arrival curves (slice 2 spec, "Arrivals"). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=arrival


func run() -> void:
	for from: float in [-296.0, 412.0]:
		var dir := -signf(from)
		near(Arrival.offset(0.0, from), from, "starts off-screen (%d)" % from)
		near(Arrival.offset(Arrival.ARRIVE_TIME, from), 0.0, "home at ARRIVE_TIME (%d)" % from)
		near(Arrival.offset(5.0, from), 0.0, "stays home (%d)" % from)
		var furthest := -INF
		var t := 0.0
		while t <= Arrival.ARRIVE_TIME + 0.1:
			furthest = maxf(furthest, Arrival.offset(t, from) * dir)
			t += 0.001
		expect(furthest <= Arrival.OVERSHOOT_PX + 1e-6, "overshoot at most %.0f px (%d: %.3f)" % [Arrival.OVERSHOOT_PX, from, furthest])
		expect(furthest >= Arrival.OVERSHOOT_PX - 0.05, "it does overshoot (%d: %.3f)" % [from, furthest])
	for dir: float in [1.0, -1.0]:
		eq(Arrival.lean(0.0, dir), 0.0, "no lean at the start")
		eq(Arrival.lean(Arrival.ARRIVE_TIME + Arrival.WOBBLE_TIME, dir), 0.0, "upright after the wobble")
		var peak := 0.0
		var t := 0.0
		while t < Arrival.ARRIVE_TIME + Arrival.WOBBLE_TIME:
			peak = maxf(peak, absf(Arrival.lean(t, dir)))
			t += 0.001
		expect(peak <= deg_to_rad(Arrival.LEAN_DEG) + 1e-6 and peak > deg_to_rad(Arrival.LEAN_DEG) * 0.9,
			"lean peaks at about LEAN_DEG (%.2f°)" % rad_to_deg(peak))
		eq(signf(Arrival.lean(Arrival.ARRIVE_TIME * 0.5, dir)), dir, "it tips toward its travel while braking")
	expect(not Arrival.done(Arrival.ARRIVE_TIME) and Arrival.done(Arrival.ARRIVE_TIME + Arrival.WOBBLE_TIME), "done() after the wobble")
	var tumbler := PackedVector2Array([Vector2(-17, 0), Vector2(17, 0), Vector2(21, -74), Vector2(-21, -74)])
	eq(Arrival.pivot(tumbler, 0.0, 1.0), Vector2(17, 0), "a glass moving right tips over its right foot")
	eq(Arrival.pivot(tumbler, 0.0, -1.0), Vector2(-17, 0), "...moving left, its left foot")
	var bottle := PackedVector2Array([Vector2(-2, -1), Vector2(8, -1), Vector2(25, 151), Vector2(-19, 151)])
	eq(Arrival.pivot(bottle, -deg_to_rad(55.0), -1.0), Vector2(-19, 151), "a held bottle tips over its lowest corner once turned")
