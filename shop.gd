class_name Shop
extends CanvasLayer
## The shop between rounds, over the whole screen: a liquor-shop background,
## the coin pill, three tabs and NEXT ROUND. UPGRADES sells the garnishes of
## the drinks you own, DRINKS sells new drinks, MENU switches your drinks on
## and off for the next round. Built in code and laid out by hand in the
## 640x360 HUD space, like Hud and RoundSummary. Space or clicking NEXT ROUND
## emits next_pressed and hides it.

signal next_pressed

enum Tab { UPGRADES, DRINKS, MENU }
enum CardState { CAN_BUY, CANT_AFFORD, OWNED }

const TAB_NAMES := ["UPGRADES", "DRINKS", "MENU"]
const BACKGROUND := preload("res://art/shop_background.png")
const SCREEN := Vector2(640, 360)
const TAB_SIZE := Vector2(84, 22)
const TAB_GAP := 6.0
## Where the current tab's cards go (tools/background/shop.html darkens it).
const PANEL := Rect2(40, 40, 560, 270)
const CARD_GAP := 16.0
## Panel-local y of the group headers and of the cards' tops.
const HEADER_Y := 12.0
const CARDS_Y := 40.0

## The tab on show; it stays the same between visits.
var tab := Tab.UPGRADES
## Seconds after open() during which Space and the button are ignored, so a
## stray press from the summary doesn't skip the shop.
var input_lock := 0.5
var coins_label: Label
var next_button: Button
## The current tab's cards, in order.
var cards: Array[ShopCard] = []

var _root: Control
var _coin_pill: Panel
var _tabs: Array[Button] = []
var _content: Control
var _page: Control
var _opened_at_msec := 0


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = Hud.font()
	theme.default_font_size = Hud.SIZE
	_root.theme = theme
	add_child(_root)
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = SCREEN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_coin_pill = Panel.new()
	_coin_pill.position = Hud.PILL_AT
	_coin_pill.size = Vector2(60, Hud.PILL_H)
	_coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_pill.add_theme_stylebox_override("panel", Hud.pill_style())
	_root.add_child(_coin_pill)
	var coin := Hud.Coin.new()
	coin.position = Hud.PILL_AT + Vector2(Hud.PILL_PAD - 1.0, (Hud.PILL_H - 12.0) * 0.5)
	coin.size = Vector2(12, 12)
	_root.add_child(coin)
	coins_label = Label.new()
	coins_label.position = Vector2(Hud.PILL_AT.x + Hud.PILL_PAD + 15.0, Hud.PILL_AT.y)
	coins_label.size.y = Hud.PILL_H
	coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coins_label.add_theme_color_override("font_color", Palette.WHITE)
	_root.add_child(coins_label)

	var row_w := TAB_SIZE.x * TAB_NAMES.size() + TAB_GAP * (TAB_NAMES.size() - 1)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.position = Vector2((SCREEN.x - row_w) * 0.5 + i * (TAB_SIZE.x + TAB_GAP), Hud.PILL_AT.y)
		b.size = TAB_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Hud.font(700))
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(show_tab.bind(i))
		_root.add_child(b)
		_tabs.append(b)

	var panel := Panel.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Hud.pill_style(14)
	style.bg_color = Color(Palette.INK, 0.72)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	_content = Control.new()
	_content.position = PANEL.position
	_content.size = PANEL.size
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)

	next_button = Button.new()
	next_button.text = "NEXT ROUND  (SPACE)"
	next_button.focus_mode = Control.FOCUS_NONE
	gold_button(next_button, 12)
	next_button.size = Vector2(160, 26)
	next_button.position = SCREEN - Vector2(Hud.PILL_AT.x, Hud.PILL_AT.y) - next_button.size
	next_button.pressed.connect(_next)
	_root.add_child(next_button)
	visible = false


## Styles `b` as a gold action pill (dimmed when disabled), like the summary's button.
static func gold_button(b: Button, radius: int) -> void:
	b.add_theme_font_override("font", Hud.font(700))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Palette.INK)
	b.add_theme_color_override("font_disabled_color", Color(Palette.INK, 0.6))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := Hud.pill_style(radius)
		s.border_width_top = 0
		match state:
			"hover": s.bg_color = Palette.GOLD.lightened(0.15)
			"disabled": s.bg_color = Color(Palette.STEEL, 0.6)
			_: s.bg_color = Palette.GOLD
		b.add_theme_stylebox_override(state, s)


func open() -> void:
	refresh()
	_opened_at_msec = Time.get_ticks_msec()
	visible = true


func close() -> void:
	visible = false


func show_tab(t: Tab) -> void:
	tab = t
	refresh()


static func card_state(price: int, owned: bool, coins: int) -> CardState:
	if owned:
		return CardState.OWNED
	return CardState.CAN_BUY if coins >= price else CardState.CANT_AFFORD


## Whether a DrinkDef or GarnishDef can be bought now.
func state_of(item: Resource) -> CardState:
	if item is GarnishDef:
		return card_state(item.price, GameState.owns_garnish(item), GameState.coins)
	return card_state(item.price, GameState.owns_drink(item), GameState.coins)


## Buys a DrinkDef or GarnishDef; true if it was bought (coins spent).
func buy(item: Resource) -> bool:
	var bought := GameState.buy_garnish(item) if item is GarnishDef else GameState.buy_drink(item)
	refresh()
	if bought:
		for c in cards:
			if c.item == item:
				c.pop()
	return bought


## Switches an owned drink on or off for the next round; false when refused
## (the last drink on stays on).
func toggle(d: DrinkDef) -> bool:
	var ok := GameState.set_on_menu(d, not GameState.menu.has(d))
	refresh()
	return ok


## Brings everything up to date with GameState: the coins, the tabs, the
## current tab's cards.
func refresh() -> void:
	coins_label.text = str(GameState.coins)
	_coin_pill.size.x = coins_label.position.x - Hud.PILL_AT.x + Hud.text_width(coins_label.text, Hud.SIZE) + Hud.PILL_PAD
	for i in _tabs.size():
		_style_tab(_tabs[i], i == tab)
	if _page != null:
		_page.visible = false
		_page.queue_free()  # not free(): this may run inside one of its buttons' signals
	_page = Control.new()
	_page.size = PANEL.size
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_page)
	cards.clear()
	var groups: Array = []  # [header, [cards]]
	match tab:
		Tab.UPGRADES:
			for d in GameState.owned_drinks:
				var group: Array[ShopCard] = []
				for g in d.garnishes:
					var lines := "%s\n%s to add" % [g.description, OS.get_keycode_string(g.key).to_upper()]
					var card := _card(g, g.display_name, lines, _garnish_picture(g))
					card.show_price(g.price, state_of(g))
					group.append(card)
				if not group.is_empty():
					groups.append([d.display_name.to_upper(), group])
		Tab.DRINKS:
			var group: Array[ShopCard] = []
			for d: DrinkDef in GameState.DRINKS:
				if d.price > 0:
					var lines := "Pays %d / %d / %d" % [d.perfect_coins, d.good_coins, d.ok_coins]
					var card := _card(d, d.display_name, lines, _vessel_picture(d, VesselPreview.Kind.POURER, 1.0))
					card.show_price(d.price, state_of(d))
					group.append(card)
			groups.append(["NEW DRINKS", group])
		Tab.MENU:
			var group: Array[ShopCard] = []
			for d in GameState.owned_drinks:
				var card := _card(d, d.display_name, "", _vessel_picture(d, VesselPreview.Kind.GLASS, d.fill_fraction))
				var on := GameState.menu.has(d)
				card.show_toggle(on, on and GameState.menu.size() == 1)
				group.append(card)
			groups.append(["NEXT ROUND SERVES", group])
	_lay_out(groups)


func _card(item: Resource, title: String, lines: String, picture: Array) -> ShopCard:
	var card := ShopCard.new(item, title, lines, picture[0], picture[1])
	card.activated.connect(_on_card.bind(item))
	cards.append(card)
	return card


func _on_card(item: Resource) -> void:
	if tab == Tab.MENU:
		toggle(item)
	else:
		buy(item)


## Puts the groups' cards in one centred row, each group's header above it.
func _lay_out(groups: Array) -> void:
	var total := 0
	for g in groups:
		total += g[1].size()
	var x := (PANEL.size.x - (total * ShopCard.SIZE.x + maxi(total - 1, 0) * CARD_GAP)) * 0.5
	for g in groups:
		var group: Array[ShopCard] = g[1]
		if group.is_empty():
			continue
		var start := x
		for card in group:
			card.position = Vector2(x, CARDS_Y)
			_page.add_child(card)
			x += ShopCard.SIZE.x + CARD_GAP
		var header := Label.new()
		header.text = g[0]
		header.position = Vector2(start, HEADER_Y)
		header.size = Vector2(x - CARD_GAP - start, 20)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_theme_font_override("font", Hud.font(700))
		header.add_theme_font_size_override("font_size", 12)
		header.add_theme_color_override("font_color", Palette.GOLD)
		_page.add_child(header)


## [picture node, its box]: the garnish drawn as in the game.
func _garnish_picture(g: GarnishDef) -> Array:
	var layer := DrawLayer.new()
	var polys: Array[PackedVector2Array] = []
	if g.kind == GarnishDef.Kind.ICE:
		var poses := [Vector3(-5.0, 3.0, -0.15), Vector3(5.2, 3.4, 0.12), Vector3(0.3, -5.6, 0.05)]
		layer.draw_func = func(ci: CanvasItem) -> void:
			for p: Vector3 in poses:
				GarnishArt.draw_ice_body(ci, Vector2(p.x, p.y), g.cube_size, p.z)
				GarnishArt.draw_ice_edges(ci, Vector2(p.x, p.y), g.cube_size, p.z)
		for p: Vector3 in poses:
			polys.append(GarnishArt.ice_outline(Vector2(p.x, p.y), g.cube_size, p.z))
	else:
		layer.draw_func = func(ci: CanvasItem) -> void:
			GarnishArt.draw_lime(ci, Vector2.ZERO, Glass.LIME_RADIUS, Glass.LIME_ANGLE)
		polys = GarnishArt.lime_polygons(Vector2.ZERO, Glass.LIME_RADIUS, Glass.LIME_ANGLE)
	var box := Rect2(polys[0][0], Vector2.ZERO)
	for poly in polys:
		for p in poly:
			box = box.expand(p)
	return [layer, box.grow(box.size.x * 0.35)]


## [picture node, its box]: the drink's glass or pourer as in the game.
func _vessel_picture(d: DrinkDef, kind: VesselPreview.Kind, fill: float) -> Array:
	return [VesselPreview.new(d, kind, fill), VesselPreview.bounds(d, kind).grow(4.0)]


func _style_tab(b: Button, active: bool) -> void:
	var text := Palette.INK if active else Palette.FROST
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, text)
	for state in ["normal", "hover", "pressed"]:
		var s := Hud.pill_style()
		if active:
			s.bg_color = Palette.GOLD
			s.border_width_top = 0
		elif state == "hover":
			s.bg_color = Color(Palette.SLATE, 0.85)
		b.add_theme_stylebox_override(state, s)


func _locked() -> bool:
	return (Time.get_ticks_msec() - _opened_at_msec) / 1000.0 < input_lock


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
