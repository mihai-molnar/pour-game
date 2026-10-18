class_name MenuLine
extends Control
## One item on the shop's menu: a small ink drawing, the name in bold
## condensed capitals, a description under it in typewriter type, and on the
## right the price (the button: click it to buy), an OWNED stamp, or — on the
## MENU page — an ON/OFF checkbox. Lines that can't be afforded are printed
## faded. Built in code in HUD units; Shop decides what it shows and reacts to
## `activated` (the price clicked, or a menu line clicked anywhere).

signal activated

const SIZE := Vector2(234, 30)
## The drawing's box, centred on (11, 15).
const PICTURE := Rect2(-11, -12, 22, 24)

## The DrinkDef or GarnishDef this line sells or switches.
var item: Resource
var price_button: Button
## "OWNED", like a rubber stamp.
var badge: Label
var toggle_button: Button
## "At least one drink" under a checkbox that can't be unticked.
var note: Label
## Printed faded: can't be afforded.
var faded := false

var _toggles := false
var _on := false
var _coin: Control
var _box: DrawLayer
var _buy_hint: Label
var _underline: ColorRect


## `picture` draws the line's illustration into a canvas item, within PICTURE.
func _init(for_item: Resource, title: String, description: String, picture: Callable) -> void:
	item = for_item
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	var drawing := DrawLayer.new()
	drawing.position = Vector2(11, 15)
	drawing.draw_func = picture
	add_child(drawing)
	_label(Vector2(26, 0), title.to_upper(), MenuArt.title_font(600, 1), 12, Palette.MENU_INK)
	_label(Vector2(26, 15), description, MenuArt.type_font(), 9, Color(Palette.MENU_INK, 0.72))

	price_button = Button.new()
	price_button.flat = true
	price_button.focus_mode = Control.FOCUS_NONE
	price_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_button.size = Vector2(46, 16)
	price_button.position = Vector2(SIZE.x - 46.0, 0)
	price_button.add_theme_font_override("font", MenuArt.type_font(true))
	price_button.add_theme_font_size_override("font_size", 11)
	for c in ["font_color", "font_pressed_color", "font_disabled_color"]:
		price_button.add_theme_color_override(c, Palette.MENU_INK)
	price_button.add_theme_color_override("font_hover_color", Palette.STAMP)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		price_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	price_button.pressed.connect(activated.emit)
	price_button.mouse_entered.connect(_hover.bind(true))
	price_button.mouse_exited.connect(_hover.bind(false))
	add_child(price_button)
	_coin = Hud.Coin.new()
	_coin.size = Vector2(8, 8)
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_button.add_child(_coin)
	_underline = ColorRect.new()
	_underline.color = Palette.STAMP
	_underline.size = Vector2(30, 0.8)
	_underline.position = Vector2(SIZE.x - 32.0, 15)
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.visible = false
	add_child(_underline)
	_buy_hint = _label(Vector2(SIZE.x - 78.0, 2), "BUY", MenuArt.type_font(true), 9, Palette.STAMP)
	_buy_hint.size.x = 28.0
	_buy_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_buy_hint.visible = false

	badge = _label(Vector2(SIZE.x - 50.0, -3), "OWNED", MenuArt.title_font(700, 1), 10, Palette.STAMP)
	badge.size = Vector2(50, 15)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var stamp := StyleBoxFlat.new()
	stamp.draw_center = false
	stamp.set_border_width_all(1)
	stamp.border_color = Color(Palette.STAMP, 0.85)
	stamp.set_corner_radius_all(2)
	stamp.anti_aliasing = true
	badge.add_theme_stylebox_override("normal", stamp)
	badge.pivot_offset = badge.size * 0.5
	badge.rotation = deg_to_rad(-8.0)

	toggle_button = Button.new()
	toggle_button.flat = true
	toggle_button.focus_mode = Control.FOCUS_NONE
	toggle_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toggle_button.size = Vector2(46, 16)
	toggle_button.position = Vector2(SIZE.x - 46.0, 0)
	toggle_button.add_theme_font_override("font", MenuArt.type_font(true))
	toggle_button.add_theme_font_size_override("font_size", 10)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		toggle_button.add_theme_color_override(c, Palette.MENU_INK)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		toggle_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	toggle_button.pressed.connect(activated.emit)
	add_child(toggle_button)
	_box = DrawLayer.new()
	_box.draw_func = _draw_checkbox
	toggle_button.add_child(_box)
	note = _label(Vector2(SIZE.x - 110.0, 17), "At least one drink", MenuArt.type_font(), 9, Color(Palette.STAMP, 0.9))
	note.size.x = 110.0
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _label(pos: Vector2, text: String, font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(SIZE.x - pos.x - 50.0, font_size * 1.4)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l


## The price (faded and not clickable when it can't be afforded) or OWNED.
func show_price(price: int, state: Shop.CardState) -> void:
	_toggles = false
	var owned := state == Shop.CardState.OWNED
	price_button.text = str(price)
	_coin.position = Vector2(price_button.size.x - _text_width(price_button) - 11.0, 4)
	price_button.visible = not owned
	price_button.disabled = state == Shop.CardState.CANT_AFFORD
	badge.visible = owned
	toggle_button.visible = false
	note.visible = false
	faded = state == Shop.CardState.CANT_AFFORD
	modulate.a = 0.4 if faded else 1.0


## The menu page's checkbox: ON or OFF; `locked` = the last drink on.
func show_toggle(on: bool, locked: bool) -> void:
	_toggles = true
	_on = on
	price_button.visible = false
	badge.visible = false
	toggle_button.visible = true
	toggle_button.text = "ON" if on else "OFF"
	_box.position = Vector2(toggle_button.size.x - _text_width(toggle_button) - 9.0, 8)
	toggle_button.disabled = locked
	note.visible = locked
	faded = false
	modulate.a = 1.0 if on else 0.6


## The OWNED stamp thumps down, after buying.
func stamp() -> void:
	badge.scale = Vector2.ONE * 1.6
	badge.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(badge, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(badge, "modulate:a", 1.0, 0.1)


## Width of a button's text, so the coin or checkbox sits right before it.
static func _text_width(b: Button) -> float:
	return b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x


func _hover(on: bool) -> void:
	var live := on and not price_button.disabled
	_buy_hint.visible = live
	_underline.visible = live


func _draw_checkbox(ci: CanvasItem) -> void:
	var r := Rect2(-4.5, -4.5, 9, 9)
	ci.draw_rect(r, Palette.PAPER)
	ci.draw_rect(r, Palette.MENU_INK, false, 0.8)
	if _on:
		ci.draw_polyline(PackedVector2Array([Vector2(-2.8, 0.2), Vector2(-0.6, 2.6), Vector2(3.6, -3.4)]), Palette.MENU_INK, 1.3, true)


## A menu line switches when clicked anywhere on it.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if _toggles and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not toggle_button.disabled:
		accept_event()
		activated.emit()
