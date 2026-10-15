extends CheckBase
## Simulates pours and fails if any bubble is ever outside the glass interior.


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var glass: Glass = main.glass
	var dt := 1.0 / 60.0
	var checked := 0
	var bad := 0
	var worst := ""
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
						worst = "hold %.1fs t=%.2fs bubble at (%.1f, %.1f)" % [hold_s, t, b.x, b.y]
			t += dt
	print("bubbles checked: %d, outside the glass: %d" % [checked, bad])
	expect(checked > 0, "some bubbles were spawned")
	expect(bad == 0, "no bubble outside the glass (first offender: %s)" % worst)
