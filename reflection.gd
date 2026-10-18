class_name Reflection
extends Node2D
## A faint mirror image of the glass and the pourer in the polished counter
## top, under both. This node draws the reflecting strip of counter as a mask
## (clip_children = CLIP_CHILDREN_ONLY in main.tscn); its Mirror child draws
## the vessels flipped about the counter line, faded by its modulate. Visual
## only; redrawn every frame.

## The strip of counter that reflects (world px): from where the vessels stand to the front lip.
const STRIP := Rect2(100, 280, 400, 3.5)

var glass: Glass
var pourer: Pourer

@onready var _mirror: Node2D = $Mirror


func _ready() -> void:
	_mirror.draw.connect(_draw_mirror)


func _process(_dt: float) -> void:
	_mirror.queue_redraw()


func _draw() -> void:
	draw_rect(STRIP, Color.WHITE)


func _draw_mirror() -> void:
	var flip := Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(0, 2.0 * STRIP.position.y))
	for v: Node2D in [glass, pourer]:
		if v != null and v.visible and v.get("def") != null:
			var drawn := v.transform * (v as Glass).frame() if v is Glass else v.transform
			_mirror.draw_set_transform_matrix(flip * drawn)
			v.draw_reflection(_mirror)
	_mirror.draw_set_transform_matrix(Transform2D.IDENTITY)
