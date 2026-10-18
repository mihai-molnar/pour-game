extends CheckBase
## Simulates pours (beer's in its tipped glass) and fails if any bubble is
## ever outside the glass interior.


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var glass: Glass = main.glass
	var dt := 1.0 / 60.0
	var checked := 0
	var bad := 0
	var worst := ""
	seed(2)  # bubbles are visual randomness; a fixed seed makes a failure repeatable
	for d: DrinkDef in [GameState.WATER, GameState.WINE, GameState.BEER]:
		glass.setup(d)
		glass.place(Main.GLASS_POS)
		main.pourer.setup(d)
		main.pourer.place(Main.GLASS_POS + d.pourer_offset)
		for hold_s in [1.2, 2.0, 2.6, 3.4]:
			main.stream.clear()
			glass.reset()
			main.pourer.reset()
			var t := 0.0
			while t < hold_s + 2.0:
				main._step_sim(dt, t < hold_s)
				for b in glass._bubbles:
					checked += 1
					var px := Vector2(floorf(b.x) + 0.5, floorf(b.y) + 0.5)
					if not Geometry2D.is_point_in_polygon(px, glass.interior):
						bad += 1
						if worst == "":
							worst = "%s hold %.1fs t=%.2fs bubble at (%.1f, %.1f)" % [d.id, hold_s, t, b.x, b.y]
				t += dt
	print("bubbles checked: %d, outside the glass: %d" % [checked, bad])
	expect(checked > 0, "some bubbles were spawned")
	expect(bad == 0, "no bubble outside the glass (first offender: %s)" % worst)
