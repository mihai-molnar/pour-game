class_name DrawLayer
extends Node2D
## Forwards _draw to a callable, so one vessel script can draw several layers
## (the body behind, the shaded liquid, the glass walls in front).

var draw_func: Callable


func _draw() -> void:
	if draw_func.is_valid():
		draw_func.call(self)
