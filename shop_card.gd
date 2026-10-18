class_name ShopCard
extends Panel
## One item in the shop: a picture, its name, a line or two about it and, at
## the bottom, either its price and BUY, OWNED, or (on the menu) an ON/OFF
## toggle. Built in code in HUD units; Shop decides what it shows and reacts
## to `activated` (BUY pressed, or a menu card clicked).

signal activated

const SIZE := Vector2(150, 200)
## Where the picture is fitted (card-local).
const PICTURE := Rect2(10, 10, 130, 92)

## The DrinkDef or GarnishDef this card sells or switches.
var item: Resource
var buy_button: Button
var toggle_button: Button
## "OWNED".
var badge: Label
## "At least one drink" under a toggle that can't be switched off.
var note: Label

var _name: Label
var _lines: Label
var _price: Label
var _coin: Control
var _toggles := false
var _style: StyleBoxFlat
var _hover_style: StyleBoxFlat


func _init(for_item: Resource, title: String, lines: String, picture: Node2D, picture_box: Rect2) -> void:
	item = for_item
	size = SIZE
	pivot_offset = SIZE * 0.5
	_style = Hud.pill_style(12)
	_style.bg_color = Color(Palette.NAVY, 0.92)
	_style.border_width_top = 1
	_style.border_color = Color(Palette.WHITE, 0.1)
	_hover_style = _style.duplicate()
	_hover_style.bg_color = Color(Palette.SLATE, 0.95)
	add_theme_stylebox_override("panel", _style)
	mouse_entered.connect(func() -> void: add_theme_stylebox_override("panel", _hover_style))
	mouse_exited.connect(func() -> void: add_theme_stylebox_override("panel", _style))

	# Fit the picture (its own coordinates span picture_box) into PICTURE.
	var fit := minf(PICTURE.size.x / picture_box.size.x, PICTURE.size.y / picture_box.size.y)
	picture.scale = Vector2.ONE * fit
	picture.position = PICTURE.get_center() - picture_box.get_center() * fit
	add_child(picture)

	_name = _label(Vector2(0, 106), title, 14, Palette.WHITE, 700)
	_lines = _label(Vector2(0, 126), lines, 9, Palette.FROST, 500)
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.size = Vector2(SIZE.x - 16.0, 30.0)
	_lines.position.x = 8.0

	_coin = Hud.Coin.new()
	_coin.size = Vector2(11, 11)
	_coin.position = Vector2(20, 171.5)
	add_child(_coin)
	_price = _label(Vector2(34, 166), "", 13, Palette.GOLD, 700)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_price.size = Vector2(40, 22)
	buy_button = Button.new()
	buy_button.text = "BUY"
	buy_button.focus_mode = Control.FOCUS_NONE
	Shop.gold_button(buy_button, 10)
	buy_button.add_theme_font_size_override("font_size", 11)
	buy_button.size = Vector2(56, 22)
	buy_button.position = Vector2(SIZE.x - 56.0 - 16.0, 166)
	buy_button.pressed.connect(activated.emit)
	add_child(buy_button)

	badge = _label(Vector2(0, 166), "OWNED", 12, Palette.GREEN, 700)
	badge.size.y = 22.0

	toggle_button = Button.new()
	toggle_button.focus_mode = Control.FOCUS_NONE
	toggle_button.size = Vector2(70, 22)
	toggle_button.position = Vector2((SIZE.x - 70.0) * 0.5, 160)
	toggle_button.add_theme_font_override("font", Hud.font(700))
	toggle_button.add_theme_font_size_override("font_size", 11)
	toggle_button.pressed.connect(activated.emit)
	add_child(toggle_button)
	note = _label(Vector2(0, 184), "At least one drink", 9, Color(Palette.FROST, 0.8), 500)


func _label(pos: Vector2, text: String, font_size: int, color: Color, weight: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(SIZE.x, font_size * 1.5)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", Hud.font(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l


## Shows a price and BUY (greyed out when it can't be afforded) or OWNED.
func show_price(price: int, state: Shop.CardState) -> void:
	_toggles = false
	var owned := state == Shop.CardState.OWNED
	_price.text = str(price)
	_price.visible = not owned
	_coin.visible = not owned
	buy_button.visible = not owned
	buy_button.disabled = state == Shop.CardState.CANT_AFFORD
	badge.visible = owned
	toggle_button.visible = false
	note.visible = false
	modulate = Color(0.62, 0.62, 0.68) if state == Shop.CardState.CANT_AFFORD else Color.WHITE


## Shows the menu toggle: ON (gold) or OFF (dim); `locked` = the last drink on.
func show_toggle(on: bool, locked: bool) -> void:
	_toggles = true
	_price.visible = false
	_coin.visible = false
	buy_button.visible = false
	badge.visible = false
	toggle_button.visible = true
	toggle_button.text = "ON" if on else "OFF"
	toggle_button.disabled = locked
	note.visible = locked
	if on:
		Shop.gold_button(toggle_button, 10)
	else:
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			toggle_button.add_theme_color_override(c, Palette.FROST)
		for state in ["normal", "hover", "pressed"]:
			var s := Hud.pill_style(10)
			s.bg_color = Color(Palette.SLATE, 0.9 if state == "hover" else 0.6)
			toggle_button.add_theme_stylebox_override(state, s)
	modulate = Color.WHITE if on else Color(0.75, 0.75, 0.8)


## A menu card switches when clicked anywhere on it.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if _toggles and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not toggle_button.disabled:
		accept_event()
		activated.emit()


## A little pop, after buying.
func pop() -> void:
	scale = Vector2.ONE * 1.08
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
