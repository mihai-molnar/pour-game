class_name Shop
extends CanvasLayer
## The shop between rounds, over the whole screen: a printed drinks menu on a
## dark table, with coloured index tabs down its right edge. UPGRADES sells
## the garnishes and upgrades of your drinks, DRINKS sells new drinks, MENU switches your
## drinks on and off for the next round; lines still to unlock are blacked
## out. Each page is a MenuPage of MenuLines; clicking a tab turns the page.
## Built in code and laid out by hand in the 640x360 HUD space, like Hud.
## Space or clicking NEXT ROUND emits next_pressed and hides it.

signal next_pressed

enum Tab { UPGRADES, DRINKS, MENU }
## NEEDS: another upgrade must be bought first (vintage after premium).
enum CardState { CAN_BUY, CANT_AFFORD, OWNED, NEEDS }

const TAB_NAMES := ["UPGRADES", "DRINKS", "MENU"]
const TAB_COLORS := [Palette.TAB_UPGRADES, Palette.TAB_DRINKS, Palette.TAB_MENU]
const SCREEN := Vector2(640, 360)
## Where the page lies; the tabs stick out of its right edge.
const PAGE_AT := Vector2(22, 8)
const TAB_SIZE := Vector2(30, 74)
const TAB_TOP := 44.0
const TAB_GAP := 8.0
## Blacked-out lines (things to unlock later): per drink on UPGRADES, and on DRINKS.
const UPGRADE_TEASERS := {&"beer": 2}
const DRINK_TEASERS := 4
## How long a page takes to turn.
const TURN_TIME := 0.35

## The tab on show; it stays the same between visits.
var tab := Tab.UPGRADES
## Seconds after open() during which Space and NEXT ROUND are ignored, so a
## stray press from the last serve doesn't skip the shop.
var input_lock := 0.5
## The page on show and its parts.
var page: MenuPage
var lines: Array[MenuLine] = []
var coins_label: Label
var round_line_label: Label
var next_button: Button

var _root: Control
var _paper: Control
var _tabs: Array[Button] = []
var _round_text := ""
var _opened_at_msec := 0
var _turn_tween: Tween
var _outgoing: MenuPage  # the page that goes once the turn is over
var _shadow: ColorRect  # cast by the turning page on the one underneath
var _curl: DrawLayer  # light and shade on the turning page


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var table := ColorRect.new()
	table.color = Palette.INK
	table.size = SCREEN
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(table)
	_paper = Control.new()
	_paper.position = PAGE_AT
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_paper)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.size = TAB_SIZE
		b.position = Vector2(PAGE_AT.x + MenuPage.SIZE.x - 3.0, PAGE_AT.y + TAB_TOP + i * (TAB_SIZE.y + TAB_GAP))
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var shape := DrawLayer.new()
		shape.draw_func = _draw_tab.bind(i, b)
		b.add_child(shape)
		b.mouse_entered.connect(shape.queue_redraw)
		b.mouse_exited.connect(shape.queue_redraw)
		b.pressed.connect(show_tab.bind(i))
		_root.add_child(b)
		_tabs.append(b)
	refresh()
	visible = false


## "ROUND 2 · 6 GLASSES · 4 PERFECT · BEST x1.6 · +134" — `stats` keys:
## served, perfects, best_mult, coins.
static func round_line(round_number: int, stats: Dictionary) -> String:
	return "ROUND %d · %d %s · %d PERFECT · BEST %s · %+d" % [round_number, stats.served,
		"GLASS" if stats.served == 1 else "GLASSES", stats.perfects, Hud.format_mult(stats.best_mult), stats.coins]


## Opens the shop; `round_text` is the round line ("" hides it).
func open(round_text := "") -> void:
	_round_text = round_text
	refresh()
	_opened_at_msec = Time.get_ticks_msec()
	visible = true


func close() -> void:
	visible = false


## Turns to tab `t`'s page: going to a later tab, the page on show folds
## over toward the spine on its left, revealing the new one underneath; going
## back, the earlier page turns back in over it. A click mid-turn finishes
## that turn first. (Without a turn while the shop is hidden.)
func show_tab(t: Tab) -> void:
	_finish_turn()
	if t == tab:
		return
	if not visible or page == null:
		tab = t
		refresh()
		return
	var forward := t > tab
	var old := page
	tab = t
	_set_page(_build_page(tab))
	_outgoing = old
	var turning := old if forward else page
	if forward:
		_paper.move_child(page, old.get_index())
	_shadow = ColorRect.new()
	_shadow.color = Color(Palette.INK, 0.0)
	_shadow.size = MenuPage.SIZE
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.add_child(_shadow)
	_paper.move_child(_shadow, turning.get_index())
	_curl = DrawLayer.new()
	_curl.draw_func = _draw_curl
	turning.add_child(_curl)
	turning.pivot_offset = Vector2(0, MenuPage.SIZE.y * 0.5)
	var folded := Color(0.72, 0.7, 0.68)
	turning.scale.x = 1.0 if forward else 0.0
	turning.modulate = Color.WHITE if forward else folded
	_curl.modulate.a = 0.0 if forward else 1.0
	_turn_tween = create_tween().set_parallel()
	var easing := Tween.EASE_IN if forward else Tween.EASE_OUT
	_turn_tween.tween_property(turning, "scale:x", 0.0 if forward else 1.0, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(easing)
	_turn_tween.tween_property(turning, "modulate", folded if forward else Color.WHITE, TURN_TIME)
	_turn_tween.tween_property(_curl, "modulate:a", 1.0 if forward else 0.0, TURN_TIME)
	_shadow.color.a = 0.3 if forward else 0.0
	_turn_tween.tween_property(_shadow, "color:a", 0.0 if forward else 0.3, TURN_TIME)
	_turn_tween.chain().tween_callback(_end_turn)
	_arrange_tabs()


func is_turning() -> bool:
	return _turn_tween != null


## Finishes a turn at once (a tab clicked mid-turn, or a refresh).
func _finish_turn() -> void:
	if _turn_tween != null:
		_turn_tween.kill()
		_end_turn()


func _end_turn() -> void:
	_turn_tween = null
	if _outgoing != null:
		_outgoing.visible = false
		_outgoing.queue_free()
		_outgoing = null
	if _shadow != null:
		_shadow.queue_free()
		_shadow = null
	if _curl != null:
		_curl.queue_free()
		_curl = null
	page.scale = Vector2.ONE
	page.modulate = Color.WHITE


## Light and shade on a turning page: darker toward its turning edge, a bright
## rim right at it.
func _draw_curl(ci: CanvasItem) -> void:
	var w := MenuPage.SIZE.x
	var h := MenuPage.SIZE.y
	ci.draw_polygon(PackedVector2Array([Vector2(w * 0.4, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.4, h)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)]))
	ci.draw_rect(Rect2(w - 3.0, 0, 3.0, h), Color(Palette.WHITE, 0.5))


static func card_state(price: int, owned: bool, coins: int) -> CardState:
	if owned:
		return CardState.OWNED
	return CardState.CAN_BUY if coins >= price else CardState.CANT_AFFORD


## Whether a DrinkDef, GarnishDef or UpgradeDef can be bought now.
func state_of(item: Resource) -> CardState:
	if item is GarnishDef:
		return card_state(item.price, GameState.owns_garnish(item), GameState.coins)
	if item is UpgradeDef:
		var u := item as UpgradeDef
		if not GameState.owns_upgrade(u) and u.replaces != null and not GameState.owns_upgrade(u.replaces):
			return CardState.NEEDS
		return card_state(u.price, GameState.owns_upgrade(u), GameState.coins)
	return card_state(item.price, GameState.owns_drink(item), GameState.coins)


## Buys a DrinkDef, GarnishDef or UpgradeDef; true if it was bought (coins spent).
func buy(item: Resource) -> bool:
	var bought: bool
	if item is GarnishDef:
		bought = GameState.buy_garnish(item)
	elif item is UpgradeDef:
		bought = GameState.buy_upgrade(item)
	else:
		bought = GameState.buy_drink(item)
	refresh()
	if bought:
		for line in lines:
			if line.item == item:
				line.stamp()
	return bought


## Switches an owned drink on or off for the next round; false when refused
## (the last drink on stays on).
func toggle(d: DrinkDef) -> bool:
	var ok := GameState.set_on_menu(d, not GameState.menu.has(d))
	refresh()
	return ok


func blacked_out_lines() -> int:
	return page.blacked_out


## Brings everything up to date with GameState: a fresh page for the current
## tab, and the tabs.
func refresh() -> void:
	_finish_turn()
	var old := page
	_set_page(_build_page(tab))
	if old != null:
		old.visible = false
		old.queue_free()  # not free(): this may run inside one of its buttons' signals
	_arrange_tabs()


func _set_page(p: MenuPage) -> void:
	page = p
	_paper.add_child(page)
	lines = page.lines
	coins_label = page.coins_label
	round_line_label = page.round_line_label
	next_button = page.next_button


func _build_page(t: Tab) -> MenuPage:
	var sections: Array = []
	match t:
		Tab.UPGRADES:
			for d: DrinkDef in GameState.DRINKS:
				if not GameState.is_unlocked(d):
					continue  # its section would give away the blacked-out drink
				var rows: Array = []
				if GameState.owns_drink(d):
					for g in d.garnishes:
						var line := _line(g, g.display_name, "%s · %s to add" % [g.description, OS.get_keycode_string(g.key).to_upper()], _garnish_picture(g))
						line.show_price(g.price, state_of(g))
						rows.append(line)
					for u in d.upgrades:
						var state := state_of(u)
						var line := _line(u, u.display_name, u.locked_description if state == CardState.NEEDS else u.description, _upgrade_picture(d, u))
						line.show_price(u.price, state)
						rows.append(line)
				else:
					rows.resize(d.garnishes.size() + d.upgrades.size())  # on sale once you own the drink: blacked out
				for i in UPGRADE_TEASERS.get(d.id, 0):
					rows.append(null)
				if not rows.is_empty():
					sections.append({"header": d.display_name.to_upper(), "rows": rows})
		Tab.DRINKS:
			var rows: Array = []
			for d: DrinkDef in GameState.DRINKS:
				if d.price > 0 and not GameState.is_unlocked(d):
					rows.append(null)  # not on sale yet: blacked out
				elif d.price > 0:
					var line := _line(d, d.display_name, _pays(d, []),
						func(ci: CanvasItem) -> void: MenuArt.draw_bottle(ci, d, Rect2(-7, -13, 14, 26)))
					line.show_price(d.price, state_of(d))
					rows.append(line)
			sections.append({"header": "BY THE GLASS", "rows": rows})
			var teasers: Array = []
			teasers.resize(DRINK_TEASERS)
			sections.append({"header": "", "rows": teasers})
		Tab.MENU:
			var rows: Array = []
			for d in GameState.owned_drinks:
				var line := _line(d, d.display_name, _pays(d, GameState.active_upgrades(d)),
					func(ci: CanvasItem) -> void: MenuArt.draw_glass(ci, d, MenuLine.PICTURE, d.fill_fraction))
				var on := GameState.menu.has(d)
				line.show_toggle(on, on and GameState.menu.size() == 1)
				rows.append(line)
			sections.append({"header": "NEXT ROUND SERVES", "rows": rows})
	var p := MenuPage.new(TAB_NAMES[t], sections, _round_text, GameState.coins)
	p.next_button.pressed.connect(_next)
	return p


func _line(item: Resource, title: String, description: String, picture: Callable) -> MenuLine:
	var line := MenuLine.new(item, title, description, picture)
	line.activated.connect(_on_line.bind(item))
	return line


func _on_line(item: Resource) -> void:
	if is_turning():
		return
	if tab == Tab.MENU:
		toggle(item)
	else:
		buy(item)


## "Pays 24 / 14 / 8": a drink's steps with `upgrades` (garnishes left out:
## they depend on the glass).
static func _pays(d: DrinkDef, upgrades: Array[UpgradeDef]) -> String:
	var no_garnish: Array[GarnishDef] = []
	var steps := []
	for base in [d.perfect_coins, d.good_coins, d.ok_coins]:
		steps.append(Scoring.garnished_coins(base, no_garnish, upgrades))
	return "Pays %d / %d / %d" % steps


func _upgrade_picture(d: DrinkDef, u: UpgradeDef) -> Callable:
	if u.fizz > 0.0:
		return func(ci: CanvasItem) -> void: MenuArt.draw_sparkling(ci, d, MenuLine.PICTURE)
	if u.refill_speed > 0.0:
		return func(ci: CanvasItem) -> void: MenuArt.draw_refill(ci, d, MenuLine.PICTURE)
	return func(ci: CanvasItem) -> void: MenuArt.draw_bottle(ci, d, Rect2(-7, -13, 14, 26), u.label_look)


func _garnish_picture(g: GarnishDef) -> Callable:
	if g.kind == GarnishDef.Kind.ICE:
		return func(ci: CanvasItem) -> void: MenuArt.draw_ice(ci, Vector2.ZERO, 18.0)
	return func(ci: CanvasItem) -> void: MenuArt.draw_lime(ci, Vector2.ZERO, 10.0)


## The current page's tab sits in front of the page, joined to it; the others
## behind it.
func _arrange_tabs() -> void:
	for i in _tabs.size():
		var b := _tabs[i]
		if i == tab:
			_root.move_child(b, -1)
		elif b.get_index() > _paper.get_index():
			_root.move_child(b, _paper.get_index())  # lands just behind the page
		b.get_child(0).queue_redraw()


## An index tab: a raised shape with sloped, rounded shoulders in its colour,
## its name running down it.
func _draw_tab(ci: CanvasItem, i: int, b: Button) -> void:
	var w := TAB_SIZE.x
	var h := TAB_SIZE.y
	var shape := VesselArt.rounded(PackedVector2Array([Vector2(0, 0), Vector2(w - 6, 6), Vector2(w, 14), Vector2(w, h - 14), Vector2(w - 6, h - 6), Vector2(0, h)]), 4.0)
	var color: Color = TAB_COLORS[i]
	if i != tab:
		color = color.darkened(0.18)
	if b.is_hovered():
		color = color.lightened(0.12)
	ci.draw_colored_polygon(shape, color)
	ci.draw_polyline(shape, Color(Palette.INK, 0.35), 0.6, true)
	var font := MenuArt.title_font(700, 2)
	var text: String = TAB_NAMES[i]
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	ci.draw_set_transform(Vector2(w * 0.5 + 0.5, h * 0.5), PI * 0.5)
	ci.draw_string(font, Vector2(-tw * 0.5, 3.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.PAPER)
	ci.draw_set_transform(Vector2.ZERO)


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
