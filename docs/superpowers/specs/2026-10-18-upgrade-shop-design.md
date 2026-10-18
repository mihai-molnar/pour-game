# Pour Game — Slice 3: The Shop, Garnishes and the Drink Menu

Date: 2026-10-18
Status: Approved (2026-10-18: "looks good"); implemented 2026-10-18, awaiting playtest — plan `docs/superpowers/plans/2026-10-18-upgrade-shop.md`

## Overview

Between rounds the player now visits a shop and spends the coins they earned.
Wine stops arriving by itself in round 2: it becomes a drink you buy. Water
gets two garnishes you can buy, ice and lime. Once you own them you can add
them to any water glass while you serve it (UP drops ice in, LEFT hangs a lime
wedge on the rim), and a garnished glass pays more at every scoring step. Ice
also takes up room in the glass, so it raises the water level and the player
has to allow for it. A third shop tab, the menu, decides which of your drinks
can come up next round, which answers the open question from slice 2 ("let
the player choose the round's drink mix in the shop").

Builds on slices 1–2, the scoring steps and the smooth art style (see
`CLAUDE.md`). Everything not mentioned here (30 s rounds, scoring steps,
streak, last call, arrivals, refills, the look) is unchanged.

Prices and bonuses are first guesses. The user will tune them in playtest, so
they all live in data, not code.

## Decisions Made

These were settled with the user (2026-10-18):

- **Round flow:** the end-of-round report is shown as now. Space (or its
  button) now goes to the shop, not the next round. In the shop, Space (or a
  NEXT ROUND button) starts the next round.
- **Shop input:** mouse to click tabs and buy; Space for the next round.
  Keyboard shortcuts in the shop may come later (not this slice).
- **Three tabs:** drink upgrades (ice and lime for water), new drinks (wine),
  and the menu (toggle which owned drinks appear next round).
- **Shop background:** a liquor shop, softly blurred like the bar background.
  The user's reference photos: tall wooden cabinets with glass fronts and
  backlit shelves packed with bottles, brass name plaques on top (WHISKY,
  COGNAC, ROM), a red wine wall, recessed ceiling spots, a wooden floor and a
  dark wooden display table.
- **Prices:** ice 10, lime 15, wine 80.
- **Garnish keys:** UP drops ice (it falls from above); LEFT adds lime (it
  sits on the glass's left rim). DOWN still pours and Space still serves.
- **When:** a garnish can be added any time during the glass, before, during
  or after the pour. It only counts if it is on the glass when it is served.
- **Ice takes up volume:** it raises the water level a bit. Pouring to the
  line and then adding ice overshoots, and can spill.
- **Lime** hangs on the left rim like a wedge on a real glass (the user's
  reference photo: a lime wedge slit onto the rim, peel outward). It doesn't
  change the level.
- **Bonus:** a percentage of the step's coins, so a precise pour still pays
  the most: ice +20 %, lime +30 %, both +50 % (the user agreed to this
  suggestion). Water pays 12 / 7 / 4 with ice, 13 / 8 / 4 with lime,
  15 / 9 / 5 with both (plain: 10 / 6 / 3). The streak multiplier applies on
  top; a MISS still pays 0 and a spill still costs `spill_coins`.
- **Purchases** are permanent for the session (nothing is saved yet).
- **Wine no longer unlocks by itself.** Every round is water only until the
  player buys something else.
- **A newly bought drink** starts switched on in the menu, and the next round
  opens with it under the "NEW DRINK: WINE" banner, as round 2 does today.
- **The menu** always keeps at least one drink switched on.

## The Round Flow

`Main`'s phases become INTRO → PLAYING → LAST_CALL → SUMMARY → **SHOP** →
INTRO (next round).

- The summary's button becomes **TO THE SHOP (SPACE)**. Space or the button
  opens the shop (the summary hides).
- The shop's **NEXT ROUND (SPACE)** button or Space increments
  `GameState.round_number` and starts the round.
- Both screens ignore Space and their button for the first `input_lock`
  (0.5 s) after they appear, so a quick double tap can't skip the shop or the
  report.
- The shop covers the whole screen. The bar, the HUD and the vessels don't
  show and don't tick while it is open (the round has ended; nothing is in
  the air).
- Esc still quits.

## Garnishes

### Data

A new resource type, `GarnishDef` (`garnish_def.gd`), one `.tres` per garnish
in `res://garnishes/` (`ice.tres`, `lime.tres`):

- `id` (`&"ice"`, `&"lime"`), `display_name`, `description` (the card text,
  e.g. "Water pays +20%"), `price` (10, 15).
- `bonus`: the share added to each step's coins (0.2, 0.3). Bonuses of all
  garnishes on the glass add up (ice + lime = +50 %).
- `kind`: `ICE` (falls into the glass and displaces liquid) or `RIM` (sits on
  the rim). The shape/size tunables for each kind (cube size and count, wedge
  size) can live here or in the drawing code; the builder decides.
- The key that adds it (UP for ice, LEFT for lime).

`DrinkDef` gains `garnishes: Array[GarnishDef]` (water: ice and lime; wine:
none) and `price` (water 0, wine 80). Garnishes belong to a drink, so the
shop's upgrades tab and the game both read them from the drink.

### Scoring

`Scoring` gains the garnish bonus. The step's base coins are multiplied by
`1 + sum of bonuses` and **rounded to whole coins first**, so the table above
holds exactly; then the existing `paid_coins` applies the streak multiplier
and `coin_mult` (and rounds again). A spill's cost and a MISS are unchanged.
Round half away from zero (Godot's `roundi`): water GOOD ENOUGH with both is
3 × 1.5 = 4.5 → 5. The score result records which garnishes were on the
glass (for the checks and the debug readout).

### Using them in a round

- UP / LEFT (physical keys, like DOWN) add the drink's garnish with that key
  when all of these hold: the phase is PLAYING or LAST_CALL, the glass has
  landed (not arriving), the player owns the garnish, the current drink has
  it, and it isn't already on this glass. Otherwise the key does nothing,
  silently. (Not during INTRO: INTRO ignores input, and the timer doesn't run
  then, so a garnish there would be free. Builder's call made in this design,
  not the user's.)
- Pressing it again does nothing. One press of UP = one handful of ice; one
  press of LEFT = one wedge.
- **Serving waits for garnishes in flight:** a queued serve fires only once
  falling ice and the dropping wedge have landed, as it already waits for
  liquid in the air. The LAST_CALL idle auto-serve counts a garnish in flight
  as activity (it resets the idle timer).
- A garnish counts if it is on the glass when the serve fires. It vanishes
  with the glass in the puff. A new glass always arrives bare.
- **Key hint:** when the current glass is water and the player owns any of
  its garnishes, the hint adds them, in the same style as now:
  `HOLD DOWN  pour  ·  UP  ice  ·  LEFT  lime  ·  SPACE  serve  ·  F1  debug`
  (only the owned ones). Words rather than arrows: Fredoka has no arrow glyphs
  (checked: U+2190–2193 are missing). The hint pill already sizes itself to
  its text.
- **Popup:** unchanged; it shows the bigger number.

### Ice: how it raises the level

Ice is gameplay truth, like liquid volume: how much it raises the level is a
deterministic function of the glass's liquid volume and whether ice is in it.
The cubes' bobbing and tumbling are visual only.

- **Tuning target:** on the water glass, with the surface at the fill line,
  ice raises the settled surface by **5 rows** (allowed 4–6). So a glass
  poured to the line and then iced lands in GOOD ENOUGH, and a glass poured
  above the line and then iced can spill. The water glass has about 6 rows
  between the line and the rim.
- **Model** (the builder may refine it, but it must stay deterministic and
  monotonic): the cubes have a fixed total area. Floating, they displace a
  fixed share of it (real ice floats about 90 % submerged). In shallow water
  they rest on the floor and displace only their submerged part, so an iced
  glass with no water shows no water level, and a little water around cubes
  on the floor rises faster than in an empty glass. The level is the one
  where liquid + displaced area fills the interior below it.
- `level_for`, `rows_from_line`, the drawn liquid surface and the shader's
  `surface_y` all use the iced level, so what is drawn still sits exactly
  where scoring says (a calm iced glass's drawn top equals the scored level).
- **Overflow:** when liquid + displacement would exceed the capacity (adding
  ice to a nearly full glass, or pouring into an iced glass), the excess is
  spilled exactly as an overflow is today (`spilled` grows, drips run down).
  It scores SPILL.
- The target and the fill line don't move.

### Ice: look and animation

- **Drop:** three cubes appear just above the top of the view, over the glass,
  and fall in with a slight tumble. They reach the glass about 0.3–0.4 s after
  the press (a fixed time, so serving and the checks stay deterministic). The
  displacement applies when they land.
- **Splash:** with water in the glass, the landing kicks the surface waves and
  throws a few droplets (`Effects`). Into an empty glass, they land on the
  floor with a small bounce.
- **Cubes:** rounded squares, clear and frosty, with a bright edge highlight
  and a faint inner sheen, sized to the tuning target (about 8 world px each
  on the water glass). Once afloat they sit near the surface, mostly
  submerged with a sliver above, spread across the glass, bobbing with the
  wave height at their columns and drifting a little. In shallow water they
  rest on the floor and lift off as the water rises.
- **See-through:** suggestion for the builder: draw the cubes in the glass's
  `Back` layer (after the frost), so the liquid shader refracts and tints
  their submerged part, and add their edge highlight in `Front`. Godot copies
  the screen texture at the first item that reads it, so only what is drawn
  before the liquid gets refracted.
- They lean with the glass's layers like everything else drawn by the glass.
- Bubbles and drips keep working with ice in the glass.

### Lime: look and animation

- **Drop:** a lime wedge drops a short way onto the glass's left rim and
  settles with a small bounce (about 0.25 s).
- **Look:** like the reference photo (a close-up of a lime wedge on the rim
  of a glass of iced water: the wedge stands up and out to the left of the
  rim, slit onto the glass wall, its curved peel on the outside): the green
  peel outward, pale yellow-green flesh with segment lines and a juicy
  highlight, sitting **high on the rim** (most of it above the rim, a little
  hanging outside the left wall). Drawn by the glass's `Front` layer.
- **The fill line must never be hidden:** the bracket, the band ticks and the
  target marker all sit to the left of the glass, near the rim on water.
  They must draw over the wedge (draw the wedge before them in `Front`).
- No effect on the level.

## The Shop

### Layout

A new full-screen `CanvasLayer` scene (`shop.gd` / `shop.tscn`, `class_name
Shop`), built in code and laid out by hand in 640×360 HUD units like `Hud`
and `RoundSummary`: Fredoka, soft dark pills (`Hud.pill_style()`), gold for
actions.

- **Background:** the liquor shop image, covering the whole screen (see
  Background).
- **Coins:** the coin pill top left, as in the HUD (coin icon + total),
  updated as you buy.
- **Tabs:** a row of pill tabs near the top: **UPGRADES**, **DRINKS**,
  **MENU**. The active one is bright, the others dim. The shop opens on the
  tab last used this session (UPGRADES the first time).
- **Content:** below the tabs, the current tab's cards on a translucent dark
  panel so they read over the busy background.
- **NEXT ROUND (SPACE):** a gold button, bottom right (or bottom centre;
  builder's call).
- Buttons take no keyboard focus (`FOCUS_NONE`, as on the summary), so Space
  never "presses" a focused button and arrows do nothing.

### Cards

Each item is a card: a drawn picture, the name, one line of what it does, and
then either a price + **BUY** button or an **OWNED** badge.

- **Can afford:** BUY is gold and clickable.
- **Can't afford:** the card is greyed out and BUY is disabled; the price
  still shows.
- **Owned:** OWNED, no button.
- **Buying:** coins are spent at once, the coin pill updates, and the card
  turns to OWNED with a small pop. Items can't be bought twice.

Pictures are drawn in code in the same smooth style as the game (rounded
shapes, gradients, highlights), with the same drawing helpers the game uses,
so the ice and lime on the cards look like the ones in the glass:

- **Ice:** a few cubes.
- **Lime:** the wedge.
- **Wine:** the actual wine bottle (and optionally its glass) from the
  `DrinkDef` shapes. It should read as the bottle you pour. The builder decides
  how to share the pourer's drawing code with a card.

### The tabs

- **UPGRADES:** a section per owned drink that has garnishes, headed by the
  drink's name, with a card per garnish. Now: **WATER**: Ice (10, "Water pays
  +20%"), Lime (15, "Water pays +30%"). The card text also says which key
  adds it (e.g. "Press UP to add").
- **DRINKS:** a card per drink in the catalog that isn't free. Now: **Wine**
  (80; "Pays 15 / 9 / 5"). Once bought, OWNED.
- **MENU:** a card per owned drink with an ON/OFF toggle; click the card or
  the toggle to switch it. ON drinks can come up next round. The last ON
  drink can't be switched off: its toggle is disabled, with a note "At least
  one drink". The card shows the drink's glass (with liquid at its line) as
  its picture.

### Background

`tools/background/shop.html` draws the liquor shop on a canvas, the same way
`bar.html` draws the bar; `tools/make_background.sh` renders it to
`art/shop_background.png` (the script grows a second target; keep the bar's
output unchanged). It covers the full 640×360 HUD rect, so the image is
sized for that (sharp at 4K, mipmapped; the builder picks the resolution).

- From the photos: tall dark-wood cabinets with glass fronts and backlit
  shelves of bottles in many colours (amber, green, clear, red), brass name
  plaques on top (the text needn't be readable once blurred), a red-lacquered
  wine wall on one side, recessed ceiling spotlights, a warm wooden floor, a
  dark wooden display table in front.
- The photos themselves aren't in the repo (stock photos, one watermarked),
  so this description is the reference. Photo 1: a corner of a shop lined
  floor to ceiling with tall wooden cabinets, each with a glass front and a
  brass plaque on top, every shelf packed edge to edge with bottles lit from
  above, plus a low wooden stand of craft-beer bottles in front. Photo 2:
  dark-wood shelving on the left, a long red-lacquered wall of wine bottles
  at the back, a dark polished wooden table in the middle with a few gift
  boxes and bottles on it, and a warm wooden floor.
- Softly blurred like the bar (far layers more), and darker behind the
  content panel so the cards read.
- **Review:** no separate mockup round (the user declined browser mockups
  during design). The plan builds the background early and shows it to the
  user as an in-game screenshot; the art is then adjusted in playtest.
  (Builder's call made in this design.)
- Warm and inviting, a little brighter than the evening bar (a shop is lit
  for browsing), but nothing as bright as the cards' highlights.

## State

`GameState`:

- **Removes** `ROUND_UNLOCKS` and `unlock_for_round()`.
- `owned_drinks` stays (starts `[water]`).
- `owned_garnishes`: the garnish ids bought (starts empty).
- `menu`: the drinks switched on for the next round (starts `[water]`). A
  bought drink is added to it.
- `new_drinks`: drinks bought since the last round started. `start_round`
  forces the round's first glass to the first of them that is on the menu
  (with the "NEW DRINK: <NAME>" banner, as today's unlock does), then clears
  the list. A drink bought and then switched off gets no banner and isn't
  forced.
- Purchase helpers (`can_buy`, `buy_drink`, `buy_garnish`, `set_on_menu`, or
  whatever the builder names them) enforce the rules: enough coins, not
  already owned, the menu never empty. Spending can't take coins below 0.
- `reset_session()` resets all of it.
- The catalog (which drinks exist to buy) is the drinks in `res://drinks/`,
  or a constant list; builder's call. Water is free and owned at the start.

`Main._pick_drink()` draws uniformly from `GameState.menu` (was
`owned_drinks`) with `GameState.rng`, so a fixed seed still repeats a run.
Garnish visuals must not use `GameState.rng` (that would change the drink
sequence); they use `randf` like the other visual effects.

## Dev Tools

- `--autoplay` passes through the shop: after a short wait it buys what it can
  afford in a fixed order (ice, lime, wine), then starts the next round. On
  water glasses it adds the garnishes it owns (ice right after the glass
  lands, so it can allow for the displacement; lime any time), so autoplay
  screenshots show both. Its `release_at` for an iced water glass is tuned so
  it still lands within ~2 rows.
- **New flag** `--coins=N`: start the session with N coins, so the shop can
  be playtested without grinding rounds. (Builder's call made in this design.)
- **New flag** `--shop`: open the shop straight away at startup (after round
  1's summary state), for screenshots and quick checks of the shop. (Builder's
  call made in this design.)
- `--sweep` for plain water and wine stays byte-identical.

## Edge Cases

- **Ice into a nearly full glass:** overflows at once; drips, SPILL.
- **Ice added, no water, time runs out:** the glass isn't "active" (under 1 %
  liquid), so the round ends as today. Serving an iced empty glass is
  ignored, as an empty glass is today.
- **Serve pressed while ice falls:** queued; fires once the ice has landed
  (and liquid has landed and the pourer is upright).
- **UP or LEFT on a wine glass, before buying, during INTRO, while the glass
  arrives, or a second time:** nothing.
- **UP / LEFT while the pourer refills or arrives:** allowed (it's the glass,
  not the pourer).
- **DOWN held through a garnish:** fine; they're independent.
- **Wine bought, then switched off before leaving the shop:** the next round
  is water only, no banner.
- **All drinks switched on:** uniform picks across them, as today.
- **Not enough coins for anything:** every card greyed; NEXT ROUND still
  works.
- **Spills taking coins to 0 before the shop:** unchanged rule; the shop just
  shows 0.

## Testing

Checks (`--check=all`, one OK line per check). New and changed:

- `check_scoring`: the garnish table: water 12 / 7 / 4 with ice, 13 / 8 / 4
  with lime, 15 / 9 / 5 with both; a garnished PERFECT at x1.5 streak pays
  roundi(15 × 1.5); a garnished spill still costs 6, a garnished MISS pays 0.
- `check_glass`: ice raises the settled level at the line by 4–6 rows on the
  water glass; an iced glass with no water has no liquid level; the iced
  level is monotonic in volume; a calm iced glass's drawn top equals
  `level_for`; ice added to a glass within 4 rows of the rim overflows into
  `spilled`; the ice and lime outlines triangulate
  (`Geometry2D.triangulate_polygon`); after `arrive()` the glass is bare.
- `check_round` (fixed seed): round 2 is water only when nothing was bought;
  summary → Space → shop → Space → next round INTRO; Space is locked for 0.5 s
  on both screens; buying wine makes the next round open with wine under the
  banner; switching wine off on the menu keeps rounds water only; the menu
  picks are deterministic for a seed; UP/LEFT do nothing on wine, unowned,
  during INTRO or while the glass arrives; a serve queued while ice falls
  waits for it; a garnished water glass pays the garnished amount end to end.
- `check_shop` (new): buying with enough coins deducts the price and marks it
  owned; buying without enough coins or twice does nothing; a bought drink
  joins the menu and `new_drinks`; the last ON drink can't be switched off;
  `reset_session()` clears purchases and the menu; card states (can afford /
  can't / owned) follow the coins.
- `check_ui`: the summary button reads TO THE SHOP (SPACE); the hint names UP
  ice / LEFT lime only when owned and the glass is water; the banner after
  buying wine contains "NEW DRINK: WINE".
- `check_drinks`: drop the `ROUND_UNLOCKS` checks; wine's price is 80; water's
  garnishes are ice and lime; every garnish has a price and a bonus.
- Every check that fetches wine through `GameState.ROUND_UNLOCKS[2]`
  (`check_bubbles`, `check_glass`, `check_view`, `check_pourer`,
  `check_round`) loads it another way.

By hand:

- A windowed `--autoplay --coins=…` run with `--shots`: the shop's three tabs,
  ice falling and floating, the lime on the rim with the bracket over it, a
  wine round after buying it. Grep the output for `SHADER ERROR`.
- `--sweep` and `--sweep=wine` byte-identical to before.
- Playtest (prices, bonuses and the ice's rows are expected to change).

After implementation, update `CLAUDE.md` to describe slice 3.

## Left to the Builder

- Code structure: where garnish state lives (the glass is the natural owner
  of what's in it), the shop's internal structure, names of the
  `GameState` helpers.
- Exact card, tab and panel sizes and positions (readable at 1280×720; nothing
  under ~9 HUD units of font size).
- The ice displacement model's details, within the tuning target and the
  rules above; cube size, count placement and bobbing.
- How the wine bottle is drawn on its card.
- The shop background's composition and resolution, within the description.
- Small juice (a pop on buy, hover states on cards and tabs).

## Later (Not This Slice)

- Keyboard shortcuts in the shop.
- Upgrades that change `GameState.stats` (pour speed, refill time, longer
  rounds, coin multiplier).
- Garnishes or upgrades for wine, so it pulls ahead of fully garnished water.
- Saving and loading.
- Showing garnish stats on the round summary.

## Out of Scope

Sound, gamepad input, more drinks, selling items back, a run limit on drink
picks.
