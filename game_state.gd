extends Node
## Session state (autoload `GameState`): coins, round progress, owned drinks,
## the seeded generator that picks each glass's drink, and `stats` — every
## tunable a future upgrade may change. Gameplay reads `stats` at point of use
## and never hard-codes a value that has a key. Nothing is saved yet (session only).

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
## Drinks a round gives you when it starts — a stand-in for the slice 3 shop,
## which replaces this table.
const ROUND_UNLOCKS := {2: preload("res://drinks/wine.tres")}

var coins := 0
var round_number := 1
var owned_drinks: Array[DrinkDef] = [WATER]
var stats: Dictionary = BASE_STATS.duplicate()
## Picks each glass's drink. Seeded randomly at startup; --seed=N and the
## checks seed it so a run repeats exactly.
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## Back to a fresh session: 0 coins, round 1, only water, base stats. A
## `seed_value` >= 0 seeds the drink picks; a negative one picks a random seed.
func reset_session(seed_value := -1) -> void:
	coins = 0
	round_number = 1
	owned_drinks.clear()
	owned_drinks.append(WATER)
	stats = BASE_STATS.duplicate()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Adds the drink ROUND_UNLOCKS gives for round `n` and returns it; null when
## the round unlocks nothing or the drink is already owned.
func unlock_for_round(n: int) -> DrinkDef:
	var d: DrinkDef = ROUND_UNLOCKS.get(n)
	if d == null or owned_drinks.has(d):
		return null
	owned_drinks.append(d)
	return d
