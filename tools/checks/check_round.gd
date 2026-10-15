extends CheckBase
## Plays rounds headless at full simulation speed and checks the round rules
## from the slice 1 spec (phases, last call, auto-serve, refill, resets). Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round

const DT := 1.0 / 60.0
var main: Main


func run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	_intro_ignores_input()
	_full_round_with_autopilot()
	_last_call_auto_serve()
	_last_call_tiny_pour_still_ends()
	_time_up_untouched_glass()
	_time_up_mid_swap()
	_empty_serve_ignored()
	_space_ignored_during_swap_and_refill()
	_next_round_resets_and_reads_stats()


func _fresh() -> void:
	GameState.stats = GameState.BASE_STATS.duplicate()
	GameState.round_number = 1
	main.start_round()


func _run(seconds: float, hold := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		main.tick(DT, hold)
		t += DT


func _to_playing() -> void:
	_fresh()
	_run(Main.INTRO_TIME + DT)


## Lets the autopilot play until a serve starts (the glass begins to slide out).
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


func _intro_ignores_input() -> void:
	_fresh()
	expect(main.phase == Main.Phase.INTRO, "a round starts in INTRO")
	_run(1.0, true)
	expect(main.phase == Main.Phase.INTRO and main.pourer.tilt == 0.0, "DOWN is ignored during INTRO")
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
	for r in main.results:
		total += r.coins
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
	var served_at := -1.0
	while main.phase == Main.Phase.LAST_CALL and t < 10.0:
		main.tick(DT, false)
		t += DT
		if served_at < 0.0 and main.results.size() == 1:
			served_at = t
	expect(main.results.size() == 1, "the last-call glass is served automatically")
	expect(served_at >= 3.0, "auto-serve waits for 3 s of idle (served after %.2f s)" % served_at)
	expect(main.phase == Main.Phase.SUMMARY, "the round ends after the last-call serve")
	expect(main.glass.position.x == Main.OFFSCREEN_X, "no new glass slides in after last call")


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
	expect(main.phase == Main.Phase.SUMMARY, "0:00 during a glass swap ends the round immediately")
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
		if not filled and main._swap_t > Main.SWAP_OUT_TIME:
			# The new glass is in: put water in it so a wrongly queued serve would score.
			filled = true
			main.glass.receive(Main.GLASS_POS.x, 500.0, 0.0)
	expect(filled, "the new glass was filled during the swap")
	_run(0.5)
	expect(main.results.size() == served, "Space mashed during a swap doesn't serve the next glass")
	main.glass.receive(Main.GLASS_POS.x, 500.0, 0.0)
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.tick(DT, false)
	expect(main.pourer.refilling, "a dry pitcher refills")
	main.request_serve()
	_run(0.2)
	expect(main.results.size() == served, "Space is ignored while refilling")


func _next_round_resets_and_reads_stats() -> void:
	_to_playing()
	main.streak_steps = 3
	main.time_left = 0.01
	_run(0.1, true)  # holding DOWN through the end of the round
	expect(main.phase == Main.Phase.SUMMARY, "the round ended")
	_run(1.5, true)
	expect(main.pourer.tilt < 0.001, "DOWN is ignored on the summary (pitcher upright)")
	GameState.stats.round_duration = 10.0
	GameState.stats.good_tol = 0.2
	var round_before: int = GameState.round_number
	main.next_round()
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "next_round starts the next INTRO")
	expect(main.streak_steps == 0 and main.results.is_empty(), "streak and results reset")
	expect(is_equal_approx(main.time_left, 10.0), "round_duration is read at round start")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "the pitcher starts full")
	expect(not main.summary.visible, "the summary is hidden")
	var levels := main.glass.band_levels()
	expect(is_equal_approx(levels.x, roundf(main.glass.level_for(main.glass.target * 1.2))), "band markers follow stats.good_tol")
	GameState.stats = GameState.BASE_STATS.duplicate()
