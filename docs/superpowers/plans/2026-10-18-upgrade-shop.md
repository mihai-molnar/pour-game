# Slice 3: Shop, Garnishes and Drink Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A between-rounds shop (UPGRADES / DRINKS / MENU tabs) where the player buys ice and lime for water and wine as a new drink, picks next round's drinks, and uses the garnishes in play (UP ice, LEFT lime) for a percentage bonus.

**Architecture:** Purchases and the menu live in `GameState`; garnishes are data (`GarnishDef`, listed on each `DrinkDef`); `Scoring` adds the garnish bonus; the `Glass` owns what is in it (falling/landed ice and lime, the iced level used for drawing and scoring); `Main` gains a SHOP phase and the garnish keys; `Shop` is a full-screen `CanvasLayer` built in code like `Hud`, with cards whose pictures reuse the game's own drawing (`GarnishArt`, `VesselPreview`).

**Tech Stack:** Godot 4.5.1, GDScript, headless checks via `tools/run_check.gd`, background art via headless Chrome (`tools/make_background.sh`).

**Spec:** `docs/superpowers/specs/2026-10-18-upgrade-shop-design.md`

## Global Constraints

- Work on branch `feat/upgrade-shop` off `master`.
- `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"` (quote it). Checks: `"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=<name|all>`; judge by the `check_<name>: OK` lines, not the exit code. Run `"$GODOT" --headless --path . --import` after adding any `class_name` script or asset.
- Prices: ice 10, lime 15, wine 80. Bonuses: ice 0.2, lime 0.3 (they add up). Water's table: 12/7/4 ice, 13/8/4 lime, 15/9/5 both.
- Keys (physical): UP adds ice, LEFT adds lime. DOWN pours, Space serves (unchanged).
- Copy, exactly: summary button `TO THE SHOP  (SPACE)`; shop button `NEXT ROUND  (SPACE)`; tabs `UPGRADES`, `DRINKS`, `MENU`; menu note `At least one drink`; card lines `Water pays +20%`, `Water pays +30%`, `Pays 15 / 9 / 5`; banner `ROUND N\nNEW DRINK: WINE`; hint `HOLD DOWN  pour   ·   UP  ice   ·   LEFT  lime   ·   SPACE  serve   ·   F1  debug` (only owned garnishes, only on a drink that has them).
- Summary and shop ignore Space and their button for `input_lock` = 0.5 s after appearing.
- Ice raises the settled surface at the water line by 4–6 rows (aim 5).
- Gameplay stays deterministic; visual randomness uses `randf`/fixed constants, never `GameState.rng`.
- `--sweep` and `--sweep=wine` output byte-identical to before this slice.
- Colours via `Palette.*` in game code; HUD-space layout by hand in 640×360 units; buttons `focus_mode = FOCUS_NONE`.
- Never edit `.godot/`; commit `.uid` sidecars and `.import` files Godot generates.

## Review Focus

1. A Space press carried over from the summary must not skip the shop — the shop's own 0.5 s lock (Task 2, check_ui).
2. Double-clicking BUY spends the price once (Task 1 state, Task 5 through the button).
3. UP/LEFT while the summary or shop is open do nothing and leave nothing queued for the next round (Task 4, check_round).
4. Coins changing between shop visits: card states refresh on `open()`, not only on buy (Task 5, check_shop).
5. A bought drink toggled off and back on before leaving still opens the next round under the banner (Task 1, check_shop).

---

### Task 1: Garnish data, purchases and the scoring bonus

Wine stops unlocking in round 2; purchases and the menu exist in `GameState`; `Scoring` pays the garnish bonus. No shop UI yet (wine is only reachable through the API).

**Files:**
- Create: `garnish_def.gd`, `garnishes/ice.tres`, `garnishes/lime.tres`, `tools/checks/check_shop.gd`
- Modify: `drink_def.gd`, `drinks/water.tres`, `drinks/wine.tres`, `game_state.gd`, `scoring.gd`, `main.gd` (`start_round`, `_pick_drink`), `hud.gd` (`round_banner` param name/doc)
- Test: `tools/checks/check_scoring.gd`, `check_drinks.gd`, `check_round.gd`, `check_ui.gd`; replace every `GameState.ROUND_UNLOCKS[2]` / `.get(2)` with `GameState.WINE` in `check_bubbles.gd`, `check_glass.gd`, `check_view.gd`, `check_pourer.gd`, `check_round.gd`

**Interfaces:**
- Produces:
  - `class_name GarnishDef extends Resource` with `enum Kind { ICE, RIM }` and exports `id: StringName`, `display_name: String`, `description: String`, `price: int`, `bonus: float`, `kind: Kind`, `key: Key`, group "Ice": `cube_size: float` (8.5), `cube_count: int` (3), `float_share: float` (0.9).
  - `DrinkDef.garnishes: Array[GarnishDef]` (group "Shop"), `DrinkDef.price: int`.
  - `GameState.WINE` (preload), `GameState.DRINKS` (`[WATER, WINE]`, shop order), `owned_garnishes: Array[StringName]`, `menu: Array[DrinkDef]`, `new_drinks: Array[DrinkDef]`, `owns_drink(d: DrinkDef) -> bool`, `owns_garnish(g: GarnishDef) -> bool`, `buy_drink(d: DrinkDef) -> bool`, `buy_garnish(g: GarnishDef) -> bool`, `set_on_menu(d: DrinkDef, on: bool) -> bool`, `take_new_drink() -> DrinkDef`.
  - `Scoring.garnished_coins(base: int, garnishes: Array[GarnishDef]) -> int`; `Scoring.score(..., stats: Dictionary, garnishes: Array[GarnishDef] = [])` whose result gains `"garnishes": Array[StringName]`.
  - Removed: `GameState.ROUND_UNLOCKS`, `GameState.unlock_for_round()`.

- [ ] **Step 0: Branch and record the sweep baseline**

```bash
git checkout -b feat/upgrade-shop
S=/private/tmp/claude-501/-Users-mihai-Godot-games-pour-prototype/1786fe62-e838-46d8-a56e-d08f69bb827e/scratchpad
"$GODOT" --headless --path . -- --sweep > $S/sweep_water_before.txt 2>&1
"$GODOT" --headless --path . -- --sweep=wine > $S/sweep_wine_before.txt 2>&1
```

- [ ] **Step 1: Write the failing tests**

`check_scoring.gd` (before the `coin_mult = 2.0` lines):

```gdscript
	var ice: GarnishDef = load("res://garnishes/ice.tres")
	var lime: GarnishDef = load("res://garnishes/lime.tres")
	var with_ice: Array[GarnishDef] = [ice]
	var with_lime: Array[GarnishDef] = [lime]
	var both: Array[GarnishDef] = [ice, lime]
	var table := []
	for gs in [with_ice, with_lime, both]:
		for b in [Scoring.PERFECT, Scoring.GOOD, Scoring.GOOD_ENOUGH]:
			table.append(Scoring.garnished_coins(Scoring.base_coins(b, water), gs))
	eq(table, [12, 7, 4, 13, 8, 4, 15, 9, 5], "water pays 12/7/4 with ice, 13/8/4 with lime, 15/9/5 with both")
	eq(Scoring.score(0, 0.0, false, 5, water, stats, both).coins, roundi(15 * 1.5), "a garnished PERFECT at x1.5 pays round(15 x 1.5)")
	eq(Scoring.score(0, 0.1, true, 0, water, stats, both).coins, -6, "a garnished spill still costs 6")
	eq(Scoring.score(9, 0.0, false, 0, water, stats, both).coins, 0, "a garnished MISS pays 0")
	eq(Scoring.score(0, 0.0, false, 0, water, stats, with_ice).garnishes, [&"ice"], "score records the garnishes")
	eq(Scoring.score(0, 0.0, false, 0, water, stats).garnishes, [], "...none by default")
```

`check_drinks.gd`: delete the four `unlock_for_round` / `ROUND_UNLOCKS` expectations; `wine` comes from `GameState.WINE`; add:

```gdscript
	expect(GameState.menu.size() == 1 and GameState.menu[0] == water, "menu starts as [water]")
	expect(GameState.owned_garnishes.is_empty() and GameState.new_drinks.is_empty(), "nothing bought yet")
	expect(GameState.DRINKS.size() == 2 and GameState.DRINKS[0] == water and GameState.DRINKS[1] == wine, "the catalog is water, wine")
	eq([water.price, wine.price], [0, 80], "water is free, wine costs 80")
	eq(water.garnishes.map(func(g: GarnishDef) -> StringName: return g.id), [&"ice", &"lime"], "water's garnishes are ice and lime")
	eq(wine.garnishes.size(), 0, "wine has none yet")
	var ice: GarnishDef = water.garnishes[0]
	var lime: GarnishDef = water.garnishes[1]
	eq([ice.price, ice.bonus, ice.key, ice.kind], [10, 0.2, KEY_UP, GarnishDef.Kind.ICE], "ice: 10 coins, +20 %, UP, falls in")
	eq([lime.price, lime.bonus, lime.key, lime.kind], [15, 0.3, KEY_LEFT, GarnishDef.Kind.RIM], "lime: 15 coins, +30 %, LEFT, on the rim")
	eq([ice.description, lime.description], ["Water pays +20%", "Water pays +30%"], "card lines")
```

New `tools/checks/check_shop.gd` (state part; Task 5 appends the UI part):

```gdscript
extends CheckBase
## Checks purchases and the drink menu (GameState), and the shop screen. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=shop


func run() -> void:
	var water: DrinkDef = GameState.WATER
	var wine: DrinkDef = GameState.WINE
	var ice: GarnishDef = water.garnishes[0]
	var lime: GarnishDef = water.garnishes[1]
	expect(not GameState.buy_garnish(ice) and GameState.coins == 0 and not GameState.owns_garnish(ice), "0 coins can't buy ice")
	GameState.coins = 25
	expect(GameState.buy_garnish(ice) and GameState.coins == 15 and GameState.owns_garnish(ice), "ice costs 10")
	expect(not GameState.buy_garnish(ice) and GameState.coins == 15, "ice can't be bought twice")
	expect(GameState.buy_garnish(lime) and GameState.coins == 0, "lime costs 15")
	GameState.coins = 79
	expect(not GameState.buy_drink(wine) and not GameState.owns_drink(wine), "79 coins can't buy wine")
	GameState.coins = 80
	expect(GameState.buy_drink(wine) and GameState.coins == 0, "wine costs 80")
	expect(GameState.owned_drinks.has(wine) and GameState.menu.has(wine) and GameState.new_drinks == [wine], "bought wine is owned, on the menu and new")
	expect(not GameState.buy_drink(water), "water is already owned")
	expect(GameState.set_on_menu(water, false) and GameState.menu == [wine], "water can go off while wine is on")
	expect(not GameState.set_on_menu(wine, false) and GameState.menu == [wine], "the last drink on the menu stays on")
	expect(GameState.set_on_menu(water, true) and GameState.menu.size() == 2, "water back on")
	expect(GameState.set_on_menu(wine, false) and GameState.set_on_menu(wine, true), "wine off and on again")
	eq(GameState.take_new_drink(), wine, "a new drink toggled off and on again still opens the next round")
	eq(GameState.take_new_drink(), null, "...once")
	GameState.reset_session(1)
	GameState.coins = 80
	GameState.buy_drink(wine)
	GameState.set_on_menu(wine, false)
	eq(GameState.take_new_drink(), null, "a new drink switched off doesn't open the round")
	expect(GameState.new_drinks.is_empty(), "...and is no longer new")
	expect(not GameState.set_on_menu(load("res://drinks/wine.tres").duplicate(), true), "an unowned drink can't go on the menu")
	GameState.reset_session(1)
	expect(GameState.owned_drinks == [water] and GameState.menu == [water] and GameState.owned_garnishes.is_empty() and GameState.new_drinks.is_empty(),
		"reset_session clears purchases and the menu")
```

`check_round.gd`: add a helper and replace `_round_two_unlocks_wine` with two tests; tests that used `_fresh(2, seed)` to get wine (`_time_up_during_a_bottle_refill`, `_picks_follow_the_seed`, `_drink_change_swaps_the_pourer`, `_mixed_round_with_autopilot`) call `_fresh_with_wine(seed)` instead (same seeds).

```gdscript
## Round 2 of a session that bought wine in the shop: it opens with wine.
func _fresh_with_wine(seed_value: int) -> void:
	GameState.reset_session(seed_value)
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	GameState.coins = 0
	GameState.round_number = 2
	main.start_round()


func _round_two_is_water_only() -> void:
	_fresh(2, 5)
	eq(main.hud.banner_label.text, "ROUND 2", "round 2 brings no drink by itself")
	var seen := {}
	for i in 40:
		seen[main._pick_drink().id] = true
	eq(seen.keys(), [&"water"], "nothing bought: only water")


func _bought_wine_opens_the_next_round() -> void:
	_fresh_with_wine(5)
	var wine: DrinkDef = GameState.WINE
	expect(main.drink == wine and main.glass.def == wine and main.pourer.def == wine, "the round after buying wine opens with wine")
	eq(main.hud.banner_label.text, "ROUND 2\nNEW DRINK: WINE", "the banner names the new drink")
	var seen := {}
	for i in 40:
		seen[main._pick_drink().id] = true
	expect(seen.has(&"water") and seen.has(&"wine"), "later picks include both drinks (%s)" % [seen.keys()])
	GameState.set_on_menu(GameState.WATER, false)
	seen.clear()
	for i in 20:
		seen[main._pick_drink().id] = true
	eq(seen.keys(), [&"wine"], "picks come from the menu")
	GameState.round_number = 3
	main.start_round()
	eq(main.hud.banner_label.text, "ROUND 3", "no banner once wine isn't new")
```

`check_ui.gd`: `Hud.round_banner(2, GameState.WINE)`.

- [ ] **Step 2: Run the checks to verify they fail**

Run: `"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all`
Expected: scoring, drinks, shop, round fail (missing `GarnishDef`, `garnished_coins`, `WINE`, `buy_drink` …).

- [ ] **Step 3: Implement**

- `garnish_def.gd` as in Interfaces (doc comment: one `.tres` per garnish in `res://garnishes/`, listed on its drink's `garnishes`).
- `garnishes/ice.tres`: id `ice`, display_name `Ice`, description `Water pays +20%`, price 10, bonus 0.2, kind ICE, key `KEY_UP` (4194320). `garnishes/lime.tres`: id `lime`, `Lime`, `Water pays +30%`, 15, 0.3, RIM, `KEY_LEFT` (4194319).
- `drink_def.gd`: `@export_group("Shop")`, `@export var price := 0` ("coins it costs in the shop; 0 = owned from the start"), `@export var garnishes: Array[GarnishDef] = []`. `water.tres`: `garnishes = Array[ExtResource("<garnish_def.gd id>")]([ExtResource("<ice>"), ExtResource("<lime>")])`; `wine.tres`: `price = 80`. Verify by loading (check_drinks).
- `game_state.gd`: drop `ROUND_UNLOCKS`/`unlock_for_round`; add the Interfaces members. Rules: `buy_*` returns false when owned or `coins < price`; a bought drink is appended to `owned_drinks`, `menu` and `new_drinks`; `set_on_menu` returns false for an unowned drink or when switching off the last one, true otherwise (also when nothing changes); `take_new_drink()` returns the first of `new_drinks` that is on the menu (else null) and clears `new_drinks`; `reset_session()` resets all of it. Update the header doc (the shop replaces the round-unlock stand-in).
- `scoring.gd`: `garnished_coins` returns `base` when `base <= 0`, else `roundi(base * (1.0 + Σ bonus))`; `score()` uses `paid_coins(garnished_coins(base_coins(b, def), garnishes), streak_before, stats)` and records the ids.
- `main.gd` `start_round()`: `var fresh := GameState.take_new_drink()` replaces `unlock_for_round`; `_force_next = fresh`; the banner uses it. `_pick_drink()` draws from `GameState.menu` (doc: "a just-bought drink first, otherwise any drink on the menu").
- `hud.gd` `round_banner(round_number, new_drink)`: rename the param, doc "a drink bought in the shop since the last round".

- [ ] **Step 4: Run all checks**

Run: `"$GODOT" --headless --path . --import` then the all-checks command.
Expected: every `check_<name>: OK` line (12 checks incl. shop).

- [ ] **Step 5: Commit**

```bash
git add -A garnish_def.gd* garnishes drink_def.gd drinks game_state.gd scoring.gd main.gd hud.gd tools/checks
git commit -m "Wine becomes a purchase: garnish data, purchases and menu state, garnish bonus in scoring"
```

---

### Task 2: The shop screen, its background and the round flow

Summary → Space → shop → Space → next round. The shop shows its background, coins, the three tabs and NEXT ROUND; tab contents come in Task 5. The background is shown to the user as an in-game screenshot at the end of this task (spec: no separate mockup round).

**Files:**
- Create: `tools/background/shop.html`, `art/shop_background.png` (+ `.import`), `shop.gd`
- Modify: `tools/make_background.sh`, `main.gd`, `main.tscn` (Shop node), `round_summary.gd`
- Test: `tools/checks/check_round.gd`, `tools/checks/check_ui.gd`

**Interfaces:**
- Consumes: Task 1's `GameState` members.
- Produces:
  - `class_name Shop extends CanvasLayer`: `signal next_pressed`, `enum Tab { UPGRADES, DRINKS, MENU }`, `const TAB_NAMES := ["UPGRADES", "DRINKS", "MENU"]`, `var tab := Tab.UPGRADES`, `var input_lock := 0.5`, `var coins_label: Label`, `var next_button: Button`, `func open() -> void`, `func close() -> void`, `func show_tab(t: Tab) -> void`, `func refresh() -> void` (Task 5 fills cards here), `func _next() -> void`.
  - `Main.Phase.SHOP`, `Main.shop: Shop`, `Main.open_shop() -> void` (only from SUMMARY), `Main.next_round()` (now only from SHOP), `Main.AUTOPLAY_SHOP_WAIT := 1.5`.
  - Dev flags `--coins=N`, `--shop`.

- [ ] **Step 1: Write the failing tests**

`check_round.gd`: `_last_call_auto_serve` and `_next_round_resets_and_reads_stats` call `main.open_shop()` before `main.next_round()`; add (run it right after `_next_round_resets_and_reads_stats`):

```gdscript
func _summary_leads_to_the_shop() -> void:
	_to_playing()
	main.time_left = 0.01
	_run(0.1)
	expect(main.phase == Main.Phase.SUMMARY, "the round ended")
	main.next_round()
	expect(main.phase == Main.Phase.SUMMARY, "next_round does nothing from the summary")
	main.summary.input_lock = 0.0
	main.summary._next()
	expect(main.phase == Main.Phase.SHOP and main.shop.visible and not main.summary.visible, "the summary's button opens the shop")
	expect(not main.visible and not main.hud.visible, "the bar and the HUD are hidden in the shop")
	var round_before: int = GameState.round_number
	_run(1.0, true)
	expect(main.phase == Main.Phase.SHOP and main.pourer.tilt == 0.0, "nothing ticks in the shop")
	main.shop.input_lock = 0.0
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	main.shop._unhandled_input(space)
	expect(main.phase == Main.Phase.INTRO and GameState.round_number == round_before + 1, "Space in the shop starts the next round")
	expect(main.visible and main.hud.visible and not main.shop.visible, "...and brings the bar back")
	main.summary.input_lock = 0.5
	main.shop.input_lock = 0.5
```

`check_ui.gd`: after the summary tests:

```gdscript
	eq(summary._button.text, "TO THE SHOP  (SPACE)", "the summary leads to the shop")
	var shop: Shop = load("res://shop.gd").new()
	add_child(shop)
	eq(shop.visible, false, "the shop starts hidden")
	shop.open()
	eq(shop.next_button.text, "NEXT ROUND  (SPACE)", "NEXT ROUND button")
	var left := [false]
	shop.next_pressed.connect(func() -> void: left[0] = true)
	shop._unhandled_input(space)
	shop._next()
	eq(left[0] == false and shop.visible, true, "Space and the button are ignored right after the shop opens")
	shop.input_lock = 0.0
	shop._unhandled_input(space)
	eq(left[0] and not shop.visible, true, "Space in the shop emits next_pressed and hides it")
```

- [ ] **Step 2: Run to verify they fail**

Run: `--check=round` and `--check=ui`. Expected: FAIL (`open_shop`/`Shop` missing).

- [ ] **Step 3: Paint the shop background**

`tools/background/shop.html`, modelled on `bar.html` (same `layer()`/`glow()`/gradient helpers, seeded `rng`, `?export` → `PNGSTART…PNGEND`): a 640×360 canvas in HUD units at `PPU = 4` (2560×1440). Content per the spec's Background section: tall dark-wood glass-front cabinets with backlit shelves of varied bottles and brass plaques along the back and left, a red-lacquered wine wall on the right, recessed ceiling spots with soft downlight cones, a warm plank floor, a dark polished table in the foreground. Far layers blurred ~2.5 image px, mid ~1.6, a darkened soft area where the content panel sits (x 40–600, y 40–310), a gentle vignette. Brighter and warmer than the bar, but no highlight near white.
`tools/make_background.sh`: take target names (`bar` → `art/background.png`, `shop` → `art/shop_background.png`; no argument = both), one Chrome run per target. Run `tools/make_background.sh shop` (leave `art/background.png` untouched), then `--import`; set the import to mipmaps like `background.png.import`.

- [ ] **Step 4: Implement the shop screen and flow**

- `shop.gd` (header doc: full-screen shop between rounds, built in code in 640×360 HUD units like `Hud`): layer 2; root `Control` with a Fredoka theme; `TextureRect` of the background (full rect, `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`, stretch scale); the coin pill at `Hud.PILL_AT` (pill style + `Hud.Coin` + label, sized to the text); three tab buttons centred at y 8 (84×22 each, 6 apart; active gold with INK text, others dark pill with FROST text; clicking calls `show_tab`); a translucent content panel `Rect2(40, 40, 560, 270)` (`Hud.pill_style(14)`, INK at 0.72); `next_button` gold 160×26 at (470, 326), styled like the summary's. `open()` refreshes, records the time and shows; `close()` hides; Space (physical, not echo) and the button call `_next()`, ignored for `input_lock` s; `_next()` hides and emits. The last tab persists across `open()` calls.
- `main.tscn`: a `Shop` `CanvasLayer` node with `shop.gd`, after `RoundSummary`.
- `main.gd`: `Phase.SHOP`; `summary.next_pressed → open_shop`, `shop.next_pressed → next_round`; `open_shop()` guards SUMMARY, enters SHOP, hides the summary, hides the world (`visible = false` on Main, `hud.visible = false`) and opens the shop; `next_round()` guards SHOP, shows the world, increments the round, `start_round()`; `tick()` in SHOP only advances `phase_time`; autoplay: SUMMARY after `AUTOPLAY_SUMMARY_WAIT` → `open_shop()`, SHOP after `AUTOPLAY_SHOP_WAIT` → `next_round()`; `--coins=N` sets `GameState.coins` at startup; `--shop` starts in the shop (enter SUMMARY, `open_shop()`) instead of `start_round()`. Update the header's flag list and phase line.
- `round_summary.gd`: button text `TO THE SHOP  (SPACE)`; doc: Space/the button now lead to the shop.

- [ ] **Step 5: Run the checks**

Run: `--import`, then `--check=all`. Expected: all OK.

- [ ] **Step 6: Screenshot the shop and show the user**

```bash
"$GODOT" --path . --windowed --resolution 1280x720 -- --shop --coins=42 --shots=$S/shop --shot-every=1 --quit=3 2>&1 | grep -i "error" ; true
```
Expected: no `SHADER ERROR`/script errors; `$S/shop_02.png` shows the blurred liquor shop filling the screen, coins 42, tabs, NEXT ROUND, nothing of the bar or HUD. Show it to the user and carry on (adjustments come in playtest).

- [ ] **Step 7: Commit**

```bash
git add -A tools/background tools/make_background.sh art/shop_background.png* shop.gd* main.gd main.tscn round_summary.gd tools/checks
git commit -m "Shop screen between rounds: liquor-shop background, tabs, NEXT ROUND; summary leads to it"
```

---

### Task 3: Ice and lime in the glass

The glass holds garnishes: falling then landed ice that displaces liquid (drawn and scored at the iced level, overflow spills), a lime wedge that drops onto the left rim. Drawing helpers shared with the shop cards.

**Files:**
- Create: `garnish_art.gd`
- Modify: `glass.gd`, `palette.gd`
- Test: `tools/checks/check_glass.gd`

**Interfaces:**
- Consumes: `GarnishDef` (Task 1).
- Produces:
  - `Glass`: `signal garnish_landed(g: GarnishDef, at: Vector2)` (global, where it landed), `const ICE_FALL_TIME := 0.35`, `const LIME_DROP_TIME := 0.25`, `var garnishes: Array[GarnishDef]` (added to this glass, in order), `var show_marks := true` (band and fill line; previews turn it off), `func add_garnish(g: GarnishDef) -> bool` (false if already on), `func has_garnish(id: StringName) -> bool`, `func garnish_busy() -> bool` (one still falling), `func displaced(liquid: float) -> float`, `func surface_level(liquid: float) -> float`, `func max_liquid() -> float`. `rows_from_line(vol)` now measures `surface_level(vol)`.
  - `class_name GarnishArt` (static): `ice_outline(center: Vector2, size: float, angle: float) -> PackedVector2Array`, `draw_ice_body(ci: CanvasItem, center: Vector2, size: float, angle: float)`, `draw_ice_edges(ci: CanvasItem, center: Vector2, size: float, angle: float)`, `lime_polygons(slit: Vector2, radius: float, angle: float) -> Array[PackedVector2Array]` (peel, flesh), `draw_lime(ci: CanvasItem, slit: Vector2, radius: float, angle: float)`.
  - `Palette.LIME_PEEL` (`#3e8948`), `Palette.LIME_FLESH` (`#d4ec8e`).

- [ ] **Step 1: Write the failing tests** (`check_glass.gd`, called from `run()` before `_check_wine`; `_steps(glass, s)` = step the glass at `DT` for `s` seconds)

```gdscript
func _check_ice(glass: Glass, water: DrinkDef) -> void:
	var ice: GarnishDef = water.garnishes[0]
	glass.setup(water)
	glass.place(HOME)
	var landed := []
	glass.garnish_landed.connect(func(g: GarnishDef, _at: Vector2) -> void: landed.append(g.id))
	expect(glass.add_garnish(ice) and not glass.add_garnish(ice), "ice goes in once")
	expect(glass.garnish_busy() and glass.displaced(glass.target) == 0.0, "falling ice displaces nothing yet")
	_steps(glass, Glass.ICE_FALL_TIME + DT)
	expect(not glass.garnish_busy() and landed == [&"ice"], "it lands after ICE_FALL_TIME, once")
	near(glass.surface_level(0.0), glass.level_for(0.0), "ice in an empty glass makes no water level")
	var rows := glass.rows_from_line(glass.target)
	expect(rows >= 4 and rows <= 6, "ice raises the surface at the line by 4-6 rows (%d)" % rows)
	var prev := INF
	var rising := true
	var v := 0.0
	while v <= glass.max_liquid():
		rising = rising and glass.surface_level(v) <= prev
		prev = glass.surface_level(v)
		v += 5.0
	expect(rising, "the iced level rises with every 5 px² poured")
	near(glass.surface_level(glass.max_liquid()), glass.level_for(glass.capacity), "max_liquid fills an iced glass to the rim", 0.01)
	glass.receive(HOME.x, glass.target * 0.7, 0.0)
	_steps(glass, 3.0)
	near(_drawn_top(glass), glass.surface_level(glass.volume), "a calm iced glass is drawn at the iced level", 0.05)
	glass.receive(HOME.x, glass.capacity, 0.0)
	near(glass.volume, glass.max_liquid(), "an iced glass holds max_liquid", 0.01)
	expect(glass.spilled > 0.5, "...and the rest spills")
	glass.setup(water)
	glass.place(HOME)
	glass.receive(HOME.x, glass.capacity - 4.0 * 38.0, 0.0)
	glass.add_garnish(ice)
	_steps(glass, Glass.ICE_FALL_TIME + DT)
	expect(glass.spilled > 0.5 and glass.volume <= glass.max_liquid() + 0.01, "ice into a nearly full glass overflows")
	for i in ice.cube_count:
		expect(not Geometry2D.triangulate_polygon(GarnishArt.ice_outline(Vector2.ZERO, ice.cube_size, 0.3 * i)).is_empty(), "ice cube %d triangulates" % i)
	glass.arrive(water, HOME)
	expect(glass.garnishes.is_empty() and not glass.garnish_busy() and glass.displaced(1000.0) == 0.0, "an arriving glass is bare")


func _check_lime(glass: Glass, water: DrinkDef) -> void:
	var lime: GarnishDef = water.garnishes[1]
	glass.setup(water)
	glass.place(HOME)
	glass.receive(HOME.x, glass.target, 0.0)
	expect(glass.add_garnish(lime) and glass.garnish_busy(), "the lime drops onto the rim")
	_steps(glass, Glass.LIME_DROP_TIME + DT)
	expect(not glass.garnish_busy() and glass.has_garnish(&"lime"), "...and sits there")
	eq(glass.rows_from_line(glass.volume), 0, "the lime doesn't change the level")
	for poly in GarnishArt.lime_polygons(Vector2.ZERO, 7.0, -0.6):
		expect(not Geometry2D.triangulate_polygon(poly).is_empty(), "the lime's polygons triangulate")
```

(`_drawn_top(glass)` = the smallest y of `glass.liquid_polygon()`, reusing whatever `_check_drawn_liquid` already measures.)

- [ ] **Step 2: Run to verify it fails**

Run: `--check=glass`. Expected: FAIL (`add_garnish` missing).

- [ ] **Step 3: Implement**

Ice model in `glass.gd` (n = `cube_count`, s = `cube_size`, f = `float_share`, floor = local y of the interior's bottom row edge):

```
displaced(liquid) = 0 without landed ice, else n·s·min(depth, f·s), depth = floor − surface_level(liquid)
surface_level(liquid):
  L = level_for(liquid + f·n·s²)                  # floating
  if floor − L >= f·s: return L
  else walk rows up from the floor with free area max(row_area − n·s, 0.5) per row
       until `liquid` is used up (shallow: cubes rest on the floor)
max_liquid() = capacity − (f·n·s² if ice landed else 0)
```

- `_level` (drawing, shader `surface_y`, `liquid_polygon`, `_surface_local`) uses `surface_level(volume)`; `_target_y` stays `level_for(target)`; `receive()` and an ice landing clamp `volume` to `max_liquid()`, adding the excess to `spilled` with drips as today.
- Garnish timers advance in `step()` (deterministic). Ice lands at `ICE_FALL_TIME`: emit `garnish_landed`, kick the waves under the cubes when there is water. Lime lands at `LIME_DROP_TIME` with a small bounce in its drawn offset. `reset()` clears garnishes (so `setup`/`arrive` start bare).
- Cubes (visual): x spread evenly across the span at the surface with fixed per-cube offsets and tilts; cube bottom = `min(floor, level + f·s)` plus the wave at its column, a slow fixed-phase drift/tilt with the wave slope; falling cubes start just above the view (local y ≈ −215) and accelerate in (ease-in over `ICE_FALL_TIME`) with a tumble that settles. `draw_ice_body` in `Back` after the frost (so the liquid shader refracts/tints the submerged part); `draw_ice_edges` in `Front` after the walls.
- Lime (visual): slit on the left rim (`outer_x_at(rim)` left + ~1.5 px, rim y), radius ~7 px, standing up and out to the left (peel outward, flesh with segment lines and a juicy highlight, as in the spec); drawn in `Front` after the drips and before `_draw_band`/`_draw_fill_line`, which stay last. `show_marks` gates `_draw_band` and `_draw_fill_line`.
- `garnish_art.gd`: the static helpers in Interfaces, colours from `Palette` (ice from `FROST`/`WHITE` alphas; lime from the two new entries).

- [ ] **Step 4: Run the checks and a windowed shader run**

Run: `--import`, `--check=all` (all OK); then
`"$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --seed=11 --shots=$S/t3 --shot-every=5 --quit=6 2>&1 | grep -i "shader error\|script error"` → no output.

- [ ] **Step 5: Commit**

```bash
git add -A glass.gd garnish_art.gd* palette.gd tools/checks/check_glass.gd
git commit -m "Glass holds garnishes: falling ice that raises the level, a lime wedge on the rim"
```

---

### Task 4: Garnishes in play

UP/LEFT add garnishes, serving waits for them, the hint names them, the score pays them, ice splashes; the autopilot buys and garnishes so autoplay shows it all.

**Files:**
- Modify: `main.gd`, `effects.gd`, `autopilot.gd`
- Test: `tools/checks/check_round.gd`, `tools/checks/check_ui.gd`

**Interfaces:**
- Consumes: Task 1 (`owns_garnish`, `buy_*`, `Scoring.score(..., garnishes)`), Task 2 (`Phase.SHOP`), Task 3 (`Glass.add_garnish`, `garnish_busy`, `garnishes`, `displaced`, `garnish_landed`, `ICE_FALL_TIME`).
- Produces: `Main.try_garnish(key: Key) -> bool`, `Main.hint_text() -> String`, `Effects.splash(at: Vector2, color: Color)`, `Autopilot.decide()` result gains `"keys": Array[Key]`, `Autopilot.shop(main: Main) -> void` (buys ice, lime, wine in that order while affordable, through `GameState` here; Task 5 routes it through the shop).

- [ ] **Step 1: Write the failing tests** (`check_round.gd`)

```gdscript
func _own_garnishes() -> void:
	GameState.coins = 25
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	GameState.buy_garnish(GameState.WATER.garnishes[1])


func _garnish_keys_follow_the_rules() -> void:
	_fresh()
	expect(not main.try_garnish(KEY_UP), "nothing during INTRO")
	_run(Main.INTRO_TIME + DT)
	expect(not main.try_garnish(KEY_UP), "nothing before buying ice")
	eq(main.hint_text(), "HOLD DOWN  pour   ·   SPACE  serve   ·   F1  debug", "plain hint before buying")
	GameState.coins = 10
	GameState.buy_garnish(GameState.WATER.garnishes[0])
	eq(main.hint_text(), "HOLD DOWN  pour   ·   UP  ice   ·   SPACE  serve   ·   F1  debug", "the hint names ice once bought")
	GameState.coins = 15
	GameState.buy_garnish(GameState.WATER.garnishes[1])
	eq(main.hint_text(), "HOLD DOWN  pour   ·   UP  ice   ·   LEFT  lime   ·   SPACE  serve   ·   F1  debug", "...and lime")
	expect(main.try_garnish(KEY_UP) and not main.try_garnish(KEY_UP), "UP adds ice once")
	expect(main.try_garnish(KEY_LEFT) and not main.try_garnish(KEY_DOWN), "LEFT adds lime; other keys don't")
	_run(Glass.ICE_FALL_TIME + DT)  # a serve waits for falling ice
	_serve_with_next(GameState.WATER)
	expect(not main.try_garnish(KEY_UP), "nothing while the next glass arrives")
	_run(0.5)
	expect(main.glass.garnishes.is_empty() and main.try_garnish(KEY_UP), "the next glass arrives bare and takes ice")
	GameState.coins = 80
	GameState.buy_drink(GameState.WINE)
	_serve_with_next(GameState.WINE)
	_run(0.6)
	expect(not main.try_garnish(KEY_UP) and not main.try_garnish(KEY_LEFT), "wine takes no garnish")
	eq(main.hint_text(), "HOLD DOWN  pour   ·   SPACE  serve   ·   F1  debug", "plain hint on wine")
	main.time_left = 0.01
	_run(6.0)
	expect(main.phase == Main.Phase.SUMMARY and not main.try_garnish(KEY_UP), "nothing on the summary")
	main.open_shop()
	expect(not main.try_garnish(KEY_UP) and not main.try_garnish(KEY_LEFT), "nothing in the shop")
	main.next_round()
	_run(Main.INTRO_TIME + DT)
	expect(main.glass.garnishes.is_empty(), "nothing carried into the next round")


func _serve_waits_for_falling_ice_and_pays_more() -> void:
	_to_playing()
	_own_garnishes()
	main.try_garnish(KEY_UP)
	main.try_garnish(KEY_LEFT)
	main.glass.receive(Main.GLASS_POS.x, main.glass.target * 0.5, 0.0)
	main.request_serve()
	main.tick(DT, false)
	expect(main.results.is_empty(), "a serve waits while the ice falls")
	_run(Glass.ICE_FALL_TIME)
	eq(main.results.size(), 1, "...and fires once it has landed")
	eq(main.results[0].garnishes, [&"ice", &"lime"], "the score records both garnishes")
	_run(0.5)
	main.try_garnish(KEY_UP)
	main.try_garnish(KEY_LEFT)
	_run(Glass.ICE_FALL_TIME + DT)
	var g := main.glass
	g.receive(Main.GLASS_POS.x, g.target - g.displaced(g.target), 0.0)
	main.streak = 0
	main.request_serve()
	main.tick(DT, false)
	eq([main.results[1].band, main.results[1].coins], [Scoring.PERFECT, 15], "a PERFECT iced lime water pays 15")


func _iced_round_with_autopilot() -> void:
	_fresh()
	GameState.coins = 120
	Autopilot.new().shop(main)
	expect(GameState.owns_garnish(GameState.WATER.garnishes[1]) and GameState.owns_drink(GameState.WINE), "the autopilot buys ice, lime, wine")
	GameState.set_on_menu(GameState.WINE, false)
	main.start_round()
	var pilot := Autopilot.new()
	var t := 0.0
	while main.phase != Main.Phase.SUMMARY and t < 60.0:
		var d := pilot.decide(main)
		for k in d.keys:
			main.try_garnish(k)
		if d.serve:
			main.request_serve()
		main.tick(DT, d.hold)
		t += DT
	var garnished := 0
	var good := 0
	for r in main.results:
		garnished += 1 if r.garnishes.size() == 2 else 0
		good += 1 if r.band == Scoring.PERFECT or r.band == Scoring.GOOD else 0
	expect(main.results.size() >= 4 and garnished == main.results.size(), "every autoplayed water glass is iced and limed (%d of %d)" % [garnished, main.results.size()])
	expect(good * 2 >= main.results.size(), "...and most land GOOD or better (%d of %d)" % [good, main.results.size()])
```

`check_ui.gd` (Effects section): `fx.splash(Vector2(100, 200), Palette.WATER)` adds 3–6 bits that are gone after 3 s.

- [ ] **Step 2: Run to verify they fail**

Run: `--check=round`, `--check=ui`. Expected: FAIL (`try_garnish`, `hint_text`, `splash` missing).

- [ ] **Step 3: Implement**

- `main.gd`: `try_garnish(key)` adds the current drink's garnish with that key when the phase is PLAYING or LAST_CALL, `_summary_in < 0`, the glass is visible and not arriving, and `GameState.owns_garnish(g)`; returns `glass.add_garnish(g)`. `_unhandled_input`: `KEY_UP`, `KEY_LEFT` → `try_garnish`. The serve fires only when also `not glass.garnish_busy()`; the LAST_CALL idle counts `glass.garnish_busy()` as activity. `_serve()` passes `glass.garnishes` to `Scoring.score`. `hint_text()` builds the hint from `drink.garnishes` the player owns (`"UP  ice"` = `OS.get_keycode_string(g.key).to_upper()` + two spaces + `g.display_name.to_lower()`), joined with `"   ·   "`; `_refresh_hud` uses it (SERVING…/REFILLING… still override); `HINT` goes. `glass.garnish_landed` → `effects.splash(at, drink.liquid_highlight)` for ICE when the glass holds ≥ 0.5 px². Autoplay: apply `d.keys` via `try_garnish`; in SHOP after the wait call `_autopilot.shop(self)` before `next_round()`. Debug readout gains the garnish ids.
- `effects.gd`: `splash(at, color)` — 3–6 DOT droplets thrown up and out with gravity.
- `autopilot.gd`: `decide()` adds `"keys"`: on a landed glass, each owned garnish of the drink not yet on the glass (ice first). The release test counts `glass.displaced(glass.volume)` on top of `glass.volume + stream.in_flight_volume()`. `shop(main)` buys in the order ice, lime, wine while affordable.

- [ ] **Step 4: Run all checks; tune the autopilot if needed**

Run: `--check=all`. Expected: all OK. If `_iced_round_with_autopilot` lands fewer than half GOOD, add an `&"water_iced"` share to `release_at` and use it when the glass has landed ice.

- [ ] **Step 5: Screenshots**

```bash
"$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --shop --coins=120 --seed=11 --shots=$S/t4 --shot-every=0.5 --quit=40 2>&1 | grep -i "shader error\|script error"; true
```
Expected: no errors; frames show ice tumbling in and floating, the lime on the left rim with the bracket and target marker drawn over it, splashes, the hint naming UP/LEFT on water glasses, wine glasses too (round 2 opens with wine).

- [ ] **Step 6: Commit**

```bash
git add main.gd effects.gd autopilot.gd tools/checks
git commit -m "Garnishes in play: UP ice, LEFT lime, serving waits for them, bonus paid, hint and autopilot"
```

---

### Task 5: Shop cards — upgrades, drinks and the menu

**Files:**
- Create: `shop_card.gd`, `vessel_preview.gd`, `liquid_glass.tres`, `liquid_pourer.tres`
- Modify: `shop.gd`, `main.tscn` (the two liquid `ShaderMaterial` sub-resources become those `.tres` ext-resources, same values), `autopilot.gd` (`shop()` buys through `main.shop.buy`)
- Test: `tools/checks/check_shop.gd`

**Interfaces:**
- Consumes: Task 1 (`GameState` purchase API, `DRINKS`, `price`, `garnishes`), Task 2 (`Shop` skeleton, `refresh()`), Task 3 (`GarnishArt`, `Glass.show_marks`).
- Produces:
  - `Shop`: `enum CardState { CAN_BUY, CANT_AFFORD, OWNED }`, `static func card_state(price: int, owned: bool, coins: int) -> CardState`, `func state_of(item: Resource) -> CardState`, `func buy(item: Resource) -> bool` (DrinkDef or GarnishDef; refreshes), `func toggle(d: DrinkDef) -> bool`, `var cards: Array[ShopCard]` (the current tab's, in order).
  - `class_name ShopCard extends Panel`: `var item: Resource`, `var buy_button: Button`, `var toggle_button: Button`, `var badge: Label` (OWNED), `var note: Label` (`At least one drink`).
  - `class_name VesselPreview extends Node2D`: `enum Kind { GLASS, POURER }`, `func _init(d: DrinkDef, kind: Kind, fill: float)`; builds the vessel with `Back`/`Liquid`/`Front` `DrawLayer`s in `_ready()` (Liquid material = a duplicate of `liquid_glass.tres` / `liquid_pourer.tres`), then `setup`/`place(Vector2.ZERO)`; a glass gets `show_marks = false`, `fill × capacity` liquid and one `step` so its level is set; a pourer is set up from a duplicate of the `DrinkDef` with `pourer_rest_deg = 0` (upright, liquid level).

- [ ] **Step 1: Write the failing tests** (append to `check_shop.gd`'s `run()`)

```gdscript
	eq([Shop.card_state(10, false, 9), Shop.card_state(10, false, 10), Shop.card_state(10, true, 0)],
		[Shop.CardState.CANT_AFFORD, Shop.CardState.CAN_BUY, Shop.CardState.OWNED], "card states")
	GameState.reset_session(1)
	GameState.coins = 5
	var shop: Shop = load("res://shop.gd").new()
	add_child(shop)
	shop.open()
	eq(shop.tab, Shop.Tab.UPGRADES, "the shop opens on UPGRADES the first time")
	eq(shop.cards.map(func(c: ShopCard) -> Resource: return c.item), [ice, lime], "UPGRADES: water's ice and lime")
	expect(shop.state_of(ice) == Shop.CardState.CANT_AFFORD and shop.cards[0].buy_button.disabled, "5 coins: ice is greyed out")
	GameState.coins = 20
	shop.open()
	expect(shop.state_of(ice) == Shop.CardState.CAN_BUY and not shop.cards[0].buy_button.disabled, "coins earned since: reopening refreshes the cards")
	shop.cards[0].buy_button.pressed.emit()
	shop.cards[0].buy_button.pressed.emit()
	eq(GameState.coins, 10, "a double click on BUY spends 10 once")
	expect(shop.state_of(ice) == Shop.CardState.OWNED and shop.cards[0].badge.visible, "ice shows OWNED")
	eq(shop.coins_label.text, "10", "the coin pill follows")
	shop.show_tab(Shop.Tab.DRINKS)
	eq(shop.cards.map(func(c: ShopCard) -> Resource: return c.item), [wine], "DRINKS: wine")
	GameState.coins = 80
	shop.show_tab(Shop.Tab.DRINKS)
	expect(shop.buy(wine) and GameState.menu.has(wine) and shop.state_of(wine) == Shop.CardState.OWNED, "wine bought, on the menu")
	shop.show_tab(Shop.Tab.MENU)
	eq(shop.cards.map(func(c: ShopCard) -> Resource: return c.item), [water, wine], "MENU: a card per owned drink")
	expect(shop.toggle(water) and not GameState.menu.has(water), "water switched off")
	expect(not shop.toggle(wine) and shop.cards[1].toggle_button.disabled and shop.cards[1].note.visible, "the last drink on can't be switched off")
	shop.close()
	shop.open()
	eq(shop.tab, Shop.Tab.MENU, "the shop reopens on the last tab")
	shop.toggle(water)
	expect(GameState.menu.size() == 2, "water back on")
```

- [ ] **Step 2: Run to verify it fails**

Run: `--check=shop`. Expected: FAIL (`card_state`/`cards` missing).

- [ ] **Step 3: Implement**

- `liquid_glass.tres` / `liquid_pourer.tres`: the two `ShaderMaterial`s from `main.tscn` (glass: lens 0.35, wobble 0.6, edge 0.2; pourer: 0.3, 0.6, 0.15), referenced by `main.tscn` as ext-resources (update `load_steps`).
- `vessel_preview.gd` per Interfaces.
- `shop_card.gd`: a 150×200 card (rounded dark panel, lighter on hover): a picture area (top ~100 units, its picture node centred), the name (Fredoka 700, 14), one or two lines (9–10), and the bottom row: price with a `Hud.Coin` + BUY (gold pill; disabled and the card dimmed when unaffordable), or OWNED, or an ON/OFF toggle (gold ON / dim OFF) for the menu, with the `At least one drink` note under a disabled toggle. Clicking a menu card anywhere toggles it. A short scale pop on buy.
- `shop.gd` `refresh()` rebuilds the current tab's cards inside the content panel, centred in a row (16 apart), and updates the coin pill:
  - UPGRADES: a header (`display_name.to_upper()`, e.g. `WATER`) per owned drink with garnishes, then a card per garnish: name, `description`, `"%s to add" % OS.get_keycode_string(key).to_upper()`, price; picture: `DrawLayer` calling `GarnishArt` (three cubes / the wedge).
  - DRINKS: a card per drink in `GameState.DRINKS` with `price > 0`: name, `"Pays %d / %d / %d"` from its coins, price; picture: `VesselPreview` pourer (wine bottle, upright), scaled to fit.
  - MENU: a card per owned drink: name, toggle; picture: `VesselPreview` glass at its `fill_fraction`.
  - `buy()` calls `GameState.buy_drink`/`buy_garnish` and refreshes; `toggle()` calls `set_on_menu(d, not on)` and refreshes.
- `autopilot.gd` `shop()` calls `main.shop.buy(item)`.

- [ ] **Step 4: Run all checks and screenshot each tab**

Run: `--import`, `--check=all` → all OK. Then, for each tab, a windowed `--shop --coins=200` run (temporarily switch the opening tab with a local edit or click through by calling `show_tab` from a throwaway `--shop-tab=N` flag removed before commit) with `--shots`, grepping for `SHADER ERROR`. Expected: cards readable at 1280×720, pictures in the game's style, wine bottle refracting the shop behind it.

- [ ] **Step 5: Commit**

```bash
git add -A shop.gd shop_card.gd* vessel_preview.gd* liquid_glass.tres liquid_pourer.tres main.tscn autopilot.gd tools/checks/check_shop.gd
git commit -m "Shop cards: buy ice, lime and wine; toggle next round's drinks"
```

---

### Task 6: Docs and final verification

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-10-18-upgrade-shop-design.md` (status line)

- [ ] **Step 1: Full verification**

```bash
"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all
"$GODOT" --headless --path . -- --sweep > $S/sweep_water_after.txt 2>&1 && diff $S/sweep_water_before.txt $S/sweep_water_after.txt
"$GODOT" --headless --path . -- --sweep=wine > $S/sweep_wine_after.txt 2>&1 && diff $S/sweep_wine_before.txt $S/sweep_wine_after.txt
"$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --seed=11 --coins=0 --shots=$S/final --shot-every=1.5 --quit=110 2>&1 | grep -i "shader error\|script error"; true
```
Expected: 12 OK lines; both diffs empty; no errors; the frames show round 1 water, the summary, the shop (autopilot buys as coins allow), later rounds with garnished water and, once affordable, wine.

- [ ] **Step 2: Update `CLAUDE.md`**

Current state (slice 3 implemented, awaiting playtest), commands (`--coins=N`, `--shop`, `tools/make_background.sh [bar|shop]`), checks list (`check_shop`), architecture (SHOP phase, `GarnishDef`/`garnishes/`, `GameState` purchases/menu/`new_drinks` replacing `ROUND_UNLOCKS`, scoring bonus, glass garnishes and the iced level, `GarnishArt`, `VesselPreview`, `shop.gd`/`shop_card.gd`, the liquid materials as `.tres`), next slices (stat upgrades, wine garnishes), known deferred work.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers
git commit -m "docs: describe slice 3 (shop, garnishes, drink menu)"
```
