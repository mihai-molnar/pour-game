class_name VesselPreview
extends Node2D
## A drink's glass or pourer drawn exactly as in the game — its own Glass or
## Pourer node with Back / Liquid / Front layers and the liquid shader — for
## the shop's cards. It is set up once and never stepped: a glass holds `fill`
## of its capacity (no scoring marks), a pourer stands upright `fill` full.

enum Kind { GLASS, POURER }

const GLASS_LIQUID := preload("res://liquid_glass.tres")
const POURER_LIQUID := preload("res://liquid_pourer.tres")

var drink: DrinkDef
var kind: Kind
var fill: float


func _init(d: DrinkDef, k: Kind, f := 1.0) -> void:
	drink = d
	kind = k
	fill = f


## The vessel's outline box (local, unscaled), for fitting it on a card.
static func bounds(d: DrinkDef, k: Kind) -> Rect2:
	var pts := d.glass_outer if k == Kind.GLASS else d.pourer_outer + d.pourer_handle
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


func _ready() -> void:
	var vessel: Node2D = Glass.new() if kind == Kind.GLASS else Pourer.new()
	for layer_name in ["Back", "Liquid", "Front"]:
		var layer := DrawLayer.new()
		layer.name = layer_name
		if layer_name == "Liquid":
			# Its own copy: the vessel sets the drink's look on it.
			layer.material = (GLASS_LIQUID if kind == Kind.GLASS else POURER_LIQUID).duplicate()
		vessel.add_child(layer)
	add_child(vessel)
	if kind == Kind.GLASS:
		var glass := vessel as Glass
		glass.show_marks = false
		glass.setup(drink)
		glass.place(Vector2.ZERO)
		glass.receive(glass.global_position.x, fill * glass.capacity, 0.0)
		glass.step(1.0 / 60.0)
	else:
		var upright: DrinkDef = drink.duplicate()
		upright.pourer_rest_deg = 0.0
		var pourer := vessel as Pourer
		pourer.setup(upright)
		pourer.reset(fill)
	for layer in vessel.get_children():
		(layer as CanvasItem).queue_redraw()
