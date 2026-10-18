class_name Hud
extends CanvasLayer
## Everything drawn over the game: timer, coins, streak multiplier, result
## popups, banners, the key hint and the F1 debug readout, in soft dark pills
## set in Fredoka. Purely visual — it never drives game logic (its tweens only
## animate labels). Laid out by hand in the 640x360 HUD space (not with
## containers) so positions are known the moment they change.

const FONT_FILE := preload("res://fonts/Fredoka.ttf")
const SCREEN_W := 640.0
const SIZE := 14
const HINT_SIZE := 9
const POPUP_SIZE := 22
const BANNER_SIZE := 26
## Pills: top-left corner of the coin pill, their height, inner padding.
const PILL_AT := Vector2(10, 8)
const PILL_H := 22.0
const PILL_PAD := 8.0
## The timer, in the top-right corner (clear of the tipped pourers).
const TIMER_PILL := Rect2(570, 8, 60, 22)
## Gap between the coin count and the multiplier (a thin divider sits in it).
const STREAK_GAP := 13.0
## Where a grown multiplier pops up before flying to the coin counter, and how big.
const STREAK_POP_AT := Vector2(320, 64)
const STREAK_POP_SCALE := 3.0
## Popup colour per scoring step; anything else (MISS, SPILL) is red.
const BAND_COLORS := {
	Scoring.PERFECT: Palette.GOLD,
	Scoring.GOOD: Palette.GREEN,
	Scoring.GOOD_ENOUGH: Palette.FROST,
}

static var _fonts := {}

var root: Control
var timer_label: Label
var coins_label: Label
var streak_label: Label
## The big copy of a grown multiplier on its way to the counter (null otherwise).
var streak_flyer: Label
var banner_label: Label
var hint_label: Label
var debug_label: Label

var _coin_pill: Panel
var _divider: ColorRect
var _timer_pill: Panel
var _hint_pill: Panel
var _streak_pos := Vector2.ZERO  # right after the coin count; set_coins keeps it there
var _streak_mult := 1.0
var _streak_tween: Tween
var _shaking := false
var _banner_tween: Tween


## Fredoka at `weight` (it is a variable font; 300 light to 700 bold).
static func font(weight := 600) -> FontVariation:
	if not _fonts.has(weight):
		var f := FontVariation.new()
		f.base_font = FONT_FILE
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = f
	return _fonts[weight]


## The soft dark pill behind HUD text.
static func pill_style(radius := 11) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Palette.INK, 0.62)
	s.set_corner_radius_all(radius)
	s.border_width_top = 1
	s.border_color = Color(Palette.WHITE, 0.07)
	s.anti_aliasing = true
	return s


static func text_width(text: String, size: int, weight := 600) -> float:
	return font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = SIZE
	root.theme = theme
	add_child(root)
	_coin_pill = _pill(Rect2(PILL_AT, Vector2(80, PILL_H)))
	var coin := Coin.new()
	coin.position = PILL_AT + Vector2(PILL_PAD - 1.0, (PILL_H - 12.0) * 0.5)
	coin.size = Vector2(12, 12)
	root.add_child(coin)
	coins_label = make_label(Vector2(PILL_AT.x + PILL_PAD + 15.0, PILL_AT.y), Palette.WHITE)
	coins_label.size.y = PILL_H
	coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_divider = ColorRect.new()
	_divider.color = Color(Palette.WHITE, 0.15)
	_divider.size = Vector2(1, PILL_H - 10.0)
	root.add_child(_divider)
	streak_label = make_label(Vector2.ZERO, Palette.FROST)
	streak_label.size.y = PILL_H
	streak_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	streak_label.text = format_mult(1.0)
	_timer_pill = _pill(TIMER_PILL)
	timer_label = make_label(_timer_pill.position, Palette.WHITE)
	timer_label.size = _timer_pill.size
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label = make_label(Vector2(0, 100), Palette.WHITE)
	banner_label.size = Vector2(SCREEN_W, 70)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_override("font", font(700))
	banner_label.add_theme_font_size_override("font_size", BANNER_SIZE)
	banner_label.add_theme_color_override("font_outline_color", Color(Palette.INK, 0.85))
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.visible = false
	_hint_pill = _pill(Rect2(SCREEN_W - PILL_AT.x - 100.0, 360.0 - 8.0 - 17.0, 100.0, 17.0))
	hint_label = make_label(_hint_pill.position + Vector2(PILL_PAD, 0), Color(Palette.WHITE, 0.7))
	hint_label.size.y = 17.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_override("font", font(500))
	hint_label.add_theme_font_size_override("font_size", HINT_SIZE)
	debug_label = make_label(Vector2(12, 38), Palette.FROST)
	debug_label.add_theme_font_size_override("font_size", HINT_SIZE)
	debug_label.visible = false
	set_coins(0)


func _pill(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", pill_style())
	root.add_child(p)
	return p


func make_label(pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(Palette.INK, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 2)
	root.add_child(l)
	return l


## Seconds left as M:SS, rounding up (0:30 at the start, 0:00 only at the end).
static func format_time(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


static func format_mult(mult: float) -> String:
	var m := snappedf(mult, 0.1)
	return "x%d" % roundi(m) if is_equal_approx(m, roundf(m)) else "x%.1f" % m


## The INTRO banner: "ROUND N", plus a second line naming a drink bought in
## the shop since the last round.
static func round_banner(round_number: int, new_drink: DrinkDef) -> String:
	var text := "ROUND %d" % round_number
	if new_drink != null:
		text += "\nNEW DRINK: %s" % new_drink.display_name.to_upper()
	return text


func set_time(seconds: float) -> void:
	timer_label.text = format_time(seconds)
	timer_label.add_theme_color_override("font_color", Palette.RED if seconds <= 5.0 else Palette.WHITE)


func set_coins(total: int) -> void:
	coins_label.text = str(total)
	var count_end := coins_label.position.x + text_width(coins_label.text, SIZE)
	_streak_pos = Vector2(count_end + STREAK_GAP, PILL_AT.y)
	_divider.position = Vector2(count_end + STREAK_GAP * 0.5, PILL_AT.y + 5.0)
	if not _shaking:
		streak_label.position = _streak_pos
	_fit_coin_pill()


## Sizes the coin pill to what the multiplier label shows — during a "denied"
## shake that is still the old value.
func _fit_coin_pill() -> void:
	_coin_pill.size.x = _streak_pos.x + text_width(streak_label.text, SIZE) + PILL_PAD - PILL_AT.x


## The streak multiplier, right after the coin counter: dim at x1, gold above.
## A grown value pops up big in the middle of the screen, then flies to the
## counter and shrinks into place; a reset shakes the old value side to side
## (a "denied" shake) and turns it into x1. `animate` false sets it quietly (a
## new round starting).
func set_streak(mult: float, animate := true) -> void:
	if is_equal_approx(mult, _streak_mult) and animate:
		return
	var grew := mult > _streak_mult
	_streak_mult = mult
	_stop_streak_animation()
	if not animate:
		_land_streak()
		return
	_streak_tween = create_tween()
	if grew:
		var text := format_mult(mult)
		var size := Vector2(text_width(text, SIZE), PILL_H)
		streak_flyer = make_label(STREAK_POP_AT - size * 0.5, Palette.GOLD)
		streak_flyer.size = size
		streak_flyer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		streak_flyer.text = text
		streak_flyer.pivot_offset = size * 0.5
		streak_flyer.scale = Vector2.ZERO
		_streak_tween.tween_property(streak_flyer, "scale", Vector2.ONE * STREAK_POP_SCALE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_streak_tween.tween_interval(0.35)
		_streak_tween.tween_property(streak_flyer, "position", _streak_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		_streak_tween.parallel().tween_property(streak_flyer, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		# The streak broke (it only ever drops to x1): quick jolts that die down.
		_shaking = true
		for dx in [4.0, -3.5, 3.0, -2.0, 1.5, -1.0, 0.0]:
			_streak_tween.tween_property(streak_label, "position:x", _streak_pos.x + dx, 0.05)
	_streak_tween.tween_callback(_land_streak)


## Shows the current multiplier at the counter and clears any animation leftovers.
func _land_streak() -> void:
	_shaking = false
	if streak_flyer != null:
		streak_flyer.queue_free()
		streak_flyer = null
	streak_label.text = format_mult(_streak_mult)
	streak_label.position = _streak_pos
	streak_label.add_theme_color_override("font_color", Palette.GOLD if _streak_mult > 1.0 else Palette.FROST)
	_fit_coin_pill()


func _stop_streak_animation() -> void:
	if _streak_tween != null:
		_streak_tween.kill()
		_streak_tween = null
	if streak_flyer != null:
		streak_flyer.queue_free()
		streak_flyer = null
	_shaking = false
	streak_label.position = _streak_pos


## Floating coins won or lost, centred on `at` (a Scoring.score() result after
## Main's 0 floor); the colour carries the step: gold PERFECT, green GOOD, frost
## GOOD ENOUGH, red for a MISS ("0") or a spill ("-N", or "0" when there was
## nothing left to lose).
func popup(result: Dictionary, at: Vector2) -> Label:
	var coins: int = result.coins
	var text := "%+d" % coins if coins != 0 else "0"
	var color: Color = BAND_COLORS.get(result.band, Palette.RED)
	var label := make_label(at - Vector2(100, POPUP_SIZE), color)
	label.size = Vector2(200, POPUP_SIZE * 1.4)
	label.add_theme_font_override("font", font(700))
	label.add_theme_font_size_override("font_size", POPUP_SIZE)
	label.add_theme_color_override("font_outline_color", Color(Palette.INK, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * 0.6
	var tw := create_tween().set_parallel()
	tw.tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "position:y", label.position.y - 24.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(label.queue_free)
	return label


func show_banner(text: String, seconds: float) -> void:
	banner_label.text = text
	banner_label.visible = true
	banner_label.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(maxf(seconds - 0.3, 0.0))
	_banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_callback(banner_label.hide)


## The key hint, in a pill in the bottom-right corner (clear of the glass and the pourer).
func set_hint(text: String) -> void:
	hint_label.text = text
	var w := text_width(text, HINT_SIZE, 500) + PILL_PAD * 2.0
	_hint_pill.size.x = w
	_hint_pill.position.x = SCREEN_W - PILL_AT.x - w
	hint_label.position.x = _hint_pill.position.x
	hint_label.size.x = w


func toggle_debug() -> void:
	debug_label.visible = not debug_label.visible


func is_debug_visible() -> bool:
	return debug_label.visible


func set_debug(text: String) -> void:
	debug_label.text = text


## The coin icon in the coin pill: a small gold disc with a rim and a shine.
class Coin extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Palette.GOLD.darkened(0.35))
		draw_circle(c + Vector2(0, -0.4), r - 1.0, Palette.GOLD)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.35, Color(Palette.WHITE, 0.55))
