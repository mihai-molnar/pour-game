extends CheckBase
## Simulates pours (beer's in its tipped glass, sparkling water's with and
## without ice) and fails if any bubble is ever outside the glass interior,
## or outside the water in a sparkling pitcher.


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var glass: Glass = main.glass
	var pourer: Pourer = main.pourer
	var dt := 1.0 / 60.0
	var checked := 0
	var bad := 0
	var worst := ""
	var pitcher_checked := 0
	var pitcher_bad := 0
	var pitcher_worst := ""
	seed(2)  # bubbles are visual randomness; a fixed seed makes a failure repeatable
	var ice: GarnishDef = GameState.WATER.garnishes[0]
	# [drink, sparkling, iced]
	for case: Array in [[GameState.WATER, false, false], [GameState.WINE, false, false], [GameState.BEER, false, false],
			[GameState.WATER, true, false], [GameState.WATER, true, true]]:
		var d: DrinkDef = case[0]
		GameState.owned_upgrades.clear()
		if case[1]:
			GameState.owned_upgrades.append(&"sparkling")
		var what := "%s%s%s" % ["sparkling " if case[1] else "", d.id, " with ice" if case[2] else ""]
		glass.setup(d)
		glass.place(Main.GLASS_POS)
		pourer.setup(d)
		pourer.place(Main.GLASS_POS + d.pourer_offset)
		for hold_s in [1.2, 2.0, 2.6, 3.4]:
			main.stream.clear()
			glass.reset()
			pourer.reset()
			if case[2]:
				glass.add_garnish(ice)
			var t := 0.0
			while t < hold_s + 2.0:
				main._step_sim(dt, t < hold_s)
				for b in glass._bubbles + glass._wall_bubbles:
					checked += 1
					var px := Vector2(floorf(b.x) + 0.5, floorf(b.y) + 0.5)
					if not Geometry2D.is_point_in_polygon(px, glass.interior):
						bad += 1
						if worst == "":
							worst = "%s hold %.1fs t=%.2fs bubble at (%.1f, %.1f)" % [what, hold_s, t, b.x, b.y]
				var water := pourer.drawn_liquid_polygons()
				for b in pourer.bubbles:
					pitcher_checked += 1
					var inside := false
					for poly in water:
						inside = inside or Geometry2D.is_point_in_polygon(Vector2(b.x, b.y), poly)
					if not inside:
						pitcher_bad += 1
						if pitcher_worst == "":
							pitcher_worst = "%s hold %.1fs t=%.2fs bubble at (%.1f, %.1f)" % [what, hold_s, t, b.x, b.y]
				t += dt
	print("bubbles checked: %d, outside the glass: %d; in the pitcher: %d, outside its water: %d" % [checked, bad, pitcher_checked, pitcher_bad])
	expect(checked > 0, "some bubbles were spawned")
	expect(bad == 0, "no bubble outside the glass (first offender: %s)" % worst)
	expect(pitcher_checked > 0, "a sparkling pitcher shows bubbles")
	expect(pitcher_bad == 0, "no pitcher bubble outside its water (first offender: %s)" % pitcher_worst)

	# Still water goes still; sparkling water keeps fizzing (in the glass and the pitcher).
	for sparkling in [false, true]:
		GameState.owned_upgrades.clear()
		if sparkling:
			GameState.owned_upgrades.append(&"sparkling")
		glass.setup(GameState.WATER)
		pourer.setup(GameState.WATER)
		pourer.place(Main.GLASS_POS + GameState.WATER.pourer_offset)
		main.stream.clear()
		var t := 0.0
		while t < 14.0:
			main._step_sim(dt, t < 2.6)
			t += dt
		if sparkling:
			expect(glass.fizz > 0.0 and glass._bubbles.size() > 5 and not glass._wall_bubbles.is_empty() and not pourer.bubbles.is_empty(),
				"sparkling water still fizzes 11 s after the pour (%d bubbles, %d on the walls, %d in the pitcher)" % [glass._bubbles.size(), glass._wall_bubbles.size(), pourer.bubbles.size()])
		else:
			expect(glass.fizz == 0.0 and glass._bubbles.is_empty() and glass._wall_bubbles.is_empty() and pourer.bubbles.is_empty(),
				"still water has no bubbles 11 s after the pour (%d, %d on the walls, %d in the pitcher)" % [glass._bubbles.size(), glass._wall_bubbles.size(), pourer.bubbles.size()])
	GameState.owned_upgrades.clear()
