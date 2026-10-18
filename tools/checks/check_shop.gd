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
