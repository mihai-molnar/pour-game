class_name Shadows
extends Node2D
## Soft contact shadows on the counter under the glass (and the pourer when it
## is near the counter), drawn in world space beneath both so they don't lean
## or tilt with them. Visual only; redrawn every frame.

var glass: Glass


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if glass != null and glass.visible and glass.def != null:
		var foot := glass.outer_x_at(-0.5)
		VesselArt.draw_soft_ellipse(self, glass.position + Vector2(0, 0.3), Vector2((foot.y - foot.x) * 0.68, 2.4), Color(Palette.INK, 0.6))
