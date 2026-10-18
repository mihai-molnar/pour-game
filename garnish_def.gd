class_name GarnishDef
extends Resource
## Something the player can add to a glass while serving it (bought once in
## the shop): ice falls in and takes up room, a lime wedge sits on the rim.
## A garnished glass pays `bonus` more at every scoring step. One .tres per
## garnish in res://garnishes/, listed on its drink's `garnishes`.

## ICE: falls into the glass and displaces liquid. RIM: sits on the rim.
enum Kind { ICE, RIM }

@export var id: StringName
@export var display_name := ""
## The shop card's line, e.g. "Water pays +20%".
@export var description := ""
@export var price := 10
## The share added to each step's coins; the bonuses on a glass add up.
@export_range(0.0, 2.0) var bonus := 0.2
@export var kind := Kind.ICE
## The (physical) key that adds it.
@export var key: Key = KEY_NONE

@export_group("Ice")
## Side of one cube (world px).
@export var cube_size := 8.5
@export var cube_count := 3
## How much of a floating cube is under the surface (real ice: about 90 %).
@export_range(0.5, 1.0) var float_share := 0.9
