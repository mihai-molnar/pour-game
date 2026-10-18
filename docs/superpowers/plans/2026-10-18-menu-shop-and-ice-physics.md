# Menu Shop and Ice Physics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The round ends straight into the shop, which becomes a printed drinks menu with index tabs and page turns (blacked-out future items included), and the ice becomes two bigger cubes with visual physics.

**Architecture:** `Main` loses its SUMMARY phase and hands the round's numbers to `Shop.open()`. The shop draws a paper `MenuPage` (frame, title, sections, blacked-out lines) holding `MenuLine` controls for real items, with ink illustrations from a new `MenuArt` helper and two bundled OFL fonts; tabs are drawn buttons on the page's right edge; a tab click turns the page by scaling the old/new page about its left edge. The glass hands landed ice to a small visual-only rigid-body sim (`IcePhysics`); the displacement rule is untouched.

**Tech Stack:** Godot 4.5.1, GDScript, headless checks (`tools/run_check.gd`), fonts from github.com/google/fonts (OFL).

**Spec:** `docs/superpowers/specs/2026-10-18-menu-shop-and-ice-physics-design.md`

## Global Constraints

- Branch `feat/menu-shop` off `master`. `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`; checks: `"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=<name|all>`, judged by `check_<name>: OK` lines; `--import` after adding class_name scripts or assets.
- No change to prices, bonuses, buying / menu rules, scoring, round timing. `--sweep` and `--sweep=wine` byte-identical to `master`.
- Copy kept: `Water pays +20%`, `Water pays +30%`, `UP to add`, `LEFT to add`, `Pays 15 / 9 / 5`, `At least one drink`, tab names `UPGRADES` / `DRINKS` / `MENU` (also the page titles). New copy: `NEXT ROUND · SPACE`; round line `ROUND 2 · 6 GLASSES · 4 PERFECT · BEST x1.6 · +134` (`1 GLASS` when one); `OWNED`; `ON` / `OFF`; blacked-out price `??`.
- Ice: `cube_count` 2, `cube_size` 10.4; the rise at the water line stays 4–6 rows. Physics is visual only: `randf`, never `GameState.rng`.
- Shop Space lock stays 0.5 s; buttons `FOCUS_NONE`; HUD-space layout by hand in 640×360; no menu text under 9 units; colours via `Palette`.
- Fonts: Oswald (variable, titles/names/tabs/stamp) and Courier Prime Regular + Bold (descriptions/prices/round line), with their `OFL.txt`; Fredoka stays for the HUD.

## Review Focus

1. A Space pressed to serve the last glass lands in the freshly opened shop — the 0.5 s lock must swallow it (Task 1, check_round).
2. Clicking a price or tab while a page is mid-turn — must not buy on the outgoing page; a tab click finishes the turn and starts the next (Task 5, check_shop).
3. Ice bouncing into the corner where the wall meets the floor, or both cubes landing on top of each other — they must stay inside the glass and separate (Task 2, check_glass).
4. Reopening the shop after a round with more coins — faded lines must become buyable (Task 4, check_shop).
5. The shop opened by `--shop` before any round — no round line, no crash (Task 1, check_ui / check_round).

---

### Task 1: Round end opens the shop (no report)

**Files:**
- Delete: `round_summary.gd`, `round_summary.gd.uid`, `round_summary.tscn`
- Modify: `main.gd`, `main.tscn` (remove the RoundSummary node and its ext_resource; update `load_steps`), `shop.gd` (round line), `autopilot.gd` (doc only)
- Test: `tools/checks/check_round.gd`, `tools/checks/check_ui.gd`

**Interfaces:**
- Produces: `Main.Phase { INTRO, PLAYING, LAST_CALL, SHOP }`; `Main.SHOP_DELAY := 0.35` (was `SUMMARY_DELAY`); `Main.open_shop() -> void` (enters SHOP from any phase, hides the world, opens the shop with the round line; used by round end and `--shop`); `Shop.open(round_text := "") -> void`; `static Shop.round_line(round_number: int, stats: Dictionary) -> String`; `Shop.round_line_label: Label`.

- [ ] **Step 0: Branch and record the sweep baseline**

```bash
git checkout -b feat/menu-shop
S=/private/tmp/claude-501/-Users-mihai-Godot-games-pour-prototype/1786fe62-e838-46d8-a56e-d08f69bb827e/scratchpad
"$GODOT" --headless --path . -- --sweep > $S/sweep2_water_before.txt 2>&1
"$GODOT" --headless --path . -- --sweep=wine > $S/sweep2_wine_before.txt 2>&1
```

- [ ] **Step 1: Write the failing tests**

`check_round.gd`: every `Main.Phase.SUMMARY` becomes `Main.Phase.SHOP`, `Main.SUMMARY_DELAY` becomes `Main.SHOP_DELAY`, `main.summary.visible` becomes `main.shop.visible`; drop the `main.open_shop()` calls before `next_round()`; drop "nothing on the summary" from `_garnish_keys_follow_the_rules`; in `_next_round_resets_and_reads_stats` replace "DOWN is ignored on the summary (pitcher upright)" with

```gdscript
	var jug: float = main.pourer.volume
	_run(1.5, true)
	expect(main.stream.is_empty() and main.pourer.volume == jug, "DOWN does nothing in the shop")
```

and replace `_summary_leads_to_the_shop` with:

```gdscript
func _round_end_opens_the_shop() -> void:
	_to_playing()
	main.time_left = 0.01
	_run(0.1)
	expect(main.phase == Main.Phase.SHOP and main.shop.visible, "time up on an untouched glass opens the shop at once")
	expect(not main.visible and not main.hud.visible, "the bar and the HUD are hidden in the shop")
	eq(main.shop.round_line_label.text, "ROUND 1 · 0 GLASSES · 0 PERFECT · BEST x1 · +0", "the shop shows the round's numbers")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	var round_before: int = GameState.round_number
	main.shop._unhandled_input(space)
	expect(main.phase == Main.Phase.SHOP, "a Space carried over from the last serve is swallowed by the lock")
	main.shop.input_lock = 0.0
	main.shop._unhandled_input(space)
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "Space in the shop starts the next round")
	expect(main.visible and main.hud.visible and not main.shop.visible, "...and brings the bar back")
	main.shop.input_lock = 0.5
```

`check_ui.gd`: delete the RoundSummary block (from `var summary: RoundSummary` through "...and hides it" and the summary button line; keep the `space` event, now declared before the shop block); `next_button.text` is `NEXT ROUND · SPACE`; add:

```gdscript
	eq(Shop.round_line(2, {"served": 6, "perfects": 4, "best_mult": 1.6, "coins": 134}), "ROUND 2 · 6 GLASSES · 4 PERFECT · BEST x1.6 · +134", "round line")
	eq(Shop.round_line(3, {"served": 1, "perfects": 0, "best_mult": 1.0, "coins": -6}), "ROUND 3 · 1 GLASS · 0 PERFECT · BEST x1 · -6", "...one glass, a loss")
	shop.open()
	eq(shop.round_line_label.visible, false, "no round line before any round (--shop at startup)")
	shop.open("ROUND 1 · 2 GLASSES · 1 PERFECT · BEST x1.2 · +20")
	eq([shop.round_line_label.visible, shop.round_line_label.text], [true, "ROUND 1 · 2 GLASSES · 1 PERFECT · BEST x1.2 · +20"], "...shown after one")
```

- [ ] **Step 2: Run to verify they fail**

Run: `--check=round`, `--check=ui`. Expected: FAIL (`SHOP_DELAY`, `round_line` missing; SUMMARY still reached).

- [ ] **Step 3: Implement**

- `main.gd`: remove `summary`, `AUTOPLAY_SUMMARY_WAIT`, `Phase.SUMMARY`; rename `SUMMARY_DELAY`→`SHOP_DELAY` and `_summary_in`→`_shop_in`; `_finish_round()` calls `open_shop()`; `open_shop()` enters SHOP, hides the world and calls `shop.open(Shop.round_line(GameState.round_number, round_stats) if results were collected this round else "")` — `--shop` (no round played: `round_stats` empty) opens with `""`; `tick()` treats INTRO as the only no-input phase besides SHOP's early return; autoplay: SHOP after `AUTOPLAY_SHOP_WAIT` → `shop()` + `next_round()`; header docs updated.
- `main.tscn`: remove the `RoundSummary` node and the `round_summary.tscn` ext_resource.
- `shop.gd`: `round_line_label` (Courier-like small label under the tabs for now; Task 4 moves it onto the page); `open(round_text)` sets it (hidden when empty); `round_line()` per Interfaces (`Hud.format_mult` for BEST, `%+d` for coins); NEXT ROUND button text `NEXT ROUND · SPACE`.
- Delete the RoundSummary files.

- [ ] **Step 4: Run all checks**

Run: `--import`, then `--check=all`. Expected: 12 OK.

- [ ] **Step 5: Commit**

```bash
git add -A main.gd main.tscn shop.gd autopilot.gd round_summary.gd round_summary.gd.uid round_summary.tscn tools/checks
git commit -m "Round end opens the shop straight away; the report screen goes"
```

---

### Task 2: Two bigger ice cubes with physics

**Files:**
- Create: `ice_physics.gd`
- Modify: `garnishes/ice.tres` (`cube_count = 2`, `cube_size = 10.4`), `glass.gd`
- Test: `tools/checks/check_glass.gd`, `tools/checks/check_drinks.gd`

**Interfaces:**
- Produces:
  - `class_name IcePhysics extends RefCounted` with inner `class Cube` (`pos: Vector2`, `vel: Vector2`, `angle: float`, `spin: float`); `var cubes: Array[Cube]`; `func _init(cube_size: float, float_share: float)`; `func add(pos: Vector2, vel: Vector2, angle: float, spin: float) -> void`; `func step(dt: float, interior: PackedVector2Array, surface: Callable) -> void` (`surface.call(x) -> float`: local y of the liquid surface at x, `INF` when there is no liquid); `func push(x: float, strength: float) -> void`; `func corners(c: Cube) -> PackedVector2Array`; `func max_speed() -> float`; `func max_spin() -> float`.
  - `Glass.ice: IcePhysics` (null until ice lands; cleared by `reset()`); `Glass.ICE_ENTRY_SPEED := 220.0`.

- [ ] **Step 1: Write the failing tests**

`check_drinks.gd` (with the garnish expectations):

```gdscript
	eq([ice.cube_count, ice.cube_size], [2, 10.4], "ice: two cubes of 10.4 px")
	main.glass.setup(water)
	var floor_w: int = main.glass._row_area[main.glass._row_area.size() - 1]
	expect(ice.cube_count * ice.cube_size < floor_w, "...side by side they fit the tumbler's floor (%d px)" % floor_w)
```

(move the `main` instantiation above it). `check_glass.gd`: in `_check_ice` the triangulation loop uses `ice.cube_count` (now 2) unchanged; add `_check_ice_physics(glass, water)` after `_check_lime`:

```gdscript
## The cubes bounce and slide but always stay inside the glass, separate,
## and come to rest; afloat they ride near the surface; the stream pushes them.
func _check_ice_physics(glass: Glass, water: DrinkDef) -> void:
	var ice: GarnishDef = water.garnishes[0]
	var inside := true
	var resting := true
	var overlap := 0.0
	var moved := false
	for i in 30:
		seed(100 + i)  # the physics' randomness is visual; a fixed seed repeats a failure
		glass.setup(water)
		glass.place(HOME)
		glass.add_garnish(ice)
		_steps(glass, Glass.ICE_FALL_TIME + DT)
		expect(glass.ice != null and glass.ice.cubes.size() == 2, "drop %d: landed ice is simulated" % i)
		var start: Vector2 = glass.ice.cubes[0].pos
		var t := 0.0
		while t < 1.2:
			glass.step(DT)
			t += DT
			for c in glass.ice.cubes:
				for p in glass.ice.corners(c):
					inside = inside and Geometry2D.is_point_in_polygon(p, _grown(glass.interior, 0.6))
		moved = moved or glass.ice.cubes[0].pos.distance_to(start) > 0.5
		resting = resting and glass.ice.max_speed() < 3.0 and glass.ice.max_spin() < 0.3
		overlap = maxf(overlap, _overlap(glass.ice.corners(glass.ice.cubes[0]), glass.ice.corners(glass.ice.cubes[1])))
	expect(inside, "dropped into an empty glass, the cubes never leave it")
	expect(moved, "...they move on landing instead of sticking where they fell")
	expect(resting, "...and come to rest within about a second")
	expect(overlap < 1.0, "...without sinking into each other (%.2f px²)" % overlap)
	glass.setup(water)
	glass.place(HOME)
	glass.receive(HOME.x, glass.target - glass.displaced(glass.target), 0.0)
	glass.add_garnish(ice)
	_steps(glass, Glass.ICE_FALL_TIME + 2.5)
	var level := glass.surface_level(glass.volume)
	for c in glass.ice.cubes:
		var want := level + ice.cube_size * (ice.float_share - 0.5)
		near(c.pos.y, want, "afloat at the line, a cube rides with float_share under", 2.5)
	var before: Vector2 = glass.ice.cubes[0].vel
	glass.receive(HOME.x + glass.ice.cubes[0].pos.x + 3.0, 40.0, 120.0)
	expect(glass.ice.cubes[0].vel.x < before.x - 0.5, "liquid landing beside a cube pushes it away")
	glass.arrive(water, HOME)
	expect(glass.ice == null, "an arriving glass has no ice")
	glass.place(HOME)


func _grown(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	return Geometry2D.offset_polygon(poly, by)[0]


func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var area := 0.0
	for p in Geometry2D.intersect_polygons(a, b):
		area += Pourer.poly_area(p)
	return area
```

- [ ] **Step 2: Run to verify they fail**

Run: `--check=drinks`, `--check=glass`. Expected: FAIL (3 × 8.5; `glass.ice` missing).

- [ ] **Step 3: Implement `IcePhysics`**

Rigid rounded squares (side `cube_size`, unit mass, inertia `s²/6`), stepped in 4 substeps per call:

- gravity 700 px/s² (as `Effects.GRAVITY`); buoyancy `−700 × sub / float_share` where `sub` = the share of the cube's vertical extent (`h·(|cos|+|sin|)` each way) below `surface.call(pos.x)`; drag `vel *= 1 − (0.4 + 5·sub)·dt`, spin likewise;
- a settling torque toward the nearest quarter turn (`−60·Δangle − 6·spin`) when touching the glass or afloat, so cubes end flat on a face;
- walls: for each corner and each interior edge except the top one (the opening), if the corner is past the edge's line (the interior is convex), push the cube back along the inward normal by the penetration and apply an impulse at the corner — restitution 0.3 along the normal, friction 0.4 along the edge — updating `vel` and `spin`;
- cube–cube: separating-axis test of the two squares; on overlap, split the push along the least-overlap axis and exchange a normal impulse (restitution 0.3);
- `push(x, strength)`: cubes within `1.2·size` of x get `vel += (sign(pos.x − x)·strength, 0.5·strength)`, `strength` clamped to 60.

- [ ] **Step 4: Wire it into the glass**

- `glass.gd`: when ice lands (`_step_garnishes`), `ice = IcePhysics.new(g.cube_size, g.float_share)` and add each landing pose from `_cube_poses(g)` with `vel = Vector2(randf_range(-40, 40), ICE_ENTRY_SPEED)` (before the overflow and the wave kick, which stay), `spin = randf_range(-6, 6)`; each `step()` after that calls `ice.step(dt, interior, _surface_at)` where `_surface_at(x)` is `_surface_local(col)` for liquid ≥ 0.5 px², else `INF`; `receive()` calls `ice.push(x_local, vol * speed * 0.6)` when there is ice; `_cube_poses(g)` returns the simulated poses once `ice` exists (the scripted fall before that is unchanged); `reset()` sets `ice = null`. `CUBE_LOOKS` needs only two entries. Doc comments updated (the cubes are simulated, visual only).
- `garnishes/ice.tres`: `cube_count = 2`, `cube_size = 10.4`.

- [ ] **Step 5: Run checks, sweeps and screenshots**

Run: `--check=all` (12 OK); the two sweeps diff empty against Step 0's baseline; then
`"$GODOT" --path . --windowed -- --autoplay --shop --coins=120 --seed=11 --shots=$S/ice --shot-every=0.1 --quit=12` and look at a crop of the glass across the frames where ice drops into the empty glass and floats. Expected: cubes bounce, tip and slide, then rest flat; afloat they bob; no `SHADER ERROR`.

- [ ] **Step 6: Commit**

```bash
git add -A ice_physics.gd* glass.gd garnishes/ice.tres tools/checks
git commit -m "Ice: two bigger cubes that bounce, slide, knock about and float"
```

---

### Task 3: Menu fonts, palette and ink illustrations

**Files:**
- Create: `fonts/Oswald-VariableFont_wght.ttf`, `fonts/CourierPrime-Regular.ttf`, `fonts/CourierPrime-Bold.ttf`, `fonts/OFL-Oswald.txt`, `fonts/OFL-CourierPrime.txt`, `menu_art.gd`
- Modify: `palette.gd`
- Test: `tools/checks/check_shop.gd`

**Interfaces:**
- Produces: `Palette.PAPER` (`#f3eee3`), `Palette.MENU_INK` (`#2e2a2b`), `Palette.PAPER_SHADE` (`#ddd3bf`), `Palette.TAB_UPGRADES` (`#c0674b`), `Palette.TAB_DRINKS` (`#8aa37b`), `Palette.TAB_MENU` (`#6f8fae`), `Palette.STAMP` (`#b8423c`). `class_name MenuArt extends RefCounted` (static): `title_font(weight := 700) -> FontVariation` (Oswald), `type_font(bold := false) -> Font` (Courier Prime); `draw_ice(ci, center: Vector2, size: float)`, `draw_lime(ci, center: Vector2, radius: float)`, `draw_glass(ci, d: DrinkDef, box: Rect2, fill: float)`, `draw_bottle(ci, d: DrinkDef, box: Rect2)`, `draw_redacted(ci, box: Rect2, seed_value: int)`, `draw_ornament(ci, center: Vector2, width: float)`; and for checks the polygon getters `ice_polygons(center, size)`, `glass_polygons(d, box, fill)`, `bottle_polygons(d, box)`, `redacted_polygon(box, seed_value)` (each `Array[PackedVector2Array]` / `PackedVector2Array`).

- [ ] **Step 1: Write the failing test** (`check_shop.gd`, at the end of `run()`)

```gdscript
	# Menu art: printed-menu illustrations and marker bars, all drawable.
	var polys: Array[PackedVector2Array] = []
	polys.append_array(MenuArt.ice_polygons(Vector2.ZERO, 10.0))
	polys.append_array(GarnishArt.lime_polygons(Vector2.ZERO, 9.0, Glass.LIME_ANGLE))
	for d: DrinkDef in GameState.DRINKS:
		polys.append_array(MenuArt.glass_polygons(d, Rect2(0, 0, 20, 24), d.fill_fraction))
		polys.append_array(MenuArt.bottle_polygons(d, Rect2(0, 0, 14, 26)))
	for i in 12:
		polys.append(MenuArt.redacted_polygon(Rect2(0, 0, 60 + i * 9, 9), i))
	var bad := 0
	for p in polys:
		if p.size() >= 3 and Geometry2D.triangulate_polygon(p).is_empty():
			bad += 1
	eq(bad, 0, "every menu illustration and marker bar triangulates (%d shapes)" % polys.size())
	expect(MenuArt.redacted_polygon(Rect2(0, 0, 80, 9), 3) == MenuArt.redacted_polygon(Rect2(0, 0, 80, 9), 3), "a marker bar is the same every visit")
	expect(MenuArt.title_font() != null and MenuArt.type_font(true) != null, "the menu fonts load")
```

- [ ] **Step 2: Run to verify it fails**

Run: `--check=shop`. Expected: FAIL (`MenuArt` missing).

- [ ] **Step 3: Fetch the fonts**

```bash
B=https://github.com/google/fonts/raw/main/ofl
curl -sSL -o "fonts/Oswald-VariableFont_wght.ttf" "$B/oswald/Oswald%5Bwght%5D.ttf"
curl -sSL -o fonts/OFL-Oswald.txt "$B/oswald/OFL.txt"
curl -sSL -o fonts/CourierPrime-Regular.ttf "$B/courierprime/CourierPrime-Regular.ttf"
curl -sSL -o fonts/CourierPrime-Bold.ttf "$B/courierprime/CourierPrime-Bold.ttf"
curl -sSL -o fonts/OFL-CourierPrime.txt "$B/courierprime/OFL.txt"
file fonts/*.ttf   # each must say TrueType font data
```

- [ ] **Step 4: Implement `menu_art.gd` and the palette entries**

Ink illustrations from the game's shapes, per the spec's "Drawings, printed-menu style": an even dark-ink outline (`MENU_INK`, ~0.8 units) over flat, slightly translucent fills — ice two overlapping rounded cubes (pale `WATER_LIGHT`, white glint), the lime via `GarnishArt.lime_polygons` re-coloured (peel, pale flesh, segment lines) with an ink outline, a glass from `d.glass_outer`/`glass_interior` fitted into `box` with a fill of `d.liquid_color` up to `fill` of its height, a bottle from `d.pourer_outer` upright in `pourer_glass_color` with its label and foil rects; `draw_redacted` = a slanted bar with wobbly, seeded edges (a local `RandomNumberGenerator` seeded with `seed_value`), `Palette.INK` at 0.93, a few faint lighter streaks; `draw_ornament` = two thin rules with a small diamond between. Fonts cached like `Hud.font()` (Oswald's weight through the `wght` tag).

- [ ] **Step 5: Run all checks**

Run: `--import`, `--check=all`. Expected: 12 OK.

- [ ] **Step 6: Commit**

```bash
git add -A fonts menu_art.gd* palette.gd tools/checks/check_shop.gd
git commit -m "Menu art: Oswald and Courier Prime, paper palette, ink illustrations, marker bars"
```

---

### Task 4: The menu page, lines and tabs

**Files:**
- Create: `menu_page.gd`, `menu_line.gd`
- Modify: `shop.gd` (the page replaces the panel and cards), `tools/make_background.sh` (drop the `shop` target), `autopilot.gd` (unchanged API)
- Delete: `shop_card.gd` (+ `.uid`), `vessel_preview.gd` (+ `.uid`), `art/shop_background.png` (+ `.import`), `tools/background/shop.html`
- Test: `tools/checks/check_shop.gd`, `tools/checks/check_ui.gd`

**Interfaces:**
- Consumes: `MenuArt`, `Palette` entries (Task 3); `Shop.open(round_text)`, `round_line_label` (Task 1).
- Produces:
  - `class_name MenuPage extends Control`: built for one tab from a list of sections; draws the paper, frame, title, ornament, section headers (`::NAME::`, or a marker bar for a blacked-out header) and blacked-out lines; holds the `MenuLine` children; `var lines: Array[MenuLine]`; `var blacked_out := 0` (count of blacked-out lines on it).
  - `class_name MenuLine extends Control`: `var item: Resource`; `var price_button: Button`; `var badge: Label` (OWNED stamp); `var toggle_button: Button`; `var note: Label`; `var faded := false`; `signal activated`; `func show_price(price: int, state: Shop.CardState)`; `func show_toggle(on: bool, locked: bool)`.
  - `Shop`: `var lines: Array[MenuLine]` (replaces `cards`); `func blacked_out_lines() -> int`; `var page: MenuPage`; `const UPGRADE_TEASERS := {&"water": 2, &"wine": 3}`, `const DRINK_TEASERS := 5`; `CardState`, `card_state`, `state_of`, `buy`, `toggle`, `show_tab`, `open`, `close`, `refresh`, `next_button` (a flat line button, `NEXT ROUND · SPACE`), `coins_label` kept.

- [ ] **Step 1: Rewrite the shop tests** (`check_shop.gd` screen part: `cards` → `lines`, `ShopCard` → `MenuLine`, `buy_button` → `price_button`, `toggle_button`/`badge`/`note` as before, and the font-size loop walks `MenuLine` labels and buttons); add:

```gdscript
	shop.show_tab(Shop.Tab.UPGRADES)
	eq(shop.blacked_out_lines(), 5, "UPGRADES: 2 blacked-out water lines and 3 for wine")
	shop.show_tab(Shop.Tab.DRINKS)
	eq([shop.lines.size(), shop.blacked_out_lines()], [1, 5], "DRINKS: wine, then 5 drinks to come")
	shop.show_tab(Shop.Tab.MENU)
	eq(shop.blacked_out_lines(), 0, "MENU: only what you own")
	expect(shop.page.get_child_count() >= shop.lines.size(), "the lines sit on the page")
```

`check_ui.gd`: `next_button.text` is `NEXT ROUND · SPACE` (already, from Task 1).

- [ ] **Step 2: Run to verify it fails**

Run: `--check=shop`. Expected: FAIL (`lines`, `MenuLine`, `blacked_out_lines` missing).

- [ ] **Step 3: Implement**

- Layout (HUD units; fine-tune by screenshot): dark `INK` backdrop over the whole screen; the page `Rect2(22, 8, 560, 344)` with a soft shadow; tabs to its right (x 582–610), stacked from y 40, ~70 tall each, 10 apart; page-local: title centred at y 14 (Oswald 700, 30, letter-spaced), ornament y 54, round line y 60 (Courier 9), coins top right (coin icon + Oswald 13), a thin vertical rule between two columns (x 30–270 and 290–530), body from y 84, `NEXT ROUND · SPACE` centred at y 322 (Oswald 600, 12; darker and underlined on hover).
- Sections flow down the left column, then the right. UPGRADES: for every drink in `GameState.DRINKS` (owned or not): `::NAME::`, its garnishes as lines, then `UPGRADE_TEASERS[id]` blacked-out lines. DRINKS: `::BY THE GLASS::` with every priced drink, then a blacked-out-header section with `DRINK_TEASERS` blacked-out lines. MENU: `::NEXT ROUND SERVES::` with a line per owned drink.
- `MenuLine` (≈ 240×30): illustration at left (a `DrawLayer` calling `MenuArt`; garnishes → `draw_ice`/`draw_lime`, DRINKS → `draw_bottle`, MENU → `draw_glass` at its `fill_fraction`), name (Oswald 600, 12, caps), description under it (Courier 9, ink 0.7); right side: the price button (flat, Courier Bold 11 + a small `Hud.Coin`; hover: darker, a pen underline and a small `BUY` to its left; disabled and the line at alpha 0.4 when unaffordable), or the OWNED stamp (Oswald 700, `STAMP`, bordered, tilted ~−8°, a quick scale pop when it appears after buying), or the checkbox toggle (drawn box with a tick, `ON`/`OFF` in Courier) with `At least one drink` (Courier 9) under a locked one; a menu line toggles when clicked anywhere.
- Blacked-out lines: `MenuArt.draw_redacted` over the name and description areas (seeded by section and row), price `??` in faded Courier; not Controls, so not clickable.
- Tabs: three flat `Button`s with a drawn folder-tab shape (sloped rounded shoulders, its colour, label rotated to read top-to-bottom in Oswald 700 11); the current tab is moved in front of the page (joined to its edge), the others behind it and a little darker; hover lightens.
- `round_line_label` moves onto the page under the ornament.
- Remove the shop background and its tooling; `make_background.sh` keeps only `bar`.

- [ ] **Step 4: Run all checks and screenshot each page**

Run: `--import`, `--check=all` (12 OK). Screenshots with a throwaway local `--shop-tab=N` / `--owned` edit in `main.gd` (reverted before commit, as in slice 3): `--shop --coins=12` for each tab and `--owned` for OWNED/MENU with wine. Expected: reads like the BEVERAGES reference; text crisp at the window's resolution; tabs on the right; no `SHADER ERROR`.

- [ ] **Step 5: Commit**

```bash
git add -A shop.gd menu_page.gd* menu_line.gd* shop_card.gd shop_card.gd.uid vessel_preview.gd vessel_preview.gd.uid art tools tools/checks
git commit -m "The shop is a printed drinks menu: sections, ink drawings, blacked-out lines, index tabs"
```

---

### Task 5: Page turns

**Files:**
- Modify: `shop.gd`
- Test: `tools/checks/check_shop.gd`

**Interfaces:**
- Consumes: `MenuPage`, `Shop.show_tab` (Task 4).
- Produces: `Shop.TURN_TIME := 0.35`; `Shop.is_turning() -> bool`; `Shop._turn_tween: Tween` (checks step it with `custom_step`).

- [ ] **Step 1: Write the failing test** (`check_shop.gd`)

```gdscript
	# Page turns.
	GameState.coins = 999
	shop.open()
	shop.show_tab(Shop.Tab.UPGRADES)
	shop._finish_turn()
	shop.show_tab(Shop.Tab.DRINKS)
	expect(shop.is_turning() and shop.tab == Shop.Tab.DRINKS, "a tab click turns the page (the new page is underneath at once)")
	var coins_before := GameState.coins
	for line in shop.lines:
		line.price_button.pressed.emit()
	eq(GameState.coins, coins_before, "nothing can be bought mid-turn")
	shop.show_tab(Shop.Tab.MENU)
	expect(shop.is_turning() and shop.tab == Shop.Tab.MENU, "a tab clicked mid-turn finishes that turn and starts the next")
	shop._turn_tween.custom_step(Shop.TURN_TIME + 0.05)
	expect(not shop.is_turning(), "a turn takes TURN_TIME")
	shop.show_tab(Shop.Tab.UPGRADES)
	shop._turn_tween.custom_step(Shop.TURN_TIME + 0.05)
	expect(not shop.is_turning() and shop.tab == Shop.Tab.UPGRADES, "turning back works too")
	shop.close()
	shop.open()
	expect(not shop.is_turning(), "opening the shop doesn't turn a page")
```

(Place it before the final `shop.free()`.)

- [ ] **Step 2: Run to verify it fails**

Run: `--check=shop`. Expected: FAIL (`is_turning` missing).

- [ ] **Step 3: Implement**

`show_tab(t)` while visible and `t != tab`: finish any running turn (`_finish_turn()`), build the new page; forward (to a later tab): keep the old page on top and tween its `scale.x` 1 → 0 about its left edge (`pivot_offset.x = 0`) over `TURN_TIME` with an ease-in, a shading overlay darkening toward the fold and a soft shadow on the page below; backward: put the new page on top at `scale.x` 0 and tween it to 1, the old page underneath; when done, free the old page. `open()`/`refresh()` never turn. While turning, `MenuLine.activated` is ignored. `_finish_turn()` kills the tween, frees the outgoing page and resets scales.

- [ ] **Step 4: Run all checks and screenshot a turn mid-way**

Run: `--check=all` (12 OK). Screenshot a turn mid-way (a throwaway local edit that calls `show_tab` 0.2 s after `--shop`, `--shot-every=0.05`). Expected: the page folds toward the spine with shading; no errors.

- [ ] **Step 5: Commit**

```bash
git add shop.gd tools/checks/check_shop.gd
git commit -m "Shop: clicking a tab turns the page"
```

---

### Task 6: Docs and final verification

**Files:**
- Modify: `CLAUDE.md`, the spec's status line

- [ ] **Step 1: Verify**

```bash
"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all
"$GODOT" --headless --path . -- --sweep > $S/sweep2_water_after.txt 2>&1 && diff $S/sweep2_water_before.txt $S/sweep2_water_after.txt
"$GODOT" --headless --path . -- --sweep=wine > $S/sweep2_wine_after.txt 2>&1 && diff $S/sweep2_wine_before.txt $S/sweep2_wine_after.txt
"$GODOT" --path . --windowed -- --autoplay --seed=11 --coins=0 --shots=$S/final2 --shot-every=1.5 --quit=110 2>&1 | grep -i "error"; true
```
Expected: 12 OK, empty diffs, no errors; frames go round → shop (menu) → round.

- [ ] **Step 2: Update `CLAUDE.md`**: current state (menu shop, no report, ice physics), commands (`make_background.sh` bar only), architecture (phases without SUMMARY, `Shop` as a menu with `MenuPage`/`MenuLine`/`MenuArt`, page turns, the fonts, `IcePhysics`, removed files), visual identity (the menu look, fonts).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers
git commit -m "docs: the menu shop and ice physics"
```
