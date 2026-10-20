extends CheckBase
## Plays rounds headless at full simulation speed and checks the round rules
## from the slice 1-3 specs (phases, last call, auto-serve, refill, resets,
## arrivals, drink picks, the shop between rounds, garnishes). Run:
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
	_spill_costs_coins_but_never_below_zero()
	_space_ignored_during_swap_and_refill()
	_next_round_resets_and_reads_stats()
	_round_end_opens_the_shop()
	_round_two_is_water_only()
	_bought_wine_opens_the_next_round()
	_picks_follow_the_seed()
	_drink_change_swaps_the_pourer()
	_mixed_round_with_autopilot()
	_garnish_keys_follow_the_rules()
	_serve_waits_for_falling_ice_and_pays_more()
	_iced_round_with_autopilot()
	_serve_waits_for_an_upright_glass()
	_last_call_waits_for_an_upright_glass()
	_beer_brings_a_new_bottle()
	_beer_round_with_autopilot()
	_beer_earns_at_least_wine()


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
	while main.phase != Main.Phase.SHOP and t < 60.0:
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
	expect(main.phase == Main.Phase.SHOP, "the round ends in the shop")
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
	expect(main.shop.visible, "the shop is shown")


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
	expect(main.phase == Main.Phase.SHOP, "the round ends after the last-call serve")
	expect(t - served_at >= Main.SHOP_DELAY - DT, "the shop waits SHOP_DELAY after the last serve (%.2f s)" % (t - served_at))
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
	expect(main.phase == Main.Phase.SHOP, "...and the round ends")
	GameState.stats = GameState.BASE_STATS.duplicate()


## 0:00 while a replacement bottle slides in: the glass is still on the
## counter, so it gets its last call (the bottle refill finishes first).
func _time_up_during_a_bottle_refill() -> void:
	_fresh_with_wine(3)
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
	expect(main.phase == Main.Phase.SHOP, "...and the round ends")


func _last_call_tiny_pour_still_ends() -> void:
	_to_playing()
	main.time_left = 0.05
	# A drop smaller than 1 % of the glass is in the air when time runs out.
	main.stream.emit(main.pourer.global_position, Vector2(-20, 0), 5.0, DT)
	_run(0.1)
	expect(main.phase == Main.Phase.LAST_CALL, "liquid in the air at 0:00 counts as an active glass")
	_run(6.0)
	expect(main.phase == Main.Phase.SHOP, "a last call that never reaches 1 % still ends the round")
	expect(main.results.is_empty(), "the under-1 % glass isn't scored")


func _time_up_untouched_glass() -> void:
	_to_playing()
	main.time_left = 0.5
	_run(0.6)
	expect(main.phase == Main.Phase.SHOP, "0:00 with an untouched glass goes straight to the shop")
	expect(main.results.is_empty(), "nothing is scored")


func _time_up_mid_swap() -> void:
	_to_playing()
	_pour_until_swap()
	main.time_left = DT * 0.5
	main.tick(DT, false)
	main.next_round()
	eq(main.effects.count(), 0, "a puff left over from the last serve doesn't replay in the next round")
	_to_playing()
	_pour_until_swap()
	main.time_left = DT * 0.5
	main.tick(DT, false)
	expect(main.phase == Main.Phase.SHOP, "0:00 while the next glass arrives ends the round immediately")
	expect(main.results.size() == 1, "only the served glass is scored")


func _empty_serve_ignored() -> void:
	_to_playing()
	main.streak = 2
	main.request_serve()
	_run(0.5)
	expect(main.results.is_empty() and not main.is_swapping(), "serving an empty glass is ignored")
	expect(main.streak == 2, "...and leaves the streak alone")


func _spill_costs_coins_but_never_below_zero() -> void:
	_to_playing()
	GameState.coins = 10
	main.glass.receive(Main.GLASS_POS.x, main.glass.capacity + 50.0, 0.0)  # overflows
	main.request_serve()
	main.tick(DT, false)
	eq(main.results.size(), 1, "the spilled glass is served")
	eq([main.results[0].band, main.results[0].coins, GameState.coins], [Scoring.SPILL, -6, 4], "a water spill takes 6 of 10 coins")
	_run(0.5)
	GameState.coins = 4
	main.glass.receive(Main.GLASS_POS.x, main.glass.capacity + 50.0, 0.0)
	main.request_serve()
	main.tick(DT, false)
	eq([main.results[1].coins, GameState.coins], [-4, 0], "with 4 coins left it takes only 4: the total stops at 0")
	eq(main.round_stats.coins, -10, "the round's coins count what was actually lost")


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
	main.streak = 3
	main.time_left = 0.01
	_run(0.1, true)  # holding DOWN through the end of the round
	expect(main.phase == Main.Phase.SHOP, "the round ended")
	var jug: float = main.pourer.volume
	_run(1.5, true)
	expect(main.stream.is_empty() and main.pourer.volume == jug, "DOWN does nothing in the shop")
	GameState.stats.round_duration = 10.0
	# Leave the pourer tilted, dry and refilling so only start_round can reset it.
	main.pourer.tilt = 0.6
	main.pourer.volume = main.pourer.full_volume * 0.001
	main.pourer.refilling = true
	var round_before: int = GameState.round_number
	main.next_round()
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "next_round starts the next INTRO")
	expect(main.streak == 0, "streak resets")
	expect(main.results.is_empty(), "results reset")
	expect(is_equal_approx(main.time_left, 10.0), "round_duration is read at round start")
	expect(is_equal_approx(main.pourer.volume, main.pourer.full_volume), "the pourer starts full")
	expect(main.pourer.tilt == 0.0 and not main.pourer.refilling, "the pourer starts upright and not refilling")
	expect(main.glass.def == main.drink and main.pourer.def == main.drink, "glass and pourer match the round's first drink")
	expect(not main.shop.visible, "the shop is hidden")
	GameState.stats = GameState.BASE_STATS.duplicate()


func _round_end_opens_the_shop() -> void:
	_to_playing()
	main.time_left = 0.01
	_run(0.1)
	expect(main.phase == Main.Phase.SHOP and main.shop.visible, "time up on an untouched glass opens the shop at once")
	expect(not main.visible and not main.hud.visible, "the bar and the HUD are hidden in the shop")
	eq(main.shop.round_line_label.text, "ROUND 1 · 0 GLASSES · 0 PERFECT · BEST x1 · +0", "the shop shows the round's numbers")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	var round_before: int = GameState.round_number
	main.shop._unhandled_input(space)
	expect(main.phase == Main.Phase.SHOP, "a Space carried over from the last serve is swallowed by the lock")
	main.shop.input_lock = 0.0
	main.shop._unhandled_input(space)
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "Space in the shop starts the next round")
	expect(main.visible and main.hud.visible and not main.shop.visible, "...and brings the bar back")
	main.shop.input_lock = 0.5


## Round 2 of a session that bought wine in the shop: it opens with wine.
func _fresh_with_wine(seed_value: int) -> void:
	GameState.reset_session(seed_value)
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	GameState.coins = 0
	GameState.round_number = 2
	main.start_round()


func _round_two_is_water_only() -> void:
	_fresh(2, 5)
	eq(main.hud.banner_label.text, "ROUND 2", "round 2 brings no drink by itself")
	var seen := {}
	for i in 40:
		seen[main._pick_drink().id] = true
	eq(seen.keys(), [&"water"], "nothing bought: only water")


func _bought_wine_opens_the_next_round() -> void:
	_fresh_with_wine(5)
	var wine: DrinkDef = GameState.WINE
	expect(main.drink == wine and main.glass.def == wine and main.pourer.def == wine, "the round after buying wine opens with wine")
	eq(main.hud.banner_label.text, "ROUND 2\nNEW DRINK: WINE", "the banner names the new drink")
	var seen := {}
	for i in 40:
		seen[main._pick_drink().id] = true
	expect(seen.has(&"water") and seen.has(&"wine"), "later picks include both drinks (%s)" % [seen.keys()])
	GameState.set_on_menu(GameState.WATER, false)
	seen.clear()
	for i in 20:
		seen[main._pick_drink().id] = true
	eq(seen.keys(), [&"wine"], "picks come from the menu")
	GameState.round_number = 3
	main.start_round()
	eq(main.hud.banner_label.text, "ROUND 3", "no banner once wine isn't new")


func _picks_follow_the_seed() -> void:
	var runs: Array = []
	for attempt in 2:
		_fresh_with_wine(42)
		var ids: Array[StringName] = [main.drink.id]
		for i in 20:
			ids.append(main._pick_drink().id)
		runs.append(ids)
	expect(runs[0] == runs[1], "the same seed picks the same drinks")
	_fresh_with_wine(43)
	var other: Array[StringName] = [main.drink.id]
	for i in 20:
		other.append(main._pick_drink().id)
	expect(other != runs[0], "a different seed picks differently")


func _drink_change_swaps_the_pourer() -> void:
	_fresh_with_wine(3)
	_run(Main.INTRO_TIME + DT)
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.WINE
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
	_fresh_with_wine(11)  # a seed that serves both drinks this round
	var pilot := Autopilot.new()
	var t := 0.0
	while main.phase != Main.Phase.SHOP and t < 60.0:
		var d := pilot.decide(main)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	var count := {}
	for r in main.results:
		count[r.drink] = count.get(r.drink, 0) + 1
	expect(main.phase == Main.Phase.SHOP, "the mixed round ends in the shop")
	expect(main.results.size() >= 4, "the autopilot serves at least 4 glasses in a mixed round (%d)" % main.results.size())
	expect(count.has(&"wine") and count.has(&"water"), "round 2 serves both drinks (%s)" % count)
	var good := 0
	for r in main.results:
		if r.band == Scoring.PERFECT or r.band == Scoring.GOOD:
			good += 1
	expect(good * 2 >= main.results.size(), "the autopilot lands most glasses GOOD or better (%d of %d)" % [good, main.results.size()])


func _garnish_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for g in main.garnish_keys():
		ids.append(g.id)
	return ids


func _own_garnishes() -> void:
	GameState.coins = 25
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	GameState.buy_garnish(GameState.WATER.garnishes[1])


func _garnish_keys_follow_the_rules() -> void:
	_fresh()
	var drink := main.drink
	main.drink = null  # the sweep never starts a round, but still ticks once before quitting
	expect(main.garnish_keys().is_empty(), "no garnish keys before any drink is set")
	main.drink = drink
	expect(not main.try_garnish(KEY_UP), "nothing during INTRO")
	_run(Main.INTRO_TIME + DT)
	expect(not main.try_garnish(KEY_UP), "nothing before buying ice")
	expect(main.garnish_keys().is_empty(), "no garnish keys before buying")
	GameState.coins = 10
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	eq(_garnish_ids(), [&"ice"], "ice's key once bought")
	GameState.coins = 15
	GameState.buy_garnish(GameState.WATER.garnishes[1])
	eq(_garnish_ids(), [&"ice", &"lime"], "...and lime's")
	expect(main.try_garnish(KEY_UP) and not main.try_garnish(KEY_UP), "UP adds ice once")
	expect(main.try_garnish(KEY_LEFT) and not main.try_garnish(KEY_DOWN), "LEFT adds lime; other keys don't")
	_run(Glass.ICE_FALL_TIME + DT)  # a serve waits for falling ice
	_serve_with_next(GameState.WATER)
	expect(not main.try_garnish(KEY_UP), "nothing while the next glass arrives")
	_run(0.5)
	expect(main.glass.garnishes.is_empty() and main.try_garnish(KEY_UP), "the next glass arrives bare and takes ice")
	_run(Glass.ICE_FALL_TIME + DT)
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	_serve_with_next(GameState.WINE)
	_run(0.6)
	expect(not main.try_garnish(KEY_UP) and not main.try_garnish(KEY_LEFT), "wine takes no garnish")
	expect(main.garnish_keys().is_empty(), "no garnish keys on wine")
	main.time_left = 0.01
	_run(6.0)
	expect(main.phase == Main.Phase.SHOP, "the round ended")
	expect(not main.try_garnish(KEY_UP) and not main.try_garnish(KEY_LEFT), "nothing in the shop")
	main.next_round()
	_run(Main.INTRO_TIME + DT)
	expect(main.glass.garnishes.is_empty(), "nothing carried into the next round")


func _serve_waits_for_falling_ice_and_pays_more() -> void:
	_to_playing()
	_own_garnishes()
	main.try_garnish(KEY_UP)
	main.try_garnish(KEY_LEFT)
	main.glass.receive(Main.GLASS_POS.x, main.glass.target * 0.5, 0.0)
	main.request_serve()
	main.tick(DT, false)
	expect(main.results.is_empty(), "a serve waits while the ice falls")
	_run(Glass.ICE_FALL_TIME)
	eq(main.results.size(), 1, "...and fires once it has landed")
	if main.results.size() == 1:
		eq(main.results[0].garnishes, [&"ice", &"lime"], "the score records both garnishes")
	_run(0.5)
	main.try_garnish(KEY_UP)
	main.try_garnish(KEY_LEFT)
	_run(Glass.ICE_FALL_TIME + DT)
	var g := main.glass
	g.receive(Main.GLASS_POS.x, g.target - g.displaced(g.target), 0.0)
	main.streak = 0
	main.request_serve()
	main.tick(DT, false)
	if main.results.size() == 2:
		eq([main.results[1].band, main.results[1].coins], [Scoring.PERFECT, 15], "a PERFECT iced lime water pays 15")
	else:
		expect(false, "the second garnished glass was served")


func _iced_round_with_autopilot() -> void:
	_fresh()
	GameState.coins = 120
	Autopilot.new().shop(main)
	expect(GameState.owns_garnish(GameState.WATER.garnishes[1]) and GameState.owns_drink(GameState.WINE), "the autopilot buys ice, lime, wine")
	GameState.coins = 400
	Autopilot.new().shop(main)
	eq(GameState.owned_upgrades, [&"sparkling", &"premium", &"vintage", &"water_refill", &"wine_refill"] as Array[StringName],
		"then sparkling, premium, vintage and both refills")
	eq(GameState.coins, 400 - 225, "...for 225")
	GameState.owned_upgrades.clear()
	GameState.set_on_menu(GameState.WINE, false)
	main.start_round()
	var pilot := Autopilot.new()
	var t := 0.0
	while main.phase != Main.Phase.SHOP and t < 60.0:
		var d := pilot.decide(main)
		for k in d.keys:
			main.try_garnish(k)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	var garnished := 0
	var good := 0
	for r in main.results:
		garnished += 1 if r.garnishes.size() == 2 else 0
		good += 1 if r.band == Scoring.PERFECT or r.band == Scoring.GOOD else 0
	expect(main.results.size() >= 4 and garnished == main.results.size(), "every autoplayed water glass is iced and limed (%d of %d)" % [garnished, main.results.size()])
	expect(good * 2 >= main.results.size(), "...and most land GOOD or better (%d of %d)" % [good, main.results.size()])


## A beer glass with the target in it, the bottle ready, nothing pouring, then
## tipped as if the pour had just stopped.
func _tipped_beer_glass() -> void:
	_fresh()
	GameState.owned_drinks.append(GameState.BEER)
	_run(Main.INTRO_TIME + DT)
	_serve_with_next(GameState.BEER)  # the next glass is beer
	_run(Arrival.ARRIVE_TIME + Pourer.POP_TIME + 0.1)
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.glass.tilt = 0.4
	main.glass._tilt_idle = 0.0


func _serve_waits_for_an_upright_glass() -> void:
	_tipped_beer_glass()
	var served: int = main.results.size()
	main.request_serve()
	main.tick(DT, false)
	expect(main.results.size() == served and main.is_serve_queued(), "a serve waits while the glass is tipped")
	var t := DT
	while main.results.size() == served and t < 2.0:
		main.tick(DT, false)
		t += DT
	expect(main.results.size() == served + 1 and t >= Glass.TILT_GRACE, "...and fires once it is upright (%.2f s)" % t)


func _last_call_waits_for_an_upright_glass() -> void:
	_tipped_beer_glass()
	main._enter(Main.Phase.LAST_CALL)
	main._idle = 0.0
	var served: int = main.results.size()
	var t := 0.0
	while main.results.size() == served and t < Main.LAST_CALL_IDLE + 2.0:
		main.tick(DT, false)
		t += DT
	expect(t >= Main.LAST_CALL_IDLE + Glass.TILT_GRACE, "last call's idle starts once the glass is upright (served at %.2f s)" % t)
	expect(main.results.size() == served + 1 and t < Main.LAST_CALL_IDLE + 1.0, "...then it auto-serves (%.2f s)" % t)


## Every beer glass comes with its own new, full, capped bottle, whatever was
## left in the last one; wine keeps its bottle across glasses.
func _beer_brings_a_new_bottle() -> void:
	_fresh()
	GameState.owned_drinks.append(GameState.BEER)
	GameState.menu.append(GameState.BEER)
	GameState.new_drinks.append(GameState.BEER)  # start_round() opens with it
	main.start_round()
	_run(Main.INTRO_TIME + DT)
	expect(main.drink == GameState.BEER, "the round opens with beer")
	var pops := [0]
	var count := func(_a: Vector2, _v: Vector2, _c: Color) -> void: pops[0] += 1
	main.pourer.popped.connect(count)
	main.pourer.volume = main.pourer.full_volume * 0.4  # what was left of the last bottle
	_serve_with_next(GameState.BEER)
	expect(main.pourer.is_arriving() and main.pourer.corked, "the next beer brings a new, capped bottle")
	_run(Arrival.ARRIVE_TIME + Pourer.POP_TIME + DT)
	expect(pops[0] == 1 and main.pourer.volume == main.pourer.full_volume, "...full, its cap popped (%d pops)" % pops[0])
	main.pourer.popped.disconnect(count)
	_serve_with_next(GameState.WINE)
	_run(Arrival.ARRIVE_TIME + Pourer.POP_TIME + DT)
	_serve_with_next(GameState.WINE)
	expect(not main.pourer.is_arriving(), "wine still keeps its bottle across glasses")


## A round of only `d`, played by the autopilot: its results, coins and how
## many bottles were opened.
func _round_of(d: DrinkDef, seed_value: int) -> Dictionary:
	GameState.reset_session(seed_value)
	if not GameState.owned_drinks.has(d):
		GameState.owned_drinks.append(d)
	GameState.menu.assign([d])
	main.start_round()
	var pilot := Autopilot.new()
	var pops := [0]
	var count := func(_a: Vector2, _v: Vector2, _c: Color) -> void: pops[0] += 1
	main.pourer.popped.connect(count)
	var t := 0.0
	while main.phase != Main.Phase.SHOP and t < 60.0:
		var dec := pilot.decide(main)
		if dec.serve:
			main.request_serve()
		main.tick(DT, dec.hold)
		t += DT
	main.pourer.popped.disconnect(count)
	return {"results": main.results.duplicate(), "coins": main.round_stats.coins, "pops": pops[0]}


## The autopilot feathers beer: mostly GOOD or better, no spill, a bottle per glass.
func _beer_round_with_autopilot() -> void:
	var r := _round_of(GameState.BEER, 5)
	var bands: Array = r.results.map(func(x: Dictionary) -> StringName: return x.band)
	var good := bands.filter(func(b: StringName) -> bool: return b == Scoring.PERFECT or b == Scoring.GOOD)
	expect(bands.size() >= 3, "the autopilot serves at least 3 beers in a round (%d)" % bands.size())
	expect(good.size() * 10 >= bands.size() * 6 and not bands.has(Scoring.SPILL), "...mostly GOOD or better, no spill (%s)" % [bands])
	expect(r.pops >= bands.size(), "each beer had its own bottle (%d caps for %d glasses)" % [r.pops, bands.size()])


## Beer is worth its 150 coins: a round of it earns at least a round of wine.
func _beer_earns_at_least_wine() -> void:
	var wine := _round_of(GameState.WINE, 5)
	var beer := _round_of(GameState.BEER, 5)
	expect(beer.coins >= wine.coins, "a round of beer earns at least a round of wine (%d vs %d)" % [beer.coins, wine.coins])
