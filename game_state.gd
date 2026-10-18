extends Node
## Session state (autoload `GameState`): coins, round progress, what the shop
## sold (drinks, garnishes), the menu of drinks the next round picks from, the
## seeded generator that picks each glass's drink, and `stats` — every tunable
## a future upgrade may change. Gameplay reads `stats` at point of use and
## never hard-codes a value that has a key. Nothing is saved yet (session only).

const BASE_STATS := {
	"round_duration": 30.0,
	# Scoring step limits in pixel rows between the settled surface and the line.
	"perfect_rows": 1,
	"good_rows": 3,
	"ok_rows": 6,
	# Streak multiplier: x1 until streak_start GOOD-or-better glasses in a row,
	# then 1 + streak_step per glass, capped at streak_max.
	"streak_start": 2,
	"streak_step": 0.1,
	"streak_max": 3.0,
	"coin_mult": 1.0,
	"pour_speed_mult": 1.0,
	"refill_time": 1.0,
}
const WATER := preload("res://drinks/water.tres")
const WINE := preload("res://drinks/wine.tres")
const BEER := preload("res://drinks/beer.tres")
## Every drink, in the shop's order. Water is free and owned from the start.
const DRINKS := [WATER, WINE, BEER]

var coins := 0
var round_number := 1
var owned_drinks: Array[DrinkDef] = [WATER]
## Ids of the garnishes bought.
var owned_garnishes: Array[StringName] = []
## The drinks switched on for the next round (never empty).
var menu: Array[DrinkDef] = [WATER]
## Drinks bought since the last round started: the next round opens with one.
var new_drinks: Array[DrinkDef] = []
var stats: Dictionary = BASE_STATS.duplicate()
## Picks each glass's drink. Seeded randomly at startup; --seed=N and the
## checks seed it so a run repeats exactly.
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## Back to a fresh session: 0 coins, round 1, only water, nothing bought, base
## stats. A `seed_value` >= 0 seeds the drink picks; a negative one picks a
## random seed.
func reset_session(seed_value := -1) -> void:
	coins = 0
	round_number = 1
	owned_drinks.clear()
	owned_drinks.append(WATER)
	owned_garnishes.clear()
	menu.clear()
	menu.append(WATER)
	new_drinks.clear()
	stats = BASE_STATS.duplicate()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func owns_drink(d: DrinkDef) -> bool:
	return owned_drinks.has(d)


func owns_garnish(g: GarnishDef) -> bool:
	return owned_garnishes.has(g.id)


## True once `d` is on sale: its unlock_round rounds have been played (in the
## shop round_number is the round just played; 0 under --shop before any round).
func is_unlocked(d: DrinkDef) -> bool:
	return d.unlock_round == 0 or round_number >= d.unlock_round


## Buys `d` if it is unlocked, isn't owned and there are enough coins: it is
## switched on for the next round, which opens with it. False when nothing was bought.
func buy_drink(d: DrinkDef) -> bool:
	if owns_drink(d) or not is_unlocked(d) or coins < d.price:
		return false
	coins -= d.price
	owned_drinks.append(d)
	menu.append(d)
	new_drinks.append(d)
	return true


## Buys `g` if it isn't owned and there are enough coins.
func buy_garnish(g: GarnishDef) -> bool:
	if owns_garnish(g) or coins < g.price:
		return false
	coins -= g.price
	owned_garnishes.append(g.id)
	return true


## Switches an owned drink on or off for the next round. False when refused:
## the drink isn't owned, or it is the last one on.
func set_on_menu(d: DrinkDef, on: bool) -> bool:
	if not owns_drink(d):
		return false
	if on:
		if not menu.has(d):
			menu.append(d)
		return true
	if menu.has(d) and menu.size() == 1:
		return false
	menu.erase(d)
	return true


## The drink the next round opens with: the first drink bought since the
## last round that is on the menu (null if none). Clears the list.
func take_new_drink() -> DrinkDef:
	var first: DrinkDef = null
	for d in new_drinks:
		if menu.has(d):
			first = d
			break
	new_drinks.clear()
	return first
