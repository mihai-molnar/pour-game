class_name RoundSummary
extends CanvasLayer
## End-of-round screen: glasses, perfects, best streak, coins this round and
## total. Space or clicking NEXT ROUND emits next_pressed and hides it.

signal next_pressed

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const SCREEN_W := 640.0

## Seconds after show_results during which Space and the button are ignored, so
## a stray press from the last serve doesn't skip the results.
var input_lock := 0.5
var _shown_at_msec := 0

var _title: Label
var _body: Label
var _button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 8
	root.theme = theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(Palette.INK, 0.8)
	root.add_child(dim)
	_title = _centered_label(root, 96.0, Palette.GOLD, 16)
	_body = _centered_label(root, 136.0, Palette.FROST, 8)
	_button = Button.new()
	_button.text = "NEXT ROUND (SPACE)"
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_color_override("font_color", Palette.WHITE)
	_button.add_theme_color_override("font_hover_color", Palette.GOLD)
	_button.position = Vector2(SCREEN_W * 0.5 - 96.0, 248.0)
	_button.size = Vector2(192, 16)
	_button.pressed.connect(_next)
	root.add_child(_button)
	visible = false


func _centered_label(parent: Control, y: float, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.position = Vector2(0, y)
	l.size = Vector2(SCREEN_W, font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("line_spacing", 6)
	parent.add_child(l)
	return l


## `stats` keys: served, perfects, best_steps, coins.
func show_results(round_number: int, stats: Dictionary, total_coins: int) -> void:
	_title.text = "ROUND %d DONE" % round_number
	var rows := [
		["GLASSES", str(stats.served)],
		["PERFECT", str(stats.perfects)],
		["BEST STREAK", Hud.format_mult(stats.best_steps)],
		["COINS", "+%d" % stats.coins],
		["", ""],
		["TOTAL", str(total_coins)],
	]
	var lines: Array[String] = []
	for row in rows:
		lines.append("%-12s%6s" % row)
	_body.text = "\n".join(lines)
	_shown_at_msec = Time.get_ticks_msec()
	visible = true


func _locked() -> bool:
	return (Time.get_ticks_msec() - _shown_at_msec) / 1000.0 < input_lock


func hide_results() -> void:
	visible = false


func body_text() -> String:
	return _body.text


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if not _locked():
			_next()


func _next() -> void:
	if _locked():
		return
	visible = false
	next_pressed.emit()
