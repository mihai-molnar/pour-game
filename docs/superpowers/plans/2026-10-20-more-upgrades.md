# More Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sell five always-on upgrades in the shop — sparkling water (+40 %), premium (+40 %) and vintage (+60 %, replaces premium) wine, and a 50 % faster refill for water and for wine — with fizz for sparkling water and nicer labels for premium and vintage wine.

**Architecture:** A new `UpgradeDef` resource listed per drink (`DrinkDef.upgrades`); `GameState` owns the purchases and answers per-drink questions (`active_upgrades`, `refill_time`, `fizz`, `label_look`); `Scoring` adds upgrade bonuses to garnish bonuses; vessels read GameState at the points they already read `stats.refill_time` / `def.fizz`; the shop lists the upgrades in the existing UPGRADES sections.

**Tech Stack:** Godot 4.5.1, GDScript; headless checks via `tools/run_check.gd`.

**Spec:** `docs/superpowers/specs/2026-10-20-more-upgrades-design.md`

## Global Constraints

- Prices: sparkling 25, water refill 30, premium 50, vintage 70, wine refill 50. Bonuses: sparkling 0.4, premium 0.4, vintage 0.6; refill speed 0.5 (time / 1.5).
- Upgrade bonuses add to garnish bonuses: `roundi(base × (1 + Σ bonus))`, before the streak and `coin_mult`; MISS and SPILL unchanged.
- `--sweep`, `--sweep=wine`, `--sweep=beer` byte-identical to `master` (baseline saved in the scratchpad before work began).
- Gameplay deterministic; new randomness visual only (`randf`).
- Colours via `Palette`; drawn polygons must triangulate; shop text ≥ 9 units; every line description fits its 158-unit label.
- `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`; checks: `"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=<name>`; success = `check_<name>: OK`. Run `--import` after adding a `class_name`.

## Review Focus

1. Vintage clicked while premium isn't owned (with coins for both) → nothing bought; the line is faded and unclickable. Test in Task 1 (GameState) and Task 3 (shop line state).
2. Buying wine and then its upgrades in the same shop visit (e.g. `--shop --coins=300`) → wine's section turns from blacked-out rows into real lines as soon as the UPGRADES page is shown again. Test in Task 3.
3. A wine bottle refill with the upgrade and `stats.refill_time` changed too → the two multiply (0.5 s base → 0.33 s; the uncork never below `MIN_UNCORK`). Test in Task 2.
4. Sparkling water's fizz in a glass being filled, drained by a serve, and in the ice-filled glass → no bubble ever outside the interior. Test in Task 4 (check_bubbles, sparkling water with ice).
5. Upgrades owned for a drink that is switched off the menu → they do nothing for other drinks (water's sparkling doesn't touch wine's pay or fizz). Test in Task 1 (scoring per drink).

---

### Task 1: Upgrade data, purchases and pay

**Files:**
- Create: `upgrade_def.gd`, `upgrades/sparkling.tres`, `upgrades/water_refill.tres`, `upgrades/premium.tres`, `upgrades/vintage.tres`, `upgrades/wine_refill.tres`
- Modify: `drink_def.gd` (Shop group), `drinks/water.tres`, `drinks/wine.tres`, `game_state.gd`, `scoring.gd`, `main.gd` (`_serve`)
- Test: `tools/checks/check_shop.gd`, `tools/checks/check_scoring.gd`

**Interfaces:**
- Produces: `class_name UpgradeDef extends Resource` with `enum LabelLook { PLAIN, PREMIUM, VINTAGE }`, exports `id: StringName`, `display_name`, `description`, `price: int`, `bonus: float`, `refill_speed: float`, `replaces: UpgradeDef`, `fizz: float`, `label_look: LabelLook`.
- `DrinkDef.upgrades: Array[UpgradeDef]` (water: sparkling, water_refill; wine: premium, vintage, wine_refill; beer: none).
- `GameState.owned_upgrades: Array[StringName]`, `owns_upgrade(u) -> bool`, `drink_of(u) -> DrinkDef`, `buy_upgrade(u) -> bool`, `active_upgrades(d) -> Array[UpgradeDef]`, `refill_time(d) -> float`, `fizz(d) -> float`, `label_look(d) -> UpgradeDef.LabelLook`.
- `Scoring.garnished_coins(base, garnishes, upgrades: Array[UpgradeDef] = [])`, `Scoring.score(..., garnishes, upgrades: Array[UpgradeDef] = [])`.

- [ ] **Step 1: Failing tests**

check_shop (GameState part), after the existing purchase checks:
```gdscript
var sparkling: UpgradeDef = water.upgrades[0]
var premium: UpgradeDef = wine.upgrades[0]
var vintage: UpgradeDef = wine.upgrades[1]
GameState.reset_session(1)
GameState.coins = 500
expect(GameState.buy_upgrade(sparkling) and GameState.coins == 475, "sparkling costs 25")
expect(not GameState.buy_upgrade(sparkling), "...once")
expect(not GameState.buy_upgrade(premium) and GameState.coins == 475, "wine's upgrades need wine")
GameState.buy_drink(wine)
expect(not GameState.buy_upgrade(vintage), "vintage needs premium first")
expect(GameState.buy_upgrade(premium) and GameState.buy_upgrade(vintage), "premium 50, then vintage 70")
eq(GameState.active_upgrades(wine), [vintage], "vintage replaces premium")
expect(GameState.buy_upgrade(water.upgrades[1]) and is_equal_approx(GameState.refill_time(water), 1.0 / 1.5), "water refill: 0.67 s")
eq(GameState.refill_time(wine), 1.0, "...not wine's")
expect(GameState.fizz(water) > 0.0 and GameState.fizz(wine) == 0.0 and GameState.fizz(GameState.BEER) == GameState.BEER.fizz, "sparkling fizzes water only")
eq(GameState.label_look(wine), UpgradeDef.LabelLook.VINTAGE, "vintage label")
GameState.reset_session(1)
expect(GameState.owned_upgrades.is_empty() and GameState.label_look(wine) == UpgradeDef.LabelLook.PLAIN, "reset clears upgrades")
```
check_scoring: water with `[sparkling]` and `[ice, lime]` → PERFECT/GOOD/GOOD ENOUGH coins `[19, 11, 6]`; sparkling alone `[14, 8, 4]`; wine `[premium]` → `[21, 13, 7]`, `[vintage]` → `[24, 14, 8]`; SPILL with sparkling still `-6`; MISS `0`.

- [ ] **Step 2:** Run `--check=shop` and `--check=scoring`; expect FAILED (UpgradeDef unknown / missing methods).
- [ ] **Step 3:** Implement. `buy_upgrade` refuses when owned, `drink_of(u)` not owned, `u.replaces` not owned, or coins short. `active_upgrades(d)` = owned ones of `d.upgrades`, dropping any that another owned one `replaces`. `refill_time(d) = stats.refill_time / (1 + Σ refill_speed)`. `fizz(d) = d.fizz + Σ fizz` (sparkling's fizz starts at 30 /s; tuned in Task 4). `label_look(d)` = highest `label_look` among active upgrades. Main `_serve` passes `GameState.active_upgrades(drink)`. Descriptions: sparkling "Water pays +40%", water_refill "Pitcher refills 50% faster", premium "Wine pays +40%", vintage "Wine pays +60%, not +40%", wine_refill "New bottles open 50% faster" (Task 3 checks they fit).
- [ ] **Step 4:** `--import`, then both checks OK; `--check=all` OK.
- [ ] **Step 5:** Commit "Upgrades: sparkling water, premium and vintage wine, refill speed — data, purchases, pay".

### Task 2: Per-drink refill time

**Files:** Modify `pourer.gd` (`refill_progress`, `_step_refill`); Test `tools/checks/check_pourer.gd`.

**Interfaces:** Consumes `GameState.refill_time(d)`.

- [ ] **Step 1: Failing test** — in check_pourer, with water_refill owned the pitcher's refill (once upright) takes 0.67 s (±0.1); with wine_refill owned the bottle's refill (vanish → pop) takes `maxf(1/1.5, ARRIVE_TIME + MIN_UNCORK)` ≈ 0.67 s; with `stats.refill_time = 0.5` and wine_refill, `maxf(0.333, 0.4)` = 0.4 s (review focus 3). Reuse the existing measuring helpers in check_pourer.
- [ ] **Step 2:** Run `--check=pourer`; FAILED.
- [ ] **Step 3:** Replace the three `GameState.stats.refill_time` reads in `pourer.gd` with `GameState.refill_time(def)`.
- [ ] **Step 4:** `--check=pourer` and `--check=keys` OK.
- [ ] **Step 5:** Commit "Refill speed upgrades shorten that drink's refill".

### Task 3: The shop lines

**Files:** Modify `shop.gd`, `menu_line.gd`, `menu_art.gd`; Test `tools/checks/check_shop.gd`.

**Interfaces:**
- `Shop.CardState` gains `NEEDS` (another upgrade first); `Shop.state_of(item)` handles `UpgradeDef`; `Shop.buy(item)` routes `UpgradeDef` to `GameState.buy_upgrade`.
- `MenuLine.show_price(price, state)` prints `NEEDS` like CANT_AFFORD (faded, disabled).
- `MenuArt.draw_bottle(ci, d, box, look := UpgradeDef.LabelLook.PLAIN)`, `MenuArt.draw_sparkling(ci, d, box)`, `MenuArt.draw_refill(ci, d, box)`, `MenuArt.refill_arrow_polygon(center, radius) -> PackedVector2Array` (triangulated by the check).
- `Shop.UPGRADE_TEASERS = {&"beer": 2}`.

- [ ] **Step 1: Failing tests** (update the existing shop-screen expectations):
  - Fresh session, UPGRADES: items `[ice, lime, sparkling, water_refill]`; `blacked_out_lines() == 3` (wine not owned: its 3 lines blacked out).
  - Wine bought in the same visit (`shop.buy(wine)` from DRINKS, then `show_tab(UPGRADES)`): items `[ice, lime, sparkling, water_refill, premium, vintage, wine_refill]`, `blacked_out_lines() == 0` (review focus 2).
  - Coins 500, premium not owned: `state_of(vintage) == NEEDS`, its line faded and its price disabled; emitting its price button buys nothing (review focus 1); after buying premium `state_of(vintage) == CAN_BUY`.
  - After round 3: `blacked_out_lines() == 2` (beer's).
  - Every line's description label fits: `font.get_string_size(text, …, 9).x <= label.size.x` for all UPGRADES lines.
  - MENU page with vintage owned: wine's description "Pays 24 / 14 / 8".
  - Menu art: `refill_arrow_polygon` and bottle polygons with each look triangulate.
- [ ] **Step 2:** `--check=shop` FAILED.
- [ ] **Step 3:** Implement. UPGRADES section per unlocked drink: if owned, its garnish lines then its upgrade lines (description from the .tres); if not owned, one blacked-out row per garnish + upgrade; then the teasers. MENU "Pays" applies `Scoring.garnished_coins(…, [], active_upgrades)`. Pictures: sparkling = water glass + a few bubble rings; refill = the pourer + a curved arrow; premium/vintage = wine bottle with that look (label `CAP_GOLD` / dark `WINE` with gold rule).
- [ ] **Step 4:** `--check=shop` OK; screenshot `--shop --coins=300` to eyeball the page.
- [ ] **Step 5:** Commit "Shop: the new upgrades on the UPGRADES page".

### Task 4: Sparkling water fizzes

**Files:** Modify `glass.gd` (fizz from `GameState.fizz(def)`, wall bubbles, surface glints), `pourer.gd` (bubbles in the pitcher's water when its drink's upgrade fizz > 0); `drinks`/`upgrades/sparkling.tres` (fizz rate); Test `tools/checks/check_bubbles.gd`.

**Interfaces:** `Glass.fizz: float` (set in `reset()` from `GameState.fizz(def)`); `Pourer.bubbles: Array[Vector3]` (local x, y, speed; visual).

- [ ] **Step 1: Failing test** — check_bubbles: still water (nothing bought) pours spawn no floor fizz once the stream has stopped and the bubbles have risen (none after 2 s idle); with sparkling bought, water (also with ice) shows bubbles 2 s after the pour stops, none outside the interior; pitcher bubbles all inside `pourer.liquid_polygons()` on every tick (review focus 4).
- [ ] **Step 2:** `--check=bubbles` FAILED.
- [ ] **Step 3:** Implement. Glass: `fizz` replaces `def.fizz` in `reset`, `receive_local`, `_bubble_cap`, `step`; sparkling bubbles rise 12–24 px/s; wall bubbles: 6–10 static tiny dots on the inner walls below the surface (positions picked in `reset`, drawn only below the calm level); glints: a bubble popping at a foam-less surface leaves a 0.15 s fading spark 0.5 px above it. Pourer: if `GameState.fizz(def) - def.fizz > 0` spawn bubbles at random points in the liquid (rejection-sample its bounds against `liquid_polygons()`), rise toward world-up (`Vector2.UP.rotated(-rotation)`), pop outside the liquid; cap 30; drawn in Front before the label.
- [ ] **Step 4:** `--check=bubbles`, `--check=glass`, `--check=pourer` OK; windowed screenshot of a sparkling glass and pitcher (`--autoplay` after buying sparkling via a temporary flag or `--shop --coins`), check the surface still reads.
- [ ] **Step 5:** Commit "Sparkling water fizzes, in the glass and the pitcher".

### Task 5: Premium and vintage labels

**Files:** Modify `pourer.gd` (`_draw_label`, `_draw_foil` by `GameState.label_look(def)`), `palette.gd` (named colours if needed, e.g. `VINTAGE_LABEL`), `vessel_art.gd` or `pourer.gd` (crest polygon); Test `tools/checks/check_vessel_art.gd`.

**Interfaces:** `Pourer.crest_polygon(center: Vector2, size: float) -> PackedVector2Array` (static).

- [ ] **Step 1: Failing test** — check_vessel_art: `Pourer.crest_polygon` triangulates; drawing the wine pourer's Front with each look logs no errors (call `_draw_front` on a DrawLayer in a SubViewport-free headless run, as the existing art checks do).
- [ ] **Step 2:** `--check=vessel_art` FAILED.
- [ ] **Step 3:** Implement: PREMIUM = cream label + gold double frame, gold grape emblem, gold band at the foil's foot; VINTAGE = dark burgundy label with gold frame, gold crest, gold year "1987" (text drawn at font size 40 scaled down to ~5 world px for crispness), gold foil capsule. Reflection keeps the plain flat copy.
- [ ] **Step 4:** `--check=vessel_art` OK; screenshots of the plain, premium and vintage bottle tipped over a glass.
- [ ] **Step 5:** Commit "Premium and vintage wine labels".

### Task 6: Autopilot, docs, final verification

**Files:** Modify `autopilot.gd` (`SHOPPING` += `&"sparkling", &"premium", &"vintage", &"water_refill", &"wine_refill"`, buying `UpgradeDef`s through `main.shop.buy`), `main.gd` (dev flag `--buy=id,id` to start owning things — for screenshots), `CLAUDE.md`; Test `tools/checks/check_round.gd`.

- [ ] **Step 1:** check_round: with 400 coins and wine owned, `Autopilot.shop` buys sparkling, premium, vintage and both refills.
- [ ] **Step 2–4:** Implement, `--check=all` (every check OK), sweeps diffed against the baseline (identical), autoplay screenshots.
- [ ] **Step 5:** Update `CLAUDE.md` (state, data, GameState, Scoring, shop, glass/pourer notes, dev flag); commit "Autopilot buys the new upgrades; docs".
- [ ] **Step 6:** Fresh-eyes review of the whole branch (superpowers:requesting-code-review), fix findings, then report to the user and ask about merging.
