extends CheckBase
## Checks purchases and the drink menu (GameState), and the shop screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=shop


func run() -> void:
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.WINE
	var ice: GarnishDef = water.garnishes[0]
	var lime: GarnishDef = water.garnishes[1]
	expect(not GameState.buy_garnish(ice) and GameState.coins == 0 and not GameState.owns_garnish(ice), "0 coins can't buy ice")
	GameState.coins = 25
	expect(GameState.buy_garnish(ice) and GameState.coins == 15 and GameState.owns_garnish(ice), "ice costs 10")
	expect(not GameState.buy_garnish(ice) and GameState.coins == 15, "ice can't be bought twice")
	expect(GameState.buy_garnish(lime) and GameState.coins == 0, "lime costs 15")
	GameState.coins = 79
	expect(not GameState.buy_drink(wine) and not GameState.owns_drink(wine), "79 coins can't buy wine")
	GameState.coins = 80
	expect(GameState.buy_drink(wine) and GameState.coins == 0, "wine costs 80")
	expect(GameState.owned_drinks.has(wine) and GameState.menu.has(wine) and GameState.new_drinks == [wine], "bought wine is owned, on the menu and new")
	expect(not GameState.buy_drink(water), "water is already owned")
	expect(GameState.set_on_menu(water, false) and GameState.menu == [wine], "water can go off while wine is on")
	expect(not GameState.set_on_menu(wine, false) and GameState.menu == [wine], "the last drink on the menu stays on")
	expect(GameState.set_on_menu(water, true) and GameState.menu.size() == 2, "water back on")
	expect(GameState.set_on_menu(wine, false) and GameState.set_on_menu(wine, true), "wine off and on again")
	eq(GameState.take_new_drink(), wine, "a new drink toggled off and on again still opens the next round")
	eq(GameState.take_new_drink(), null, "...once")
	GameState.reset_session(1)
	GameState.coins = 80
	GameState.buy_drink(wine)
	GameState.set_on_menu(wine, false)
	eq(GameState.take_new_drink(), null, "a new drink switched off doesn't open the round")
	expect(GameState.new_drinks.is_empty(), "...and is no longer new")
	expect(not GameState.set_on_menu(load("res://drinks/wine.tres").duplicate(), true), "an unowned drink can't go on the menu")
	GameState.reset_session(1)
	expect(GameState.owned_drinks == [water] and GameState.menu == [water] and GameState.owned_garnishes.is_empty() and GameState.new_drinks.is_empty(),
		"reset_session clears purchases and the menu")

	# The shop screen: a printed menu.
	eq([Shop.card_state(10, false, 9), Shop.card_state(10, false, 10), Shop.card_state(10, true, 0)],
		[Shop.CardState.CANT_AFFORD, Shop.CardState.CAN_BUY, Shop.CardState.OWNED], "line states")
	GameState.reset_session(1)
	GameState.coins = 5
	var shop: Shop = load("res://shop.gd").new()
	add_child(shop)
	shop.open()
	eq(shop.tab, Shop.Tab.UPGRADES, "the shop opens on UPGRADES the first time")
	eq(shop.lines.map(func(l: MenuLine) -> Resource: return l.item), [ice, lime], "UPGRADES: water's ice and lime")
	eq(shop.blacked_out_lines(), 5, "UPGRADES: 2 blacked-out water lines and 3 for wine")
	expect(shop.state_of(ice) == Shop.CardState.CANT_AFFORD and shop.lines[0].price_button.disabled and shop.lines[0].faded, "5 coins: ice is printed faded")
	GameState.coins = 20
	shop.open()
	expect(shop.state_of(ice) == Shop.CardState.CAN_BUY and not shop.lines[0].price_button.disabled, "coins earned since: reopening refreshes the lines")
	shop.lines[0].price_button.pressed.emit()
	shop.lines[0].price_button.pressed.emit()
	eq(GameState.coins, 10, "a double click on the price spends 10 once")
	expect(shop.state_of(ice) == Shop.CardState.OWNED and shop.lines[0].badge.visible and not shop.lines[0].price_button.visible, "ice shows OWNED")
	eq(shop.coins_label.text, "10", "the coin total follows")
	shop.show_tab(Shop.Tab.DRINKS)
	eq(shop.lines.map(func(l: MenuLine) -> Resource: return l.item), [wine], "DRINKS: wine")
	eq(shop.blacked_out_lines(), 5, "...then 5 drinks to come, blacked out")
	eq(shop.state_of(wine), Shop.CardState.CANT_AFFORD, "10 coins can't buy wine")
	GameState.coins = 80
	shop.show_tab(Shop.Tab.DRINKS)
	expect(shop.buy(wine) and GameState.menu.has(wine) and shop.state_of(wine) == Shop.CardState.OWNED, "wine bought, on the menu")
	shop.show_tab(Shop.Tab.MENU)
	eq(shop.lines.map(func(l: MenuLine) -> Resource: return l.item), [water, wine], "MENU: a line per owned drink")
	eq(shop.blacked_out_lines(), 0, "MENU: only what you own")
	expect(shop.page.get_child_count() >= shop.lines.size() and shop.lines[0].get_parent() == shop.page, "the lines sit on the page")
	expect(shop.toggle(water) and not GameState.menu.has(water), "water switched off")
	expect(not shop.toggle(wine) and shop.lines[1].toggle_button.disabled and shop.lines[1].note.visible, "the last drink on can't be switched off")
	var smallest := 99
	for line in shop.lines:
		for child in line.get_children():
			if child is Label or child is Button:
				smallest = mini(smallest, (child as Control).get_theme_font_size("font_size"))
	expect(smallest >= 9, "no menu text under 9 HUD units (smallest %d)" % smallest)
	shop.close()
	shop.open()
	eq(shop.tab, Shop.Tab.MENU, "the shop reopens on the last tab")
	shop.toggle(water)
	expect(GameState.menu.size() == 2, "water back on")
	# Page turns.
	GameState.coins = 999
	shop.open()
	shop.show_tab(Shop.Tab.UPGRADES)
	shop._finish_turn()
	shop.show_tab(Shop.Tab.DRINKS)
	expect(shop.is_turning() and shop.tab == Shop.Tab.DRINKS, "a tab click turns the page (the new page is underneath at once)")
	var coins_before := GameState.coins
	for line in shop.lines:
		line.price_button.pressed.emit()
	eq(GameState.coins, coins_before, "nothing can be bought mid-turn")
	shop.show_tab(Shop.Tab.MENU)
	expect(shop.is_turning() and shop.tab == Shop.Tab.MENU, "a tab clicked mid-turn finishes that turn and starts the next")
	shop._turn_tween.custom_step(Shop.TURN_TIME + 0.05)
	expect(not shop.is_turning(), "a turn takes TURN_TIME")
	shop.show_tab(Shop.Tab.UPGRADES)
	shop._turn_tween.custom_step(Shop.TURN_TIME + 0.05)
	expect(not shop.is_turning() and shop.tab == Shop.Tab.UPGRADES, "turning back works too")
	shop.close()
	shop.open()
	expect(not shop.is_turning(), "opening the shop doesn't turn a page")
	shop.free()

	# Menu art: printed-menu illustrations and marker bars, all drawable.
	var polys: Array[PackedVector2Array] = []
	polys.append_array(MenuArt.ice_polygons(Vector2.ZERO, 10.0))
	polys.append_array(GarnishArt.lime_polygons(Vector2.ZERO, 9.0, Glass.LIME_ANGLE))
	for d: DrinkDef in GameState.DRINKS:
		polys.append_array(MenuArt.glass_polygons(d, Rect2(0, 0, 20, 24), d.fill_fraction))
		polys.append_array(MenuArt.bottle_polygons(d, Rect2(0, 0, 14, 26)))
	for i in 12:
		polys.append(MenuArt.redacted_polygon(Rect2(0, 0, 60 + i * 9, 9), i))
	var bad := 0
	for p in polys:
		if p.size() >= 3 and Geometry2D.triangulate_polygon(p).is_empty():
			bad += 1
	eq(bad, 0, "every menu illustration and marker bar triangulates (%d shapes)" % polys.size())
	expect(MenuArt.redacted_polygon(Rect2(0, 0, 80, 9), 3) == MenuArt.redacted_polygon(Rect2(0, 0, 80, 9), 3), "a marker bar is the same every visit")
	expect(MenuArt.title_font() != null and MenuArt.type_font(true) != null, "the menu fonts load")
