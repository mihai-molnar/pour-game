extends CheckBase
## Checks HUD formatting/state, the round summary screen and the shop screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=ui


func run() -> void:
	eq(Hud.format_time(30.0), "0:30", "30 s")
	eq(Hud.format_time(29.01), "0:30", "counts whole seconds up")
	eq(Hud.format_time(5.0), "0:05", "5 s")
	eq(Hud.format_time(0.2), "0:01", "the last fraction shows 0:01")
	eq(Hud.format_time(0.0), "0:00", "0 s")
	eq(Hud.format_time(-1.0), "0:00", "never negative")
	eq(Hud.format_time(75.0), "1:15", "minutes")
	eq(Hud.format_mult(1.0), "x1", "x1")
	eq(Hud.format_mult(1.2), "x1.2", "x1.2")
	eq(Hud.format_mult(1.0 + 0.1 * 3), "x1.3", "x1.3 despite float noise")
	eq(Hud.format_mult(2.0), "x2", "x2")
	eq(Hud.format_mult(3.0), "x3", "x3")
	eq(Hud.round_banner(1, null), "ROUND 1", "plain round banner")
	eq(Hud.round_banner(2, GameState.WINE), "ROUND 2\nNEW DRINK: WINE", "the unlock banner names the drink")

	var hud: Hud = load("res://hud.gd").new()
	add_child(hud)
	hud.set_time(4.0)
	eq(hud.timer_label.text, "0:04", "timer text")
	eq(hud.timer_label.get_theme_color("font_color"), Palette.RED, "timer is red in the last 5 s")
	hud.set_time(12.0)
	eq(hud.timer_label.get_theme_color("font_color"), Palette.WHITE, "timer is white otherwise")
	hud.set_coins(42)
	eq(hud.coins_label.text, "42", "coins label: the number (a coin icon sits before it)")
	var after_42 := hud.streak_label.position
	expect(after_42.x >= hud.coins_label.position.x + hud.coins_label.get_minimum_size().x,
		"the multiplier sits right after the coin counter (%s)" % after_42)
	hud.set_coins(1234)
	var after_1234 := hud.streak_label.position
	expect(after_1234.x > after_42.x and after_1234.y == after_42.y, "...and moves with it (%s)" % after_1234)
	hud.set_streak(1.0, false)
	eq([hud.streak_label.text, hud.streak_label.get_theme_color("font_color")], ["x1", Palette.FROST], "x1 is dim")
	hud.set_streak(1.2)
	eq(hud.streak_label.text, "x1", "a new multiplier doesn't show at the counter until it lands")
	var flyer: Label = hud.streak_flyer
	expect(flyer != null and flyer.text == "x1.2", "it pops up big in the middle of the screen first")
	if flyer != null:
		expect(absf(flyer.position.x + flyer.pivot_offset.x - 320.0) < 1.0, "...centred on the screen (x %.1f)" % (flyer.position.x + flyer.pivot_offset.x))
	hud._streak_tween.custom_step(5.0)
	eq([hud.streak_label.text, hud.streak_label.get_theme_color("font_color")], ["x1.2", Palette.GOLD], "...then lands next to the coins, gold")
	expect(hud.streak_flyer == null, "the big copy is gone once it has landed")
	hud.set_streak(1.0)
	eq(hud.streak_label.text, "x1.2", "a reset first shakes the old value")
	hud.set_coins(1234)  # Main refreshes the coins every tick, mid-shake too
	var pill_end: float = hud._coin_pill.position.x + hud._coin_pill.size.x
	expect(pill_end >= hud._streak_pos.x + Hud.text_width(hud.streak_label.text, Hud.SIZE),
		"the coin pill still holds the shaking old value (pill ends at %.1f)" % pill_end)
	hud._streak_tween.custom_step(5.0)
	eq([hud.streak_label.text, hud.streak_label.get_theme_color("font_color"), hud.streak_label.position],
		["x1", Palette.FROST, after_1234], "...then turns into a dim x1 back in place")
	hud.set_streak(1.5)
	hud.set_streak(1.0, false)
	eq([hud.streak_label.text, hud.streak_flyer], ["x1", null], "a quiet reset (new round) cancels any pop and shows x1")
	hud.show_banner("LAST CALL!", 1.5)
	eq(hud.banner_label.visible and hud.banner_label.text == "LAST CALL!", true, "banner shows")
	for c in [
		[{"band": Scoring.PERFECT, "coins": 15}, "+15", Palette.GOLD],
		[{"band": Scoring.GOOD, "coins": 7}, "+7", Palette.GREEN],
		[{"band": Scoring.GOOD_ENOUGH, "coins": 3}, "+3", Palette.FROST],
		[{"band": Scoring.MISS, "coins": 0}, "0", Palette.RED],
		[{"band": Scoring.SPILL, "coins": -6}, "-6", Palette.RED],
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
	summary.show_results(3, {"served": 7, "perfects": 2, "best_mult": 1.7, "coins": 55}, 120)
	eq(summary.visible, true, "show_results shows it")
	var text := summary.body_text()
	for want in ["GLASSES", "7", "PERFECT", "2", "x1.7", "+55", "120"]:
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
	eq(summary._button.text, "TO THE SHOP  (SPACE)", "the summary leads to the shop")

	var shop: Shop = load("res://shop.gd").new()
	add_child(shop)
	eq(shop.visible, false, "the shop starts hidden")
	shop.open()
	eq(shop.next_button.text, "NEXT ROUND  (SPACE)", "NEXT ROUND button")
	eq(shop.TAB_NAMES, ["UPGRADES", "DRINKS", "MENU"], "the shop's tabs")
	var left := [false]
	shop.next_pressed.connect(func() -> void: left[0] = true)
	shop._unhandled_input(space)
	shop._next()
	eq(left[0] == false and shop.visible, true, "Space and the button are ignored right after the shop opens")
	shop.input_lock = 0.0
	shop._unhandled_input(space)
	eq(left[0] and not shop.visible, true, "Space in the shop emits next_pressed and hides it")

	var fx: Effects = load("res://effects.gd").new()
	add_child(fx)
	fx.puff(Vector2(100, 100))
	expect(fx.count() >= 4 and fx.count() <= 6, "a puff is 4-6 pixels (%d)" % fx.count())
	fx.cork(Vector2(100, 100), Vector2(-100, -100), Palette.WINE_LIGHT)
	fx.dust(Vector2(100, 280))
	for i in 180:
		fx.step(1.0 / 60.0)
	eq(fx.count(), 0, "effects are gone after 3 s")
	fx.splash(Vector2(100, 200), Palette.WATER)
	expect(fx.count() >= 3 and fx.count() <= 6, "a splash is 3-6 droplets (%d)" % fx.count())
	for i in 180:
		fx.step(1.0 / 60.0)
	eq(fx.count(), 0, "...gone after 3 s")
	for i in 100:
		fx.puff(Vector2(100, 100))
	expect(fx.count() <= Effects.MAX_BITS, "effects are capped (%d)" % fx.count())
