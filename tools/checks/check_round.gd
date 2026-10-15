extends CheckBase
## Plays rounds headless at full simulation speed and checks the round rules
## from the slice 1 and slice 2 specs (phases, last call, auto-serve, refill,
## resets, arrivals, drink picks). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round

const DT := 1.0 / 60.0
var main: Main


func run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	_intro_ignores_input_and_arrivals_land()
	_full_round_with_autopilot()
	_last_call_auto_serve()
	_last_call_held_down_while_refilling_does_not_serve()
	_last_call_waits_for_a_refill()
	_time_up_during_a_bottle_refill()
	_last_call_tiny_pour_still_ends()
	_time_up_untouched_glass()
	_time_up_mid_swap()
	_empty_serve_ignored()
	_space_ignored_during_swap_and_refill()
	_next_round_resets_and_reads_stats()
	_round_two_unlocks_wine()
	_picks_follow_the_seed()
	_drink_change_swaps_the_pourer()
	_mixed_round_with_autopilot()


func _fresh(round_number := 1, seed_value := 1) -> void:
	GameState.reset_session(seed_value)
	GameState.round_number = round_number
	main.start_round()


func _run(seconds: float, hold := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		main.tick(DT, hold)
		t += DT


func _to_playing() -> void:
	_fresh()
	_run(Main.INTRO_TIME + DT)


## Lets the autopilot play until a serve starts (the next glass begins to arrive).
func _pour_until_swap() -> void:
	var pilot := Autopilot.new()
	var t := 0.0
	while not main.is_swapping() and t < 15.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	expect(main.is_swapping(), "the autopilot served a glass")


## Puts a glass at the target in, queues a serve with `next` as the next
## drink and lets it fire this tick.
func _serve_with_next(next: DrinkDef, hold := false) -> void:
	main._force_next = next
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.request_serve()
	main.tick(DT, hold)
	expect(main.glass.is_arriving(), "the serve fired and the next glass is arriving")


func _intro_ignores_input_and_arrivals_land() -> void:
	_fresh()
	expect(main.phase == Main.Phase.INTRO, "a round starts in INTRO")
	expect(main.glass.is_arriving() and main.pourer.is_arriving(), "the first glass and pourer arrive during INTRO")
	_run(1.0, true)
	expect(main.phase == Main.Phase.INTRO and main.pourer.tilt == 0.0, "DOWN is ignored during INTRO")
	expect(main.glass.position == Main.GLASS_POS and main.pourer.position == Main.GLASS_POS + main.drink.pourer_offset,
		"they have arrived by then")
	expect(is_equal_approx(main.time_left, 30.0), "the timer doesn't run during INTRO")
	_run(0.6, true)
	expect(main.phase == Main.Phase.PLAYING, "INTRO lasts 1.5 s")
	expect(main.time_left < 30.0 and main.time_left > 29.8, "the timer runs while PLAYING (%.2f)" % main.time_left)


func _full_round_with_autopilot() -> void:
	_fresh()
	var pilot := Autopilot.new()
	var coins_before: int = GameState.coins
	var served_at_time_up := -1
	var saw_refill := false
	var refill_done := false
	var refill_rest_ticks := 0
	var t := 0.0
	while main.phase != Main.Phase.SUMMARY and t < 60.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		if main.pourer.refilling:
			saw_refill = true
			if not refill_done and main.pourer.tilt == 0.0 and main.pourer.tilt_vel == 0.0:
				refill_rest_ticks += 1
		elif saw_refill:
			refill_done = true
		if served_at_time_up < 0 and main.time_left <= 0.0:
			served_at_time_up = main.results.size()
		t += DT
	expect(main.phase == Main.Phase.SUMMARY, "the round reaches SUMMARY")
	expect(main.results.size() >= 4, "the autopilot serves at least 4 glasses (served %d)" % main.results.size())
	expect(main.results.size() - served_at_time_up <= 1, "at most one glass is served after 0:00")
	var total := 0
	var only_water := true
	for r in main.results:
		total += r.coins
		only_water = only_water and r.drink == &"water"
	expect(only_water, "round 1 serves only water")
	expect(total == main.round_stats.coins, "round coins equal the sum of paid glasses")
	expect(GameState.coins - coins_before == total, "GameState.coins grew by the round's coins")
	expect(main.round_stats.served == main.results.size(), "served count matches the results")
	expect(saw_refill, "the pitcher ran dry and refilled during the round")
	expect(absf(refill_rest_ticks * DT - 1.0) < 0.1, "the refill lasts refill_time once upright (%.2f s)" % (refill_rest_ticks * DT))
	expect(main.summary.visible, "the summary is shown")


func _last_call_auto_serve() -> void:
	_to_playing()
	main.time_left = 1.0
	_run(1.2, true)  # 0:00 hits while pouring
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 while pouring enters LAST_CALL")
	var t := 0.0
	var idle_from := -1.0  # when nothing was pouring, in the air or held (and no swap)
	var served_at := -1.0
	while main.phase == Main.Phase.LAST_CALL and t < 10.0:
		main.tick(DT, false)
		t += DT
		if idle_from < 0.0 and not main.pourer.is_pouring() and main.stream.is_empty() and not main.is_swapping():
			idle_from = t
		if served_at < 0.0 and main.results.size() == 1:
			served_at = t
	expect(main.results.size() == 1, "the last-call glass is served automatically")
	var idle_for := served_at - idle_from
	expect(idle_from >= 0.0 and idle_for >= 3.0 and idle_for < 3.1, "auto-serve comes 3.0-3.1 s after the idle starts (%.3f s)" % idle_for)
	expect(main.phase == Main.Phase.SUMMARY, "the round ends after the last-call serve")
	expect(t - served_at >= Main.SUMMARY_DELAY - DT, "the summary waits SUMMARY_DELAY after the last serve (%.2f s)" % (t - served_at))
	expect(not main.glass.visible, "the last glass vanishes and no new glass arrives")
	main.next_round()
	expect(main.glass.visible and main.glass.is_arriving(), "the next round's first glass is visible and arriving")


func _last_call_held_down_while_refilling_does_not_serve() -> void:
	_to_playing()
	_run(1.5, true)
	expect(main.glass.volume > main.glass.capacity * Main.ACTIVE_SHARE, "some liquid is in the glass")
	main.time_left = 0.05
	_run(0.1, true)
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 with an active glass enters LAST_CALL")
	GameState.stats.refill_time = 5.0
	main.pourer.volume = main.pourer.full_volume * 0.001
	var served := main.results.size()
	_run(4.0, true)
	expect(main.pourer.refilling, "the pitcher is still refilling")
	expect(main.phase == Main.Phase.LAST_CALL and main.results.size() == served, "holding DOWN for 4 s blocks the idle auto-serve")
	GameState.stats = GameState.BASE_STATS.duplicate()


func _last_call_waits_for_a_refill() -> void:
	_to_playing()
	_run(1.5, true)
	main.time_left = 0.05
	_run(0.1, true)
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 with an active glass enters LAST_CALL")
	GameState.stats.refill_time = 5.0
	main.pourer.volume = main.pourer.full_volume * 0.001
	var served := main.results.size()
	_run(4.5)  # DOWN released: it swings back and refills for 5 s
	expect(main.pourer.refilling and main.results.size() == served, "the idle auto-serve waits while the pitcher refills")
	_run(6.0)
	expect(main.results.size() == served + 1, "...then serves 3 s after the refill")
	expect(main.phase == Main.Phase.SUMMARY, "...and the round ends")
	GameState.stats = GameState.BASE_STATS.duplicate()


## 0:00 while a replacement bottle slides in: the glass is still on the
## counter, so it gets its last call (the bottle refill finishes first).
func _time_up_during_a_bottle_refill() -> void:
	_fresh(2, 3)
	_run(Main.INTRO_TIME + 0.5)  # the opening wine bottle has arrived and popped its cork
	main.glass.receive(Main.GLASS_POS.x, main.glass.target * 0.8, 0.0)
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.tick(DT, false)  # at rest and dry: the empty bottle vanishes, a new one starts arriving
	expect(main.pourer.refilling and main.pourer.is_arriving(), "the replacement bottle is arriving")
	main.time_left = DT * 0.5
	main.tick(DT, false)
	expect(main.phase == Main.Phase.LAST_CALL, "0:00 while the new bottle arrives still gives the glass its last call (phase %s)" % Main.Phase.keys()[main.phase])
	_run(6.0)
	expect(main.results.size() == 1, "the part-filled glass is scored")
	expect(main.phase == Main.Phase.SUMMARY, "...and the round ends")


func _last_call_tiny_pour_still_ends() -> void:
	_to_playing()
	main.time_left = 0.05
	# A drop smaller than 1 % of the glass is in the air when time runs out.
	main.stream.emit(main.pourer.global_position, Vector2(-20, 0), 5.0, DT)
	_run(0.1)
	expect(main.phase == Main.Phase.LAST_CALL, "liquid in the air at 0:00 counts as an active glass")
	_run(6.0)
	expect(main.phase == Main.Phase.SUMMARY, "a last call that never reaches 1 % still ends the round")
	expect(main.results.is_empty(), "the under-1 % glass isn't scored")


func _time_up_untouched_glass() -> void:
	_to_playing()
	main.time_left = 0.5
	_run(0.6)
	expect(main.phase == Main.Phase.SUMMARY, "0:00 with an untouched glass goes straight to SUMMARY")
	expect(main.results.is_empty(), "nothing is scored")


func _time_up_mid_swap() -> void:
	_to_playing()
	_pour_until_swap()
	main.time_left = DT * 0.5
	main.tick(DT, false)
	expect(main.phase == Main.Phase.SUMMARY, "0:00 while the next glass arrives ends the round immediately")
	expect(main.results.size() == 1, "only the served glass is scored")


func _empty_serve_ignored() -> void:
	_to_playing()
	main.streak_steps = 2
	main.request_serve()
	_run(0.5)
	expect(main.results.is_empty() and not main.is_swapping(), "serving an empty glass is ignored")
	expect(main.streak_steps == 2, "...and leaves the streak alone")


func _space_ignored_during_swap_and_refill() -> void:
	_to_playing()
	_pour_until_swap()
	var served := main.results.size()
	var filled := false
	while main.is_swapping():
		main.request_serve()  # mashing Space
		main.tick(DT, false)
		if not filled:
			# Put water in the arriving glass so a wrongly queued serve would score.
			filled = true
			main.glass.receive(Main.GLASS_POS.x, 500.0, 0.0)
	expect(filled, "the arriving glass was filled")
	_run(0.5)
	expect(main.results.size() == served, "Space mashed while the next glass arrives doesn't serve it")
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.tick(DT, false)
	expect(main.pourer.refilling, "a dry pitcher refills")
	main.request_serve()
	_run(0.2)
	expect(main.results.size() == served, "Space is ignored while refilling")


func _next_round_resets_and_reads_stats() -> void:
	_to_playing()
	_pour_until_swap()  # one glass served: results and a drained pourer
	_run(1.0)
	expect(main.results.size() == 1, "one glass was served before the round ends")
	expect(main.pourer.volume < main.pourer.full_volume, "the pitcher was drained by the serve")
	main.streak_steps = 3
	main.time_left = 0.01
	_run(0.1, true)  # holding DOWN through the end of the round
	expect(main.phase == Main.Phase.SUMMARY, "the round ended")
	_run(1.5, true)
	expect(main.pourer.tilt < 0.001, "DOWN is ignored on the summary (pitcher upright)")
	GameState.stats.round_duration = 10.0
	GameState.stats.good_tol = 0.2
	# Leave the pourer tilted, dry and refilling so only start_round can reset it.
	main.pourer.tilt = 0.6
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.pourer.refilling = true
	var round_before: int = GameState.round_number
	main.next_round()
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "next_round starts the next INTRO")
	expect(main.streak_steps == 0, "streak resets")
	expect(main.results.is_empty(), "results reset")
	expect(is_equal_approx(main.time_left, 10.0), "round_duration is read at round start")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "the pourer starts full")
	expect(main.pourer.tilt == 0.0 and not main.pourer.refilling, "the pourer starts upright and not refilling")
	expect(main.glass.def == main.drink and main.pourer.def == main.drink, "glass and pourer match the round's first drink")
	expect(not main.summary.visible, "the summary is hidden")
	var levels := main.glass.band_levels()
	expect(is_equal_approx(levels.x, roundf(main.glass.level_for(main.glass.target * 1.2))), "band markers follow stats.good_tol")
	GameState.stats = GameState.BASE_STATS.duplicate()


func _round_two_unlocks_wine() -> void:
	_fresh(2, 5)
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	expect(GameState.owned_drinks.has(wine), "round 2 unlocks wine")
	expect(main.drink == wine and main.glass.def == wine and main.pourer.def == wine, "round 2 opens with wine: glass and bottle")
	eq(main.hud.banner_label.text, "ROUND 2\nNEW DRINK: WINE", "the banner names the new drink")
	var seen := {}
	for i in 40:
		seen[main._pick_drink().id] = true
	expect(seen.has(&"water") and seen.has(&"wine"), "after the first glass, picks include both drinks (%s)" % [seen.keys()])
	GameState.round_number = 3
	main.start_round()
	eq(main.hud.banner_label.text, "ROUND 3", "no unlock banner once wine is owned")
	eq(GameState.owned_drinks.size(), 2, "wine isn't added twice")


func _picks_follow_the_seed() -> void:
	var runs: Array = []
	for attempt in 2:
		_fresh(2, 42)
		var ids: Array[StringName] = [main.drink.id]
		for i in 20:
			ids.append(main._pick_drink().id)
		runs.append(ids)
	expect(runs[0] == runs[1], "the same seed picks the same drinks")
	_fresh(2, 43)
	var other: Array[StringName] = [main.drink.id]
	for i in 20:
		other.append(main._pick_drink().id)
	expect(other != runs[0], "a different seed picks differently")


func _drink_change_swaps_the_pourer() -> void:
	_fresh(2, 3)
	_run(Main.INTRO_TIME + DT)
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.ROUND_UNLOCKS[2]
	expect(main.drink == wine and not main.pourer.is_busy(), "wine is ready to pour")
	main.pourer.volume = main.pourer.full_volume * 0.5
	_serve_with_next(water)
	expect(main.drink == water and main.pourer.def == water and main.pourer.is_arriving(), "a drink change brings the other pourer")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "...full")
	_run(0.5)
	main.pourer.volume = main.pourer.full_volume * 0.6
	_serve_with_next(water)
	expect(not main.pourer.is_arriving(), "the same drink keeps its pourer")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume * 0.6), "...at its level")
	_run(0.5)
	# DOWN held through a drink change: the new bottle ignores it until it's
	# uncorked, then tilts while DOWN is still held.
	_serve_with_next(wine, true)
	var tilted_while_busy := false
	var t := 0.0
	while t < 1.0:
		main.tick(DT, true)
		tilted_while_busy = tilted_while_busy or (main.pourer.is_busy() and main.pourer.tilt > 0.0)
		t += DT
	expect(not tilted_while_busy, "DOWN is ignored while the bottle arrives and is uncorked")
	expect(main.pourer.tilt > 0.0, "...then it tilts with DOWN still held")


func _mixed_round_with_autopilot() -> void:
	_fresh(2, 11)  # a seed that serves both drinks this round
	var pilot := Autopilot.new()
	var t := 0.0
	while main.phase != Main.Phase.SUMMARY and t < 60.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	var count := {}
	for r in main.results:
		count[r.drink] = count.get(r.drink, 0) + 1
	expect(main.phase == Main.Phase.SUMMARY, "the mixed round reaches SUMMARY")
	expect(main.results.size() >= 4, "the autopilot serves at least 4 glasses in a mixed round (%d)" % main.results.size())
	expect(count.has(&"wine") and count.has(&"water"), "round 2 serves both drinks (%s)" % count)
	var good := 0
	for r in main.results:
		if r.band == Scoring.PERFECT or r.band == Scoring.GOOD:
			good += 1
	expect(good * 2 >= main.results.size(), "the autopilot lands most glasses GOOD or better (%d of %d)" % [good, main.results.size()])
