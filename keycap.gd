class_name Keycap
extends Control
## One keyboard key drawn in the HUD (KeyHints places them): a chunky rounded
## cap — a darker base showing as a thick bottom edge under a lighter top
## face — with a white glyph: DOWN's arrow (or, while the pourer refills, a
## ring filling up), SPACE's ␣, or a garnish's drawing with a small arrow in
## the corner. Purely visual: `shown` is the state, set at once; the pop in,
## shrink out and press are tweens. No words on the keys (spec).

enum Kind { DOWN, SPACE, GARNISH }

## Sizes in HUD units: the key's height (with its bottom edge), the arrow and
## space keys' widths, the bottom edge's depth and what's left of it pressed.
const KEY_H := 22.0
const ARROW_W := 22.0
const SPACE_W := 64.0
const DEPTH := 4.0
const PRESSED_DEPTH := 1.5
const RADIUS := 5
const POP_TIME := 0.15
const HIDE_TIME := 0.1
const PRESS_TIME := 0.08
## A key that does nothing for a moment (the pourer arriving or corked) is drawn this faint.
const DIM_ALPHA := 0.45
const RING_RADIUS := 5.5
const RING_WIDTH := 1.8
const GLYPH := Color(1, 1, 1, 0.92)

static var _base_style: StyleBoxFlat
static var _face_style: StyleBoxFlat

var kind: Kind
## GARNISH only: what the key adds (its `kind` picks the drawing, its `key` the corner arrow).
var garnish: GarnishDef
var shown := false
var pressed := false:
	set(v):
		if v != pressed:
			pressed = v
			queue_redraw()
var dim := false:
	set(v):
		dim = v
		self_modulate.a = DIM_ALPHA if v else 1.0
## DOWN only: < 0 shows the arrow, 0..1 the refill ring that far round.
var progress := -1.0:
	set(v):
		if v != progress:
			progress = v
			queue_redraw()

var _press_amount := 0.0:  # 0..1, a press's animation
	set(v):
		_press_amount = v
		queue_redraw()
var _show_tween: Tween
var _press_tween: Tween


func _init(k: Kind, g: GarnishDef = null) -> void:
	kind = k
	garnish = g
	size = Vector2(SPACE_W if k == Kind.SPACE else ARROW_W, KEY_H)
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows or hides the key: it pops in (a small overshoot) or shrinks away —
## after a press that is still playing.
func set_shown(on: bool) -> void:
	if on == shown:
		return
	shown = on
	if _show_tween != null:
		_show_tween.kill()
	_show_tween = create_tween().set_parallel()
	if on:
		visible = true
		scale = Vector2.ONE * 0.6
		modulate.a = 0.0
		_show_tween.tween_property(self, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_show_tween.tween_property(self, "modulate:a", 1.0, POP_TIME * 0.6)
	else:
		var wait := PRESS_TIME if _press_tween != null and _press_tween.is_running() else 0.0
		_show_tween.tween_property(self, "scale", Vector2.ONE * 0.6, HIDE_TIME).set_delay(wait).set_ease(Tween.EASE_IN)
		_show_tween.tween_property(self, "modulate:a", 0.0, HIDE_TIME).set_delay(wait)
		_show_tween.chain().tween_callback(hide)


## A quick press (SPACE, a garnish key): the top face goes down and comes up.
func press() -> void:
	if not shown:
		return
	if _press_tween != null:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "_press_amount", 1.0, PRESS_TIME * 0.5)
	_press_tween.tween_property(self, "_press_amount", 0.0, PRESS_TIME * 0.5)


func center() -> Vector2:
	return position + size * 0.5


## An arrow `size` long pointing along `dir`, centred on `center`: a shaft and
## a head (7 points).
static func arrow_polygon(center: Vector2, size: float, dir: Vector2) -> PackedVector2Array:
	var h := size * 0.5
	var head := size * 0.4
	var shaft := size * 0.15
	var pts := PackedVector2Array([Vector2(-h, -shaft), Vector2(0, -shaft), Vector2(0, -head), Vector2(h, 0),
		Vector2(0, head), Vector2(0, shaft), Vector2(-h, shaft)])
	return Transform2D(dir.angle(), center) * pts


## The space bar's ␣: a line `width` long with short upturned ends, centred on `center`.
static func space_symbol(center: Vector2, width: float) -> PackedVector2Array:
	var h := width * 0.2
	var w := width * 0.5
	return PackedVector2Array([center + Vector2(-w, -h * 0.5), center + Vector2(-w, h * 0.5),
		center + Vector2(w, h * 0.5), center + Vector2(w, -h * 0.5)])


static func _styles() -> void:
	if _base_style != null:
		return
	_base_style = StyleBoxFlat.new()
	_base_style.bg_color = Palette.INK
	_base_style.set_corner_radius_all(RADIUS)
	_base_style.border_width_bottom = 1
	_base_style.border_color = Color(Palette.WHITE, 0.05)
	_base_style.anti_aliasing = true
	_face_style = StyleBoxFlat.new()
	_face_style.bg_color = Palette.NAVY.lerp(Palette.SLATE, 0.55)
	_face_style.set_corner_radius_all(RADIUS - 1)
	_face_style.border_width_top = 1
	_face_style.border_color = Color(Palette.MIST, 0.35)
	_face_style.anti_aliasing = true


func _draw() -> void:
	_styles()
	var w := size.x
	VesselArt.draw_soft_ellipse(self, Vector2(w * 0.5, KEY_H + 0.5), Vector2(w * 0.62, 4.0), Color(Palette.INK, 0.6))
	draw_style_box(_base_style, Rect2(0, 0, w, KEY_H))
	var down := maxf(1.0 if pressed else 0.0, _press_amount) * (DEPTH - PRESSED_DEPTH)
	var face := Rect2(1.2, 0.8 + down, w - 2.4, KEY_H - DEPTH - 0.8)
	draw_style_box(_face_style, face)
	var c := face.get_center()
	match kind:
		Kind.DOWN:
			if progress < 0.0:
				draw_colored_polygon(arrow_polygon(c, 11.0, Vector2.DOWN), GLYPH)
			else:
				draw_arc(c, RING_RADIUS, 0.0, TAU, 32, Color(Palette.WHITE, 0.18), RING_WIDTH, true)
				if progress > 0.0:
					draw_arc(c, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * progress, maxi(3, ceili(32 * progress)), GLYPH, RING_WIDTH, true)
		Kind.SPACE:
			draw_polyline(space_symbol(c, 22.0), GLYPH, 1.6, true)
		Kind.GARNISH:
			_draw_garnish(c, face)


## The garnish's drawing in the middle of the face, a small arrow in its top-left corner.
func _draw_garnish(c: Vector2, face: Rect2) -> void:
	if garnish == null:
		return
	if garnish.kind == GarnishDef.Kind.ICE:
		GarnishArt.draw_ice_body(self, c + Vector2(1.5, 0.5), 10.0, 0.25)
		GarnishArt.draw_ice_edges(self, c + Vector2(1.5, 0.5), 10.0, 0.25)
	else:
		GarnishArt.draw_lime(self, c + Vector2(1.5, 3.5), 6.5, 0.0)
	var dir := Vector2.UP
	match garnish.key:
		KEY_LEFT:
			dir = Vector2.LEFT
		KEY_RIGHT:
			dir = Vector2.RIGHT
		KEY_DOWN:
			dir = Vector2.DOWN
	draw_colored_polygon(arrow_polygon(face.position + Vector2(3.6, 3.6), 5.0, dir), Color(Palette.WHITE, 0.7))
