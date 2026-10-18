class_name RoundSummary
extends CanvasLayer
## End-of-round screen: glasses, perfects, best streak, coins this round and
## total, on a rounded dark panel in the HUD's style. Space or clicking TO THE
## SHOP emits next_pressed (Main opens the shop) and hides it.

signal next_pressed

const SCREEN_W := 640.0
const PANEL := Rect2(200, 46, 240, 268)

## Seconds after show_results during which Space and the button are ignored, so
## a stray press from the last serve doesn't skip the results.
var input_lock := 0.5
var _shown_at_msec := 0

var _title: Label
var _names: Label
var _values: Label
var _button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = Hud.font()
	theme.default_font_size = 13
	root.theme = theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(Palette.INK, 0.55)
	root.add_child(dim)
	var panel := Panel.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	var style := Hud.pill_style(14)
	style.bg_color = Color(Palette.INK, 0.92)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	_title = _label(root, Rect2(PANEL.position.x, PANEL.position.y + 16.0, PANEL.size.x, 30.0), Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_override("font", Hud.font(700))
	_title.add_theme_font_size_override("font_size", 22)
	var rows := Rect2(PANEL.position.x + 28.0, PANEL.position.y + 58.0, PANEL.size.x - 56.0, 110.0)
	_names = _label(root, rows, Palette.FROST, HORIZONTAL_ALIGNMENT_LEFT)
	_values = _label(root, rows, Palette.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_button = Button.new()
	_button.text = "TO THE SHOP  (SPACE)"
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_override("font", Hud.font(700))
	_button.add_theme_color_override("font_color", Palette.INK)
	_button.add_theme_color_override("font_hover_color", Palette.INK)
	_button.add_theme_color_override("font_pressed_color", Palette.INK)
	for state in ["normal", "hover", "pressed"]:
		var b := Hud.pill_style(12)
		b.bg_color = Palette.GOLD.lightened(0.15) if state == "hover" else Palette.GOLD
		b.border_width_top = 0
		_button.add_theme_stylebox_override(state, b)
	_button.position = Vector2(SCREEN_W * 0.5 - 80.0, PANEL.end.y - 42.0)
	_button.size = Vector2(160, 26)
	_button.pressed.connect(_next)
	root.add_child(_button)
	visible = false


func _label(parent: Control, rect: Rect2, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 5)
	parent.add_child(l)
	return l


## `stats` keys: served, perfects, best_mult, coins.
func show_results(round_number: int, stats: Dictionary, total_coins: int) -> void:
	_title.text = "ROUND %d DONE" % round_number
	var rows := [
		["GLASSES", str(stats.served)],
		["PERFECT", str(stats.perfects)],
		["BEST STREAK", Hud.format_mult(stats.best_mult)],
		["COINS", "%+d" % stats.coins],
		["", ""],
		["TOTAL", str(total_coins)],
	]
	var names: Array[String] = []
	var values: Array[String] = []
	for row in rows:
		names.append(row[0])
		values.append(row[1])
	_names.text = "\n".join(names)
	_values.text = "\n".join(values)
	_shown_at_msec = Time.get_ticks_msec()
	visible = true


func _locked() -> bool:
	return (Time.get_ticks_msec() - _shown_at_msec) / 1000.0 < input_lock


func hide_results() -> void:
	visible = false


## The rows as text, one "NAME  value" per line.
func body_text() -> String:
	var names := _names.text.split("\n")
	var values := _values.text.split("\n")
	var lines: Array[String] = []
	for i in names.size():
		lines.append(("%s  %s" % [names[i], values[i]]).strip_edges())
	return "\n".join(lines)


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
