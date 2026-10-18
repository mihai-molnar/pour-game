class_name KeyHints
extends Control
## The keyboard keys over the bar, where each action happens
## (docs/superpowers/specs/2026-10-18-key-art-design.md): DOWN on the counter
## front under the pourer (a refill ring while it refills, dim while a new
## one arrives or is corked), SPACE under the glass whenever it has something
## in it (held down while a serve waits for the pour), and the garnish keys a
## press would add beside the glass — UP above it, LEFT on its left. Laid out
## in HUD units from world points; sync(main) reads Main's rules every tick
## and never changes game state.

## Gap (HUD units) between the counter lip and the top of the key row.
const ROW_GAP := 5.0
## UP's bottom edge sits this far above the spout's height (clear of the pourer,
## the stream and a result popup floating up from the glass).
const UP_GAP := 20.0
## LEFT's right edge sits this far left of the band bracket's spine, its top this far below the rim.
const LEFT_GAP := 7.0
const LEFT_DROP := 4.0

var down: Keycap
var space: Keycap
## Key → Keycap for garnish keys, made the first time a garnish on that key shows.
var garnish_caps := {}
## Where DOWN is headed (its centre x): under the current pourer; it glides there on a drink change.
var down_x := NAN

var _down_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	down = _cap(Keycap.Kind.DOWN)
	space = _cap(Keycap.Kind.SPACE)


func _cap(kind: Keycap.Kind, g: GarnishDef = null) -> Keycap:
	var cap := Keycap.new(kind, g)
	add_child(cap)
	return cap


## Shows, places and sets up every key from Main's state: nothing outside
## PLAYING / LAST_CALL or once the round is ending.
func sync(main: Main) -> void:
	var on := main.is_serving_phase() and main._shop_in < 0.0 and main.drink != null
	if main.drink != null:
		_place_down(slot(main, KEY_DOWN))
		space.position = slot(main, KEY_SPACE).position
	var pourer := main.pourer
	down.pressed = main.hold_down and not pourer.refilling
	down.dim = pourer.is_busy() and not pourer.refilling
	down.progress = pourer.refill_progress() if pourer.refilling else -1.0
	down.set_shown(on)
	space.pressed = main.is_serve_queued()
	space.set_shown(on and main.glass_has_drink())
	var want: Array[GarnishDef] = []
	if on:
		want = main.garnish_keys()
	for g in want:
		if not garnish_caps.has(g.key):
			garnish_caps[g.key] = _cap(Keycap.Kind.GARNISH, g)
		var cap: Keycap = garnish_caps[g.key]
		if cap.garnish != g:
			cap.garnish = g
			cap.queue_redraw()
		cap.position = slot(main, g.key).position
	for key: Key in garnish_caps:
		var cap: Keycap = garnish_caps[key]
		cap.set_shown(want.has(cap.garnish))


## Plays a garnish key's press (its key then vanishes as the garnish goes in).
func press_garnish(key: Key) -> void:
	if garnish_caps.has(key):
		(garnish_caps[key] as Keycap).press()


## Where the key for `key` goes for Main's current drink (HUD rect): DOWN
## under the pourer at rest and SPACE under the glass, both in the row below
## the counter lip; UP centred above the glass, over the spout's height; LEFT
## left of the band bracket, just below the rim. Empty for other keys.
func slot(main: Main, key: Key) -> Rect2:
	var d := main.drink
	var lip := Main.GLASS_POS + d.pourer_offset
	var row_top := main.world_to_hud(Vector2(0.0, Main.COUNTER_LIP_Y)).y + ROW_GAP
	var arrow := Vector2(Keycap.ARROW_W, Keycap.KEY_H)
	match key:
		KEY_DOWN:
			var x := main.world_to_hud(Pourer.rest_center(d, lip)).x
			return Rect2(Vector2(x - arrow.x * 0.5, row_top), arrow)
		KEY_SPACE:
			var x := main.world_to_hud(Main.GLASS_POS).x
			return Rect2(Vector2(x - Keycap.SPACE_W * 0.5, row_top), Vector2(Keycap.SPACE_W, Keycap.KEY_H))
		KEY_UP:
			var x := main.world_to_hud(Main.GLASS_POS).x
			var bottom := main.world_to_hud(lip).y - UP_GAP
			return Rect2(Vector2(x - arrow.x * 0.5, bottom - arrow.y), arrow)
		KEY_LEFT:
			var glass := main.glass
			var right := main.world_to_hud(Vector2(glass.global_position.x + glass.bracket_x(), 0.0)).x - LEFT_GAP
			var top := main.world_to_hud(Vector2(0.0, glass.rim_y_world())).y + LEFT_DROP
			return Rect2(Vector2(right - arrow.x, top), arrow)
	return Rect2()


func cap_rect(cap: Keycap) -> Rect2:
	return Rect2(cap.position, cap.size)


## Puts DOWN at `r`, gliding there over an arrival when it is on screen and its spot moved.
func _place_down(r: Rect2) -> void:
	var x := r.get_center().x
	down.position.y = r.position.y
	if x == down_x:
		return
	var glide := down.shown and not is_nan(down_x)
	down_x = x
	if _down_tween != null:
		_down_tween.kill()
	if glide:
		_down_tween = create_tween()
		_down_tween.tween_property(down, "position:x", r.position.x, Arrival.ARRIVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		down.position.x = r.position.x
