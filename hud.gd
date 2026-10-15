class_name Hud
extends CanvasLayer
## Everything drawn over the game: timer, coins, streak multiplier, result
## popups, banners, the key hint and the F1 debug readout. Purely visual — it
## never drives game logic (its tweens only animate labels).

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const SCREEN_W := 640.0

var root: Control
var timer_label: Label
var coins_label: Label
var streak_label: Label
var banner_label: Label
var hint_label: Label
var debug_label: Label

var _streak_pos := Vector2(184, 196)
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


static func format_mult(steps: int) -> String:
	var m := Scoring.multiplier(steps)
	return "x%d" % int(m) if m == floorf(m) else "x%.1f" % m


func set_time(seconds: float) -> void:
	timer_label.text = format_time(seconds)
	timer_label.add_theme_color_override("font_color", Palette.RED if seconds <= 5.0 else Palette.WHITE)


func set_coins(total: int) -> void:
	coins_label.text = "COINS %d" % total


func place_streak(pos: Vector2) -> void:
	_streak_pos = pos
	streak_label.position = pos


## Shows what the next glass pays; pops when it changes.
func set_streak(steps: int) -> void:
	var text := format_mult(steps)
	if text == streak_label.text:
		return
	streak_label.text = text
	streak_label.add_theme_color_override("font_color", Palette.GOLD if steps > 0 else Palette.FROST)
	streak_label.position = _streak_pos - Vector2(0, 4)
	create_tween().tween_property(streak_label, "position", _streak_pos, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Floating result text centred on `at` (a Scoring.score() result).
func popup(result: Dictionary, at: Vector2) -> void:
	var pct := roundi(result.error * 100.0)
	var text := "MISS %+d%%" % pct
	var color := Palette.RED
	if result.band == Scoring.PERFECT:
		text = "PERFECT! +%d" % result.coins
		color = Palette.GOLD
	elif result.band == Scoring.GOOD:
		text = "GOOD %+d%% +%d" % [pct, result.coins]
		color = Palette.GREEN
	elif result.band == Scoring.SPILL:
		text = "SPILLED!"
	var label := make_label(at - Vector2(100, 0), color)
	label.size = Vector2(200, 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	var tw := create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 24.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(label.queue_free)


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
