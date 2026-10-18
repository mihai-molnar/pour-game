extends CheckBase
## Checks the camera framing: arriving vessels start off-screen, every vessel
## fits the view at rest and at its common pouring tilts without passing behind
## a HUD pill (a pourer's third glass, tipped further, may), the counter edge
## shows, the background covers the view, and world points map onto the
## screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=view

## Vessels stay this far inside the view (world px).
const MARGIN := 2.0
## The steepest tilt past rest (°) a pourer reaches on its first two glasses
## from full (measured with the autopilot: pitcher 48° then up to 68°, bottle
## up to 54°); the third glass from a pourer may tip further.
const COMMON_TILT := {&"water": 70.0, &"wine": 55.0}
## The widest the coin pill gets in play (4-digit coins and x2.5).
const COIN_PILL_W := 110.0


func run() -> void:
	var main: Main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	var view := Main.view_rect()
	near(view.size.x, 640.0 / Main.CAMERA_ZOOM, "view width follows the zoom", 0.01)
	near(view.get_center().x, Main.CAMERA_CENTER.x, "the view is centred on the camera", 0.01)
	var camera: Camera2D = main.get_node("Camera")
	eq([camera.position, camera.zoom], [Main.CAMERA_CENTER, Vector2.ONE * Main.CAMERA_ZOOM], "the camera node matches the constants")
	expect(Glass.OFFSCREEN_X + 26.0 < view.position.x, "an arriving glass starts fully left of the view")
	expect(Pourer.OFFSCREEN_X - 25.0 > view.end.x, "an arriving pourer starts fully right of the view")
	expect(view.end.y >= 286.0, "the counter's front edge is in view (bottom %.1f)" % view.end.y)

	var inner := view.grow(-MARGIN)
	var pills := [_rect_poly(Rect2(Hud.PILL_AT, Vector2(COIN_PILL_W, Hud.PILL_H))), _rect_poly(Hud.TIMER_PILL)]
	for d: DrinkDef in [GameState.WATER, GameState.ROUND_UNLOCKS[2]]:
		var glass := Transform2D(0.0, Main.GLASS_POS) * d.glass_outer
		expect(inner.encloses(_box(glass)) and not _behind_pill(main, glass, pills), "%s glass fits, clear of the HUD" % d.id)
		var lip := Main.GLASS_POS + d.pourer_offset
		var tilt := 0.0
		while tilt <= COMMON_TILT[d.id]:
			var at := Transform2D(-deg_to_rad(d.pourer_rest_deg + tilt), lip)
			var body := at * d.pourer_outer
			expect(inner.encloses(_box(body + at * d.pourer_handle)), "%s pourer at tilt %d fits the view" % [d.id, tilt])
			var hidden := _behind_pill(main, body, pills)
			if d.pourer_handle.size() >= 2:
				hidden = hidden or _behind_pill(main, at * d.pourer_handle, pills)
			expect(not hidden, "%s pourer at tilt %d stays clear of the HUD pills" % [d.id, tilt])
			tilt += 2.0

	var bg: Sprite2D = main.get_node("Background")
	var bg_rect := Rect2(bg.position, bg.texture.get_size() * bg.scale)
	expect(bg_rect.encloses(view.grow(1.0)), "the background covers the whole view (%s vs %s)" % [bg_rect, view])
	expect(bg_rect.position.distance_to(Main.BACKGROUND_RECT.position) < 0.5 and bg_rect.size.distance_to(Main.BACKGROUND_RECT.size) < 0.5,
		"the background sits on BACKGROUND_RECT (%s)" % bg_rect)

	var reflection: Node2D = main.get_node_or_null("Reflection")
	expect(reflection != null and reflection.clip_children == CanvasItem.CLIP_CHILDREN_ONLY, "the counter reflection is clipped to the counter")
	if reflection != null:
		expect(reflection.get_index() < main.get_node("Glass").get_index(), "...and drawn under the glass")
		var mirror: Node2D = reflection.get_node("Mirror")
		expect(mirror.modulate.a > 0.05 and mirror.modulate.a < 0.3, "...faint (alpha %.2f)" % mirror.modulate.a)
		mirror.queue_redraw()

	near(main.world_to_hud(Main.CAMERA_CENTER).distance_to(Vector2(320, 180)), 0.0, "the camera centre is the screen centre", 0.01)
	var rim := main.world_to_hud(Vector2(256, 206))
	expect(Rect2(0, 0, 640, 360).has_point(rim), "the glass rim maps onto the screen (%s)" % rim)


## True if the world polygon `p` (closed, so a handle polyline counts as its hull) overlaps a pill on screen.
func _behind_pill(main: Main, p: PackedVector2Array, pills: Array) -> bool:
	var on_screen := PackedVector2Array()
	for q in p:
		on_screen.append(main.world_to_hud(q))
	for pill: PackedVector2Array in pills:
		if not Geometry2D.intersect_polygons(on_screen, pill).is_empty():
			return true
	return false


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _box(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r
