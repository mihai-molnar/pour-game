extends CheckBase
## Checks the pourer: DrinkDef setup, capacity vs the glass, pour_speed_mult,
## and the automatic refill. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=pourer

const DT := 1.0 / 60.0


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var pourer: Pourer = main.pourer
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.owned_drinks[0]
	expect(pourer.def == water, "pourer is set up with water")
	var glasses := pourer.full_volume / glass.target
	expect(glasses > 2.3 and glasses < 2.7, "a full pitcher holds ~2.5 glasses at the line (got %.2f)" % glasses)
	expect(pourer.position.is_equal_approx(Vector2(256, 280) + water.pourer_offset), "pourer sits at glass + pourer_offset")
	pourer.reset()
	expect(pourer.volume == pourer.full_volume and not pourer.refilling, "reset() = full, upright, not refilling")

	# pour_speed_mult scales the tilt speed (measured before any pouring starts).
	var base_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 2.0
	var fast_tilt := _tilt_after_hold(pourer, 0.3)
	GameState.stats.pour_speed_mult = 1.0
	var ratio := fast_tilt / base_tilt
	expect(ratio > 1.8 and ratio < 2.2, "pour_speed_mult 2 doubles the tilt speed (ratio %.2f)" % ratio)

	# Running dry while tilted: DOWN is ignored (same motion held or not), it
	# returns upright, then refills over stats.refill_time.
	var held := _drain_and_refill(pourer, true)
	var free := _drain_and_refill(pourer, false)
	expect(held.tilts == free.tilts, "refilling ignores DOWN")
	expect(held.upright_at > 0.0, "it returned upright before refilling")
	expect(absf(held.refill_s - 1.0) < 0.1, "refill takes refill_time once upright (took %.2f s)" % held.refill_s)
	expect(is_equal_approx(pourer.volume, pourer.full_volume) and not pourer.refilling, "refilled to full")
	GameState.stats.refill_time = 0.5
	var quick := _drain_and_refill(pourer, false)
	GameState.stats.refill_time = 1.0
	expect(absf(quick.refill_s - 0.5) < 0.1, "refill_time is read live (took %.2f s)" % quick.refill_s)


func _tilt_after_hold(pourer: Pourer, seconds: float) -> float:
	pourer.reset()
	var t := 0.0
	while t < seconds - 1e-6:
		pourer.step(DT, true)
		t += DT
	return pourer.tilt


## Tilts the pourer to 1 rad with an almost empty pourer, then steps until the
## refill ends. Returns {tilts: Array, upright_at: float, refill_s: float}.
func _drain_and_refill(pourer: Pourer, hold: bool) -> Dictionary:
	pourer.reset()
	pourer.tilt = 1.0
	pourer.volume = pourer.full_volume * 0.005
	var tilts: Array[float] = []
	var upright_at := -1.0
	var t := 0.0
	pourer.step(DT, hold)
	t += DT
	while pourer.refilling and t < 10.0:
		tilts.append(pourer.tilt)
		if upright_at < 0.0 and pourer.tilt == 0.0 and pourer.tilt_vel == 0.0:
			upright_at = t
		pourer.step(DT, hold)
		t += DT
	return {"tilts": tilts, "upright_at": upright_at, "refill_s": t - upright_at}
