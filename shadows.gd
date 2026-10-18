class_name Shadows
extends Node2D
## Soft contact shadows on the counter under the glass (and the pourer when it
## is near the counter), drawn in world space beneath both so they don't lean
## or tilt with them. Visual only; redrawn every frame.

## The pourer's shadow fades out as its lowest point lifts this far above the counter (px).
const POURER_FADE := 45.0

var glass: Glass
var pourer: Pourer


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if glass != null and glass.visible and glass.def != null:
		var foot := glass.outer_x_at(-0.5)
		VesselArt.draw_soft_ellipse(self, glass.position + Vector2(0, 0.3), Vector2((foot.y - foot.x) * 0.68, 2.4), Color(Palette.INK, 0.6))
	if pourer != null and pourer.visible and pourer.def != null:
		var pts := pourer.transform * pourer.def.pourer_outer
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		var k := clampf(1.0 - (Main.GLASS_POS.y - box.end.y) / POURER_FADE, 0.0, 1.0)
		if k > 0.0:
			VesselArt.draw_soft_ellipse(self, Vector2(box.get_center().x, Main.GLASS_POS.y + 0.3), Vector2(box.size.x * 0.55, 2.4), Color(Palette.INK, 0.5 * k))
