extends CheckBase
## Checks the beer head's model (Foam): how much foam a landing makes,
## conservation of beer through landing, draining, collapsing and spilling,
## quick draining against slow collapsing, and running over. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=foam

const DT := 1.0 / 60.0


func run() -> void:
	var beer: DrinkDef = GameState.BEER
	expect(beer.has_foam() and not GameState.WATER.has_foam() and not GameState.WINE.has_foam(), "only beer foams")
	var f := Foam.new(beer)
	expect(f.share(50.0) == beer.foam_share_slow and f.share(5000.0) == beer.foam_share_fast, "trickle and full-speed shares")
	expect(f.share(400.0) > f.share(200.0), "faster landing makes more foam")

	# Conservation through landing, draining, collapsing and spilling.
	var landed := 0.0
	var liquid := 0.0
	var spilled := 0.0
	for i in 300:
		var v := 8.0 if i < 200 else 0.0  # 480 px²/s for 3.3 s, then nothing
		landed += v
		liquid += f.land(v)
		liquid += f.step(DT)
		if i == 150:
			spilled += f.spill(f.volume * 0.5)
	near(liquid + f.beer + spilled, landed, "landed = liquid + foam's beer + spilled", 0.01)
	expect(f.rate < 50.0, "the landing rate falls once nothing lands (%.0f px²/s)" % f.rate)

	# Draining is quick, collapsing is slow.
	var g := Foam.new(beer)
	g.volume = 800.0
	g.beer = 800.0 * beer.foam_wet_share
	var out := 0.0
	for i in 180:
		out += g.step(DT)
	expect(g.beer / g.volume < beer.foam_dry_share + 0.02, "after 3 s the head is nearly dry (%.3f)" % (g.beer / g.volume))
	expect(g.volume > 800.0 * 0.9, "...but still about as tall (%.0f px²)" % g.volume)
	near(out, 800.0 * beer.foam_wet_share - g.beer, "the drained beer was released", 0.01)

	var h := Foam.new(beer)
	h.volume = 300.0
	h.beer = 30.0
	expect(h.spill(400.0) == 0.0 and h.volume == 300.0, "room to spare: nothing runs over")
	near(h.spill(100.0), 20.0, "200 of 300 px² runs over, with two thirds of its beer", 0.001)
	near(h.volume, 100.0, "...leaving 100 px² of head", 0.001)
	near(h.spill(-5.0), 10.0, "no room at all: the whole head runs over", 0.001)
	expect(h.volume == 0.0 and h.beer == 0.0, "...and nothing is left")
