extends CheckBase
## Checks the keyboard keys drawn in the HUD (docs/superpowers/specs/2026-10-18-key-art-design.md):
## Main's rules for when SPACE and the garnish keys show, and the DOWN hold
## they follow. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=keys

const DT := 1.0 / 60.0
var main: Main


func run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	_space_rules()
	_garnish_rules()
	_hold_down_follows_tick()


func _fresh(round_number := 1, seed_value := 1) -> void:
	GameState.reset_session(seed_value)
	GameState.round_number = round_number
	main.start_round()


func _run(seconds: float, hold := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		main.tick(DT, hold)
		t += DT


## Ticks with `hold` until `done` is true (at most `limit` s); true if any tick
## along the way could serve.
func _until(done: Callable, hold: bool, limit := 6.0) -> bool:
	var could := false
	var t := 0.0
	while not done.call() and t < limit:
		could = could or main.can_serve_now()
		main.tick(DT, hold)
		t += DT
	return could


func _garnish_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for g in main.garnish_keys():
		ids.append(g.id)
	return ids


func _space_rules() -> void:
	_fresh()
	expect(not main.can_serve_now(), "no SPACE during INTRO")
	_run(Main.INTRO_TIME + DT)
	expect(not main.can_serve_now(), "no SPACE on an empty glass")
	_until(main.pourer.is_pouring, true)
	expect(main.pourer.is_pouring() and not main.can_serve_now(), "no SPACE while pouring")
	_run(0.4, true)
	_until(func() -> bool: return not main.pourer.is_pouring() and main.stream.is_empty(), false)
	expect(main.can_serve_now(), "SPACE once the pour has landed")
	_until(main.pourer.is_pouring, true)
	expect(not main.can_serve_now(), "SPACE hides when pouring again")
	main.request_serve()
	var shown := _until(main.is_swapping, false)
	expect(main.is_swapping() and not shown, "a serve queued mid-pour never shows SPACE before it fires")
	_run(0.5)
	expect(not main.glass.is_arriving() and not main.can_serve_now(), "the next glass lands empty: no SPACE")
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	expect(main.can_serve_now(), "SPACE on a filled, still glass")
	main.pourer.volume = 0.0
	main.tick(DT, false)
	expect(main.pourer.refilling, "the pourer refills")
	shown = _until(func() -> bool: return not main.pourer.refilling, false)
	expect(not shown, "no SPACE for the whole refill")
	expect(main.can_serve_now(), "...and SPACE again after it")
	main.time_left = 0.01
	main.tick(DT, false)
	expect(main.phase == Main.Phase.LAST_CALL and main.can_serve_now(), "SPACE in LAST CALL with liquid in")
	_until(func() -> bool: return main._shop_in >= 0.0, false)
	expect(main._shop_in >= 0.0 and not main.can_serve_now(), "no SPACE once the last glass is served")
	_run(1.0)
	expect(main.phase == Main.Phase.SHOP and not main.can_serve_now(), "no SPACE in the shop")


func _garnish_rules() -> void:
	_fresh()
	_run(Main.INTRO_TIME + DT)
	expect(main.garnish_keys().is_empty(), "no garnish keys before buying")
	GameState.coins = 25
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	GameState.buy_garnish(GameState.WATER.garnishes[1])
	GameState.round_number = 2
	main.start_round()
	expect(main.garnish_keys().is_empty(), "no garnish keys during INTRO")
	_run(Main.INTRO_TIME + DT)
	eq(_garnish_ids(), [&"ice", &"lime"], "both garnish keys once bought, on a landed glass")
	main.glass.receive(Main.GLASS_POS.x, main.glass.target * 0.5, 0.0)
	main.try_garnish(KEY_UP)
	eq(_garnish_ids(), [&"lime"], "ice in: only LEFT is left")
	expect(not main.can_serve_now(), "no SPACE while the ice falls")
	_run(Glass.ICE_FALL_TIME + DT)
	expect(main.can_serve_now(), "SPACE once the ice has landed")
	main.try_garnish(KEY_LEFT)
	expect(main.garnish_keys().is_empty(), "both on: no garnish keys")
	_run(Glass.LIME_DROP_TIME + DT)
	main.request_serve()
	main.tick(DT, false)
	expect(main.glass.is_arriving() and main.garnish_keys().is_empty(), "no garnish keys while the next glass arrives")
	_run(0.5)
	eq(_garnish_ids(), [&"ice", &"lime"], "the next glass shows both again")
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	main._force_next = GameState.WINE
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.request_serve()
	main.tick(DT, false)
	_run(0.6)
	expect(main.drink == GameState.WINE and main.garnish_keys().is_empty(), "no garnish keys on wine")
	var drink := main.drink
	main.drink = null
	expect(main.garnish_keys().is_empty(), "no garnish keys without a drink")
	main.drink = drink


func _hold_down_follows_tick() -> void:
	_fresh()
	main.tick(DT, true)
	expect(not main.hold_down, "DOWN isn't held during INTRO")
	_run(Main.INTRO_TIME)
	main.tick(DT, true)
	expect(main.hold_down, "DOWN held while playing")
	main.tick(DT, false)
	expect(not main.hold_down, "...and released")
	main.open_shop()
	main.tick(DT, true)
	expect(not main.hold_down, "DOWN isn't held in the shop")
