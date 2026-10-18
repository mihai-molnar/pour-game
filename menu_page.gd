class_name MenuPage
extends Control
## One page of the shop's menu, printed on paper: a big condensed title, a
## small ornament, the round just played, the coin total in the corner like a
## running bar tab, two columns of `::SECTIONS::` holding MenuLines (and,
## for things still to unlock, lines blacked out with marker), and NEXT ROUND
## · SPACE at the foot. Built once for a tab; Shop builds a new one to change
## it (and turns the old one over).

const SIZE := Vector2(560, 344)
## The two columns' left edges and width, and the body's top and bottom.
const COLUMNS := [30.0, 296.0]
const COLUMN_W := 234.0
const BODY_TOP := 86.0
const BODY_BOTTOM := 294.0
const HEADER_H := 20.0
const SECTION_GAP := 10.0

## The real items on the page, in order.
var lines: Array[MenuLine] = []
## How many lines are blacked out.
var blacked_out := 0
var coins_label: Label
var round_line_label: Label
var next_button: Button

var _title: String
var _headers: Array = []  # [Rect2, text] — "" text = a blacked-out header
var _redacted: Array = []  # [Rect2 of the row, seed]


## `sections`: [{"header": String ("" = blacked out), "rows": [MenuLine or
## null (a blacked-out line), …]}, …]; `round_text` "" hides the round line.
func _init(title: String, sections: Array, round_text: String, coins: int) -> void:
	_title = title
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := _label(Rect2(0, 10, SIZE.x, 40), title, MenuArt.title_font(700, 4), 30, Palette.MENU_INK)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_line_label = _label(Rect2(0, 60, SIZE.x, 14), round_text, MenuArt.type_font(), 9, Color(Palette.MENU_INK, 0.75))
	round_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_line_label.visible = round_text != ""
	var coin := Hud.Coin.new()
	coin.size = Vector2(11, 11)
	coin.position = Vector2(SIZE.x - 84.0, 22.5)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin)
	coins_label = _label(Rect2(SIZE.x - 70.0, 17, 46, 22), str(coins), MenuArt.title_font(600), 15, Palette.MENU_INK)

	next_button = Button.new()
	next_button.text = "NEXT ROUND · SPACE"
	next_button.flat = true
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.size = Vector2(170, 20)
	next_button.position = Vector2((SIZE.x - 170.0) * 0.5, 302)
	next_button.add_theme_font_override("font", MenuArt.title_font(600, 2))
	next_button.add_theme_font_size_override("font_size", 12)
	next_button.add_theme_color_override("font_color", Color(Palette.MENU_INK, 0.85))
	next_button.add_theme_color_override("font_hover_color", Palette.STAMP)
	next_button.add_theme_color_override("font_pressed_color", Palette.STAMP)
	for state in ["normal", "hover", "pressed", "focus"]:
		next_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(next_button)
	_lay_out(sections)


func _label(rect: Rect2, text: String, font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l


## Section i starts in column i % 2 and runs on into the other if it overflows.
func _lay_out(sections: Array) -> void:
	var y := [BODY_TOP, BODY_TOP]
	var row_seed := 0
	for i in sections.size():
		var sec: Dictionary = sections[i]
		var col := i % 2
		var need := HEADER_H + MenuLine.SIZE.y
		if y[col] + need > BODY_BOTTOM and y[1 - col] + need <= BODY_BOTTOM:
			col = 1 - col
		_headers.append([Rect2(COLUMNS[col], y[col], COLUMN_W, HEADER_H), sec.header])
		y[col] += HEADER_H
		for row in sec.rows:
			if y[col] + MenuLine.SIZE.y > BODY_BOTTOM:
				col = 1 - col
			var at := Vector2(COLUMNS[col], y[col])
			if row == null:
				_redacted.append([Rect2(at, MenuLine.SIZE), 31 * i + row_seed])
				blacked_out += 1
			else:
				var line: MenuLine = row
				line.position = at
				add_child(line)
				lines.append(line)
			row_seed += 1
			y[col] += MenuLine.SIZE.y
		y[col] += SECTION_GAP


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	# A soft shadow under the page, the paper, its edges a little darker.
	for k in 4:
		draw_rect(Rect2(r.position + Vector2(2 + k, 3 + k), r.size), Color(0, 0, 0, 0.12))
	draw_rect(r, Palette.PAPER)
	var shade := Color(Palette.PAPER_SHADE, 0.75)
	var clear := Color(Palette.PAPER_SHADE, 0.0)
	var e := 16.0
	for strip: Array in [
		[Vector2(0, 0), Vector2(SIZE.x, 0), Vector2(SIZE.x - e, e), Vector2(e, e)],
		[Vector2(SIZE.x, 0), Vector2(SIZE.x, SIZE.y), Vector2(SIZE.x - e, SIZE.y - e), Vector2(SIZE.x - e, e)],
		[Vector2(SIZE.x, SIZE.y), Vector2(0, SIZE.y), Vector2(e, SIZE.y - e), Vector2(SIZE.x - e, SIZE.y - e)],
		[Vector2(0, SIZE.y), Vector2(0, 0), Vector2(e, e), Vector2(e, SIZE.y - e)],
	]:
		draw_polygon(PackedVector2Array(strip), PackedColorArray([shade, shade, clear, clear]))
	# The printed frame and the ornament under the title.
	draw_rect(r.grow(-9), Color(Palette.MENU_INK, 0.55), false, 0.8, true)
	draw_rect(r.grow(-12), Color(Palette.MENU_INK, 0.35), false, 0.4, true)
	MenuArt.draw_ornament(self, Vector2(SIZE.x * 0.5, 55), 120.0)
	draw_line(Vector2(SIZE.x * 0.5, BODY_TOP), Vector2(SIZE.x * 0.5, BODY_BOTTOM), Color(Palette.MENU_INK, 0.22), 0.6, true)
	var head := MenuArt.title_font(700, 2)
	for h in _headers:
		var box: Rect2 = h[0]
		if h[1] == "":
			MenuArt.draw_redacted(self, Rect2(box.position + Vector2(0, 3), Vector2(110, 10)), int(box.position.y) + 7)
		else:
			draw_string(head, box.position + Vector2(0, 13), "::%s::" % h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MENU_INK)
		draw_line(box.position + Vector2(0, 17), box.position + Vector2(COLUMN_W, 17), Color(Palette.MENU_INK, 0.25), 0.5, true)
	# Lines still to unlock: blacked out with marker, the price unknown.
	var rng := RandomNumberGenerator.new()
	var price := MenuArt.type_font(true)
	for row in _redacted:
		var box: Rect2 = row[0]
		rng.seed = row[1]
		MenuArt.draw_redacted(self, Rect2(box.position + Vector2(26, 2), Vector2(rng.randf_range(55, 110), 10)), row[1])
		MenuArt.draw_redacted(self, Rect2(box.position + Vector2(26, 16), Vector2(rng.randf_range(80, 170), 8)), row[1] + 101)
		draw_string(price, box.position + Vector2(COLUMN_W - 14, 12), "??", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Palette.MENU_INK, 0.45))
