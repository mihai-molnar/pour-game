extends Node
## Session state (autoload `GameState`): coins, round progress, owned drinks,
## and `stats` — every tunable a future upgrade may change. Gameplay reads
## `stats` at point of use and never hard-codes a value that has a key.
## Nothing is saved yet (session only).

const BASE_STATS := {
	"round_duration": 30.0,
	"perfect_tol": 0.03,
	"good_tol": 0.10,
	"coin_mult": 1.0,
	"pour_speed_mult": 1.0,
	"refill_time": 1.0,
}

var coins := 0
var round_number := 1
var owned_drinks: Array[DrinkDef] = [preload("res://drinks/water.tres")]
var stats: Dictionary = BASE_STATS.duplicate()
