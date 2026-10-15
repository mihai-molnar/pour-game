class_name Hud
extends CanvasLayer
## Everything drawn over the game: timer, coins, streak multiplier, result
## popups, banners, the key hint and the F1 debug readout. Purely visual — it
## never drives game logic (its tweens only animate labels).

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const SCREEN_W := 640.0
## Press Start 2P at 8 px is monospaced: every glyph is 8 px wide.
const CHAR_W := 8.0
## Where a grown multiplier pops up before flying to the coin counter, and how big.
const STREAK_POP_AT := Vector2(320, 64)
const STREAK_POP_SCALE := 4.0
## Popup colour per scoring step; anything else (MISS, SPILL) is red.
const BAND_COLORS := {
	Scoring.PERFECT: Palette.GOLD,
	Scoring.GOOD: Palette.GREEN,
	Scoring.GOOD_ENOUGH: Palette.FROST,
}

var root: Control
var timer_label: Label
var coins_label: Label
var streak_label: Label
## The big copy of a grown multiplier on its way to the counter (null otherwise).
var streak_flyer: Label
var banner_label: Label
var hint_label: Label
var debug_label: Label

var _streak_pos := Vector2(72, 8)  # right after "COINS 0"; set_coins keeps it there
var _streak_mult := 1.0
var _streak_tween: Tween
var _shaking := false
var _banner_tween: Tween


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 8
	root.theme = theme
	add_child(root)
	coins_label = make_label(Vector2(8, 8), Palette.GOLD)
	timer_label = make_label(Vector2(0, 8), Palette.WHITE)
	timer_label.size = Vector2(SCREEN_W, 8)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_label = make_label(_streak_pos, Palette.FROST)
	streak_label.text = format_mult(1.0)
	banner_label = make_label(Vector2(0, 112), Palette.WHITE)
	banner_label.size = Vector2(SCREEN_W, 16)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 16)
	banner_label.visible = false
	hint_label = make_label(Vector2(8, 344), Palette.FROST)
	debug_label = make_label(Vector2(8, 24), Palette.FROST)
	debug_label.visible = false


func make_label(pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Palette.INK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 4)
	root.add_child(l)
	return l


## Seconds left as M:SS, rounding up (0:30 at the start, 0:00 only at the end).
static func format_time(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


static func format_mult(mult: float) -> String:
	var m := snappedf(mult, 0.1)
	return "x%d" % roundi(m) if is_equal_approx(m, roundf(m)) else "x%.1f" % m


## The INTRO banner: "ROUND N", plus a second line naming a drink unlocked this round.
static func round_banner(round_number: int, unlocked: DrinkDef) -> String:
	var text := "ROUND %d" % round_number
	if unlocked != null:
		text += "\nNEW DRINK: %s" % unlocked.display_name.to_upper()
	return text


func set_time(seconds: float) -> void:
	timer_label.text = format_time(seconds)
	timer_label.add_theme_color_override("font_color", Palette.RED if seconds <= 5.0 else Palette.WHITE)


func set_coins(total: int) -> void:
	coins_label.text = "COINS %d" % total
	_streak_pos = coins_label.position + Vector2((coins_label.text.length() + 1) * CHAR_W, 0)
	if not _shaking:
		streak_label.position = _streak_pos


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
		var size := Vector2(text.length() * CHAR_W, CHAR_W)
		streak_flyer = make_label(STREAK_POP_AT - size * 0.5, Palette.GOLD)
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
	var label := make_label(at - Vector2(100, 0), color)
	label.size = Vector2(200, 8)
	label.add_theme_color_override("font_outline_color", Palette.INK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	var tw := create_tween().set_parallel()
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


func set_hint(text: String) -> void:
	hint_label.text = text


func toggle_debug() -> void:
	debug_label.visible = not debug_label.visible


func is_debug_visible() -> bool:
	return debug_label.visible


func set_debug(text: String) -> void:
	debug_label.text = text
