extends CheckBase
## Checks the camera framing: arriving vessels start off-screen, every vessel
## fits the view at rest and at its common pouring tilts (clear of the HUD row
## unless tipped far), the counter edge shows, and world points map onto the
## screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=view

## Vessels stay this far inside the view (world px).
const MARGIN := 2.0
## The HUD's top row (screen px); only a pourer tipped past HUD_TILT may reach into it.
const HUD_ROW := 22.0
const HUD_TILT := 60.0


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
	var below_hud := inner
	below_hud.position.y = view.position.y + HUD_ROW / Main.CAMERA_ZOOM
	below_hud.size.y = inner.end.y - below_hud.position.y
	for d: DrinkDef in [GameState.WATER, GameState.ROUND_UNLOCKS[2]]:
		var glass_box := _box(Transform2D(0.0, Main.GLASS_POS) * d.glass_outer)
		expect(below_hud.encloses(glass_box), "%s glass fits below the HUD row (%s)" % [d.id, glass_box])
		var lip := Main.GLASS_POS + d.pourer_offset
		var max_tilt := 85.0 if d.refill_style == DrinkDef.RefillStyle.IN_PLACE else 35.0
		var tilt := 0.0
		while tilt <= max_tilt:
			var shape := d.pourer_outer + d.pourer_handle
			var box := _box(Transform2D(-deg_to_rad(d.pourer_rest_deg + tilt), lip) * shape)
			var room := inner if tilt > HUD_TILT else below_hud
			expect(room.encloses(box), "%s pourer at tilt %d fits (%s in %s)" % [d.id, tilt, box, room])
			tilt += 5.0

	near(main.world_to_hud(Main.CAMERA_CENTER).distance_to(Vector2(320, 180)), 0.0, "the camera centre is the screen centre", 0.01)
	var rim := main.world_to_hud(Vector2(256, 206))
	expect(Rect2(0, 0, 640, 360).has_point(rim), "the glass rim maps onto the screen (%s)" % rim)


func _box(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r
