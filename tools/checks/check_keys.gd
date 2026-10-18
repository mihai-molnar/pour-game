extends CheckBase
## Checks the keyboard keys drawn in the HUD (docs/superpowers/specs/2026-10-18-key-art-design.md):
## Main's rules for when SPACE and the garnish keys show and the DOWN hold;
## that the keys on screen follow them through whole rounds; the DOWN key's
## dim / pressed / refill-ring states; where the keys sit (on screen, the row
## below the counter lip, UP and LEFT clear of the glass, its bracket, the HUD
## pills, the pourers and the stream, and a drink's garnish keys clear of the
## LAST CALL banner and the result popup); the glyphs triangulate. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=keys

const DT := 1.0 / 60.0
const COMMON_TILT: Dictionary = preload("res://tools/checks/check_view.gd").COMMON_TILT
var main: Main


func run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.manual = true
	_space_rules()
	_garnish_rules()
	_hold_down_follows_tick()
	_keys_follow_the_rules()
	_down_key_states()
	_key_geometry()
	_glyphs_triangulate()


func _fresh(round_number := 1, seed_value := 1) -> void:
	GameState.reset_session(seed_value)
	GameState.round_number = round_number
	main.start_round()


func _run(seconds: float, hold := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		main.tick(DT, hold)
		t += DT


## Ticks with `hold` until `done` is true (at most `limit` s); true if `bad`
## was true on any tick along the way.
func _until(done: Callable, hold: bool, bad := func() -> bool: return false, limit := 6.0) -> bool:
	var seen := false
	var t := 0.0
	while not done.call() and t < limit:
		seen = seen or bad.call()
		main.tick(DT, hold)
		t += DT
	return seen


func _garnish_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for g in main.garnish_keys():
		ids.append(g.id)
	return ids


## SPACE shows whenever the glass has something in it (spec, revised after
## the first look: "only missing on an empty glass, nothing more").
func _space_rules() -> void:
	var keys: KeyHints = main.hud.keys
	var no_space := func() -> bool: return not main.glass_has_drink()
	_fresh()
	expect(not main.glass_has_drink(), "no SPACE during INTRO")
	_run(Main.INTRO_TIME + DT)
	expect(not main.glass_has_drink(), "no SPACE on an empty glass")
	_until(func() -> bool: return main.glass.volume >= main.glass.capacity * Main.ACTIVE_SHARE, true)
	expect(main.pourer.is_pouring() and main.glass_has_drink(), "SPACE mid-pour once something is in the glass")
	main.request_serve()
	main.tick(DT, true)
	expect(keys.space.shown and keys.space.pressed, "a serve queued mid-pour holds SPACE down")
	var gap := _until(main.is_swapping, false, no_space)
	expect(main.is_swapping() and not gap, "...and SPACE stays until the serve fires")
	_run(0.5)
	expect(not main.glass.is_arriving() and not main.glass_has_drink(), "the next glass lands empty: no SPACE")
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.tick(DT, false)
	expect(main.glass_has_drink() and keys.space.shown and not keys.space.pressed, "SPACE, up, on a filled glass")
	main.pourer.volume = 0.0
	main.tick(DT, false)
	expect(main.pourer.refilling, "the pourer refills")
	gap = _until(func() -> bool: return not main.pourer.refilling, false, no_space)
	expect(not gap, "SPACE stays through a refill")
	main.time_left = 0.01
	main.tick(DT, false)
	expect(main.phase == Main.Phase.LAST_CALL and main.glass_has_drink(), "SPACE in LAST CALL with liquid in")
	_until(func() -> bool: return main._shop_in >= 0.0, false)
	expect(main._shop_in >= 0.0 and not main.glass_has_drink(), "no SPACE once the last glass is served")
	_run(1.0)
	expect(main.phase == Main.Phase.SHOP and not main.glass_has_drink(), "no SPACE in the shop")


func _garnish_rules() -> void:
	_fresh()
	_run(Main.INTRO_TIME + DT)
	expect(main.garnish_keys().is_empty(), "no garnish keys before buying")
	GameState.coins = 25
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	GameState.buy_garnish(GameState.WATER.garnishes[1])
	GameState.round_number = 2
	main.start_round()
	expect(main.garnish_keys().is_empty(), "no garnish keys during INTRO")
	_run(Main.INTRO_TIME + DT)
	eq(_garnish_ids(), [&"ice", &"lime"], "both garnish keys once bought, on a landed glass")
	main.glass.receive(Main.GLASS_POS.x, main.glass.target * 0.5, 0.0)
	main.try_garnish(KEY_UP)
	eq(_garnish_ids(), [&"lime"], "ice in: only LEFT is left")
	expect(main.glass_has_drink(), "SPACE stays while the ice falls")
	_run(Glass.ICE_FALL_TIME + DT)
	main.try_garnish(KEY_LEFT)
	expect(main.garnish_keys().is_empty(), "both on: no garnish keys")
	_run(Glass.LIME_DROP_TIME + DT)
	main.request_serve()
	main.tick(DT, false)
	expect(main.glass.is_arriving() and main.garnish_keys().is_empty(), "no garnish keys while the next glass arrives")
	_run(0.5)
	eq(_garnish_ids(), [&"ice", &"lime"], "the next glass shows both again")
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	main._force_next = GameState.WINE
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.request_serve()
	main.tick(DT, false)
	_run(0.6)
	expect(main.drink == GameState.WINE and main.garnish_keys().is_empty(), "no garnish keys on wine")
	var drink := main.drink
	main.drink = null
	expect(main.garnish_keys().is_empty(), "no garnish keys without a drink")
	main.drink = drink


func _hold_down_follows_tick() -> void:
	_fresh()
	main.tick(DT, true)
	expect(not main.hold_down, "DOWN isn't held during INTRO")
	_run(Main.INTRO_TIME)
	main.tick(DT, true)
	expect(main.hold_down, "DOWN held while playing")
	main.tick(DT, false)
	expect(not main.hold_down, "...and released")
	main.open_shop()
	main.tick(DT, true)
	expect(not main.hold_down, "DOWN isn't held in the shop")


## A list of what the keys on screen got wrong this tick (empty when right).
func _key_mismatches() -> Array[String]:
	var keys: KeyHints = main.hud.keys
	var bad: Array[String] = []
	var on := main.is_serving_phase() and main._shop_in < 0.0
	if keys.down.shown != on:
		bad.append("DOWN %s in %s" % [keys.down.shown, Main.Phase.keys()[main.phase]])
	if keys.space.shown != main.glass_has_drink():
		bad.append("SPACE %s, glass_has_drink %s" % [keys.space.shown, main.glass_has_drink()])
	if keys.space.shown and keys.space.pressed != main.is_serve_queued():
		bad.append("SPACE pressed %s, serve queued %s" % [keys.space.pressed, main.is_serve_queued()])
	var want := main.garnish_keys()
	for g in want:
		var cap: Keycap = keys.garnish_caps.get(g.key)
		if cap == null or not cap.shown or cap.garnish != g:
			bad.append("%s key missing" % g.id)
	for key: Key in keys.garnish_caps:
		var cap: Keycap = keys.garnish_caps[key]
		if cap.shown and not want.has(cap.garnish):
			bad.append("%s key shown" % cap.garnish.id)
	return bad


func _keys_follow_the_rules() -> void:
	_fresh()
	GameState.coins = 200
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	GameState.buy_garnish(GameState.WATER.garnishes[1])
	GameState.buy_drink(GameState.WINE)
	GameState.take_new_drink()
	var pilot := Autopilot.new()
	var bad: Array[String] = []
	var ticks := 0
	var refilled := false
	var garnished := false
	while main.phase != Main.Phase.SHOP and ticks < 60 * 45:
		var d := pilot.decide(main)
		for k in d.keys:
			garnished = main.try_garnish(k) or garnished
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		refilled = refilled or main.pourer.refilling
		for m in _key_mismatches():
			if bad.size() < 5:
				bad.append("t=%.2f %s" % [ticks * DT, m])
		ticks += 1
	expect(main.phase == Main.Phase.SHOP and refilled and garnished, "the round covered garnishes, a refill and the shop")
	main.tick(DT, false)
	main.next_round()
	for i in 30:
		main.tick(DT, false)
		for m in _key_mismatches():
			if bad.size() < 5:
				bad.append("next INTRO %s" % m)
	expect(bad.is_empty(), "the keys on screen follow the rules on every tick %s" % [bad])


func _down_key_states() -> void:
	var keys: KeyHints = main.hud.keys
	_fresh()
	_run(Main.INTRO_TIME + DT)
	main.tick(DT, true)
	expect(keys.down.pressed, "DOWN shows pressed while held")
	main.tick(DT, false)
	expect(not keys.down.pressed, "...and up when released")
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	main._force_next = GameState.WINE
	main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
	main.request_serve()
	main.tick(DT, false)
	var dim := false
	var ring := false
	var t := 0.0
	while (main.pourer.is_arriving() or main.pourer.corked) and t < 2.0:
		dim = dim or keys.down.dim
		ring = ring or keys.down.progress >= 0.0
		main.tick(DT, false)
		t += DT
	expect(dim and not ring, "DOWN dims (no ring) while the new bottle arrives and is uncorked")
	expect(not keys.down.dim, "...and lights up once it is ready")
	var want := main.world_to_hud(Pourer.rest_center(GameState.WINE, Main.GLASS_POS + GameState.WINE.pourer_offset)).x
	expect(absf(keys.down_x - want) < 0.01, "DOWN moves under the bottle (%.1f vs %.1f)" % [keys.down_x, want])
	for d: DrinkDef in [GameState.WINE, GameState.WATER]:
		if main.drink != d:
			main._force_next = d
			main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
			main.request_serve()
			main.tick(DT, false)
			_run(1.0)
		main.pourer.volume = 0.0
		main.tick(DT, false)
		var last := 0.0
		var rising := true
		t = 0.0
		while main.pourer.refilling and t < 5.0:
			rising = rising and keys.down.progress >= last
			last = keys.down.progress
			main.tick(DT, false)
			t += DT
		expect(rising and last >= 0.95, "%s: the refill ring fills (to %.2f)" % [d.id, last])
		expect(keys.down.progress < 0.0, "%s: the arrow is back after the refill" % d.id)


func _key_geometry() -> void:
	var keys: KeyHints = main.hud.keys
	_fresh()
	GameState.coins = 200
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	GameState.buy_garnish(GameState.WATER.garnishes[1])
	GameState.buy_drink(GameState.WINE)
	GameState.take_new_drink()
	_run(Main.INTRO_TIME + DT)
	var screen := Rect2(0, 0, 640, 360)
	var pills := [Rect2(Hud.PILL_AT, Vector2(110, Hud.PILL_H)), Hud.TIMER_PILL]
	for d: DrinkDef in [GameState.WATER, GameState.WINE]:
		if main.drink != d:
			main._force_next = d
			main.glass.receive(Main.GLASS_POS.x, main.glass.target, 0.0)
			main.request_serve()
			main.tick(DT, false)
			_run(1.0)
		var lip_y := main.world_to_hud(Vector2(0, Main.COUNTER_LIP_Y)).y
		var down := keys.slot(main, KEY_DOWN)
		var space := keys.slot(main, KEY_SPACE)
		var up := keys.slot(main, KEY_UP)
		var left := keys.slot(main, KEY_LEFT)
		for r: Rect2 in [down, space, up, left]:
			expect(screen.encloses(r), "%s: key %s on screen" % [d.id, r])
		expect(down.position.y >= lip_y and space.position.y >= lip_y, "%s: DOWN and SPACE sit below the counter lip" % d.id)
		expect(not down.intersects(space), "%s: DOWN and SPACE don't overlap (%s, %s)" % [d.id, down, space])
		var glass_poly := Transform2D(0.0, Main.GLASS_POS) * d.glass_outer
		var bracket := main.world_to_hud(Vector2(main.glass.global_position.x + main.glass.bracket_x(), 0)).x
		expect(left.end.x <= bracket - 4.0, "%s: LEFT clears the bracket (%.1f vs %.1f)" % [d.id, left.end.x, bracket])
		var lip := Main.GLASS_POS + d.pourer_offset
		var text_zones := [main.hud.banner_rect("LAST CALL!"), Hud.popup_zone(main.popup_at())]
		for g in d.garnishes:
			var r := keys.slot(main, g.key)
			for z: Rect2 in text_zones:
				expect(not r.intersects(z), "%s: the %s key clears the banner and the result popup (%s vs %s)" % [d.id, g.id, r, z])
		for r: Rect2 in [up, left]:
			expect(not _overlaps(glass_poly, r), "%s: %s clears the glass" % [d.id, r])
			for pill: Rect2 in pills:
				expect(not r.intersects(pill), "%s: %s clears the HUD pill %s" % [d.id, r, pill])
			var tilt := 0.0
			while tilt <= COMMON_TILT[d.id]:
				var at := Transform2D(-deg_to_rad(d.pourer_rest_deg + tilt), lip)
				var hit := _overlaps(at * d.pourer_outer, r)
				if d.pourer_handle.size() >= 2:
					hit = hit or _overlaps(at * d.pourer_handle, r)
				expect(not hit, "%s: %s clears the pourer at tilt %d" % [d.id, r, tilt])
				tilt += 2.0
		var pilot := Autopilot.new()
		var in_up := 0
		var t := 0.0
		while not main.is_swapping() and t < 15.0:
			var dec := pilot.decide(main)
			if dec.serve:
				main.request_serve()
			main.tick(DT, dec.hold)
			for p in main.stream._parcels:
				if up.has_point(main.world_to_hud(p.pos)):
					in_up += 1
			t += DT
		eq(in_up, 0, "%s: the stream never passes through the UP key" % d.id)
		_run(1.0)


func _glyphs_triangulate() -> void:
	for dir: Vector2 in [Vector2.DOWN, Vector2.UP, Vector2.LEFT]:
		var arrow := Keycap.arrow_polygon(Vector2(11, 11), 12.0, dir)
		expect(not Geometry2D.triangulate_polygon(arrow).is_empty(), "the %s arrow triangulates" % dir)
	eq(Keycap.space_symbol(Vector2(32, 9), 22.0).size(), 4, "the space symbol is a 4-point line")


## True if the world polygon `p` (closed, so a handle polyline counts as its hull) overlaps the HUD rect `r`.
func _overlaps(p: PackedVector2Array, r: Rect2) -> bool:
	var on_screen := PackedVector2Array()
	for q in p:
		on_screen.append(main.world_to_hud(q))
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return not Geometry2D.intersect_polygons(on_screen, box).is_empty()
