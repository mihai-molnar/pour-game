extends CheckBase
## Checks HUD formatting/state and the round summary screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=ui


func run() -> void:
	eq(Hud.format_time(30.0), "0:30", "30 s")
	eq(Hud.format_time(29.01), "0:30", "counts whole seconds up")
	eq(Hud.format_time(5.0), "0:05", "5 s")
	eq(Hud.format_time(0.2), "0:01", "the last fraction shows 0:01")
	eq(Hud.format_time(0.0), "0:00", "0 s")
	eq(Hud.format_time(-1.0), "0:00", "never negative")
	eq(Hud.format_time(75.0), "1:15", "minutes")
	eq(Hud.format_mult(0), "x1", "x1")
	eq(Hud.format_mult(1), "x1.5", "x1.5")
	eq(Hud.format_mult(2), "x2", "x2")
	eq(Hud.format_mult(4), "x3", "x3")
	eq(Hud.format_mult(9), "x3", "capped at x3")
	eq(Hud.round_banner(1, null), "ROUND 1", "plain round banner")
	eq(Hud.round_banner(2, GameState.ROUND_UNLOCKS[2]), "ROUND 2\nNEW DRINK: WINE", "the unlock banner names the drink")

	var hud: Hud = load("res://hud.gd").new()
	add_child(hud)
	hud.set_time(4.0)
	eq(hud.timer_label.text, "0:04", "timer text")
	eq(hud.timer_label.get_theme_color("font_color"), Palette.RED, "timer is red in the last 5 s")
	hud.set_time(12.0)
	eq(hud.timer_label.get_theme_color("font_color"), Palette.WHITE, "timer is white otherwise")
	hud.set_coins(42)
	eq(hud.coins_label.text, "COINS 42", "coins label")
	hud.set_streak(2)
	eq(hud.streak_label.text, "x2", "streak label")
	hud.show_banner("LAST CALL!", 1.5)
	eq(hud.banner_label.visible and hud.banner_label.text == "LAST CALL!", true, "banner shows")
	for c in [
		[{"band": Scoring.PERFECT, "coins": 15}, "+15", Palette.GOLD],
		[{"band": Scoring.GOOD, "coins": 7}, "+7", Palette.GREEN],
		[{"band": Scoring.MISS, "coins": 0}, "0", Palette.RED],
		[{"band": Scoring.SPILL, "coins": 0}, "0", Palette.RED],
	]:
		var label := hud.popup(c[0], Vector2(100, 100))
		eq(label.text, c[1], "%s popup text" % c[0].band)
		eq(label.get_theme_color("font_color"), c[2], "%s popup color" % c[0].band)
	eq(hud.is_debug_visible(), false, "debug starts hidden")
	hud.toggle_debug()
	eq(hud.is_debug_visible(), true, "F1 toggles debug")

	var summary: RoundSummary = load("res://round_summary.tscn").instantiate()
	add_child(summary)
	eq(summary.visible, false, "summary starts hidden")
	summary.show_results(3, {"served": 7, "perfects": 2, "best_steps": 4, "coins": 55}, 120)
	eq(summary.visible, true, "show_results shows it")
	var text := summary.body_text()
	for want in ["GLASSES", "7", "PERFECT", "2", "x3", "+55", "120"]:
		eq(text.contains(want), true, "summary shows %s" % want)
	var pressed := [false]
	summary.next_pressed.connect(func() -> void: pressed[0] = true)
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	summary._unhandled_input(space)
	eq(pressed[0] == false and summary.visible, true, "Space right after show_results is ignored (input lock)")
	summary._next()
	eq(pressed[0] == false and summary.visible, true, "the button is locked too")
	summary.input_lock = 0.0
	summary._unhandled_input(space)
	eq(pressed[0], true, "Space on the summary emits next_pressed")
	eq(summary.visible, false, "...and hides it")

	var fx: Effects = load("res://effects.gd").new()
	add_child(fx)
	fx.puff(Vector2(100, 100))
	expect(fx.count() >= 4 and fx.count() <= 6, "a puff is 4-6 pixels (%d)" % fx.count())
	fx.cork(Vector2(100, 100), Vector2(-100, -100), Palette.WINE_LIGHT)
	fx.dust(Vector2(100, 280))
	for i in 180:
		fx.step(1.0 / 60.0)
	eq(fx.count(), 0, "effects are gone after 3 s")
	for i in 100:
		fx.puff(Vector2(100, 100))
	expect(fx.count() <= Effects.MAX_BITS, "effects are capped (%d)" % fx.count())
