# Pour Game — Slice 2: Second Drink and Mixed Rounds Design

Date: 2026-10-15
Status: Draft — awaiting review

## Overview

Adds wine as a second drink and mixes it into rounds: from round 2 each glass
is a random drink you own, so the player has to re-read every glass — its
shape, line height and pour feel change how long to hold and when to let go,
and a habit learned on water doesn't carry over. Glasses and pourers now
arrive with a fast, juicy slide-in instead of today's slide-out/slide-in swap,
and each pourer type has its own refill: the pitcher refills in place, an
empty wine bottle is replaced by a new one that gets uncorked.

Builds on slice 1 (`2026-10-15-round-loop-design.md`); everything not
mentioned here (30 s rounds, streak, scoring bands, last call, summary) is
unchanged.

## Decisions Made

- **Second drink:** wine — a bottle (no handle, narrow neck) poured into a
  stemmed glass whose bowl narrows toward the rim. Line at the bowl's widest
  point (low), pays 1.5× water.
- **Introduction:** round 1 is all water. Round 2 unlocks wine with a
  "NEW DRINK: WINE" banner; from then on each glass is 50/50 water or wine.
  Stands in for the slice 3 shop unlock.
- **Glass change** (every serve, same drink or not): the old glass disappears
  and the new one slides in from the left — fast, so little round time is
  lost, but with juice.
- **Drink change:** the pourer is replaced the same way, sliding in from the
  right; a pourer that swaps in arrives **full** (pourers don't remember their
  level across a swap).
- **Refill:** stays timed by `stats.refill_time` (a planned shop upgrade makes
  it faster), but the animation is per pourer: the pitcher refills in place as
  today; you don't refill a wine bottle — an empty one is replaced by a new
  corked bottle that gets uncorked.
- **Structure:** the glass and the pourer each animate their own arrival
  (`arrive()`), sharing a pure `Arrival` helper; `Main` only decides what
  arrives and when.

## Wine

`drinks/wine.tres`, new palette entries `Palette.WINE` (`#a22633`) for the
liquid and `Palette.WINE_LIGHT` (`#e43b44`) for the highlight.

- **Glass:** a big Bordeaux-style glass: a foot 28 px wide, a stem 4 px wide
  and 18 px tall, and a U-shaped bowl 48 px wide inside at its widest
  (y −52 to −62), narrowing to 36 px at the rim; 96 px tall overall (the
  water tumbler is 74). The foot and stem are part of `glass_outer` only;
  `glass_interior` is the bowl (3 100 px²). Sized so PERFECT spans ±1 pixel
  row (tuning target 1): a smaller glass with a lower line would make PERFECT
  about ±0.4 rows (checked while planning, 2026-10-15).
- **Fill line:** at the top of the bowl's widest section, the way wine is
  actually poured: `fill_fraction` 0.53 (target 1 643 px², line at y ≈ −62,
  about halfway up the bowl).
- **Bottle:** no handle (`pourer_handle` empty). Body 40 px wide inside and
  110 px long, a shoulder, a neck 6 px wide inside and 24 px long; the spout
  lip (the node origin) is the top-left of the neck's mouth. About 150 px
  long overall, holding about 2.7 glasses. Walls tinted dark green
  (`Palette.BOTTLE`, `#265c42`) through the new `DrinkDef.pourer_glass_color`;
  the pitcher keeps today's frost walls. Flow may be slower than the pitcher
  (narrow neck) — set by tuning.
- **Held, not standing:** a bottle standing upright beside the glass can't
  get its spout over the opening (the neck is in the middle of the bottle),
  so it is held tipped at 55° above and to the right of the glass, its mouth
  ≈ 20 px above the rim and over the opening. New
  `DrinkDef.pourer_rest_deg` (0 for the pitcher, 55 for the bottle): the
  shapes stay authored upright, the pourer is drawn and simulated rotated by
  it, and tilt, `max_tilt_deg` and "swings back upright" all count from it.
- **Payout:** `perfect_coins` 15, `good_coins_max` 12, `good_coins_min` 3
  (water: 10 / 8 / 2).
- **Why it's harder:** the low line makes the liquid still in the air at
  release a much larger share of the target, so the player must let go much
  earlier; the neck also delays the start of the pour.

**Tuning targets** (shapes and pour values adjusted until `--sweep=wine`
meets them):

1. PERFECT spans at least ±1 pixel row on the wine glass. Tolerances are
   relative to the target, so a small bowl would make PERFECT thinner than a
   row and unhittable; the bowl is sized to prevent that (also enforced by
   `check_drinks`, see Testing).
2. The hold nearest the line differs from water's (3.0 s) by at least 0.7 s.
3. A full bottle holds 2.5–3.5 glasses at the line (2.67 with the shapes
   above).
4. Pouring doesn't spill: in the sweep, nothing misses the glass for holds
   that end at or below the GOOD band.

## Mixed Rounds

- **Owned drinks:** `GameState.owned_drinks` starts as `[water]`.
  `GameState.ROUND_UNLOCKS = {2: wine}`: when a round in that table starts and
  its drink isn't owned yet, it is added to `owned_drinks` and the INTRO
  banner shows two lines, "ROUND N" / "NEW DRINK: <display_name in capitals>"
  ("ROUND 2" / "NEW DRINK: WINE"). The slice 3 shop replaces this table.
- **Picking:** each new glass draws uniformly from `owned_drinks`. Exception:
  the first glass after an unlock is the newly unlocked drink, so round 2
  opens with wine under the banner that names it. No run limit (four waters
  in a row can happen) — revisit after playtesting.
- **When:** the first glass of a round is picked as the round starts; every
  later glass is picked at the serve, as the old glass disappears.
- **Pourer:** if the picked drink differs from the current one, the pourer is
  replaced (see Arrivals). At round start the pourer always arrives full, for
  whichever drink comes first.
- **Scoring:** unchanged rules; each glass pays from its own drink's table
  (`Scoring.score` already takes the `DrinkDef`). The streak carries across
  drink changes. The summary is unchanged (glasses of both drinks counted
  together).
- **Determinism:** picks use `GameState.rng` (`RandomNumberGenerator`), seeded
  randomly at startup; the `--seed=N` dev flag fixes the seed, and checks seed
  it explicitly. Same seed + same inputs = same round.
- **Session reset:** `GameState.reset_session()` restores coins, round number,
  `owned_drinks`, `stats` and the rng seed; `tools/run_check.gd` calls it
  before each check instead of resetting fields one by one.

## Arrivals

`arrival.gd` (`class_name Arrival`): pure static functions of the time since
an arrival started. No state, no tweens — glass and pourer step it from their
own `step()`, so arrivals advance inside `main.tick()` and stay deterministic.

- **Slide:** `Arrival.ARRIVE_TIME` = 0.3 s from off-screen to home, easing
  out, overshooting home by at most 3 px and settling back by the end.
- **Lean:** the object tips toward its direction of travel as it brakes (the
  top keeps going), then wobbles back upright in about two shrinking swings,
  peaking around 6°. The wobble may finish up to 0.15 s after the slide; the
  object is usable as soon as the slide ends. It tips over its lowest
  leading corner (`Arrival.pivot`), so nothing dips into the counter, and it
  rotates only the vessel's draw layers (`Liquid`, `Front`), never the node,
  so no gameplay code sees it.
- All values are named constants in `arrival.gd`, tunable in playtest.

**Glass:** `glass.arrive(drink)` runs `setup(drink)` (empty), places the glass
off-screen left (x = −40) and slides it to `Main.GLASS_POS`. `receive`,
`surface_y_world_at`, `opening_world` and `rim_y_world` use the node, which
never rotates. An empty glass doesn't slosh from its own motion (the arrival's
acceleration would otherwise leave waves for the first pour).
`glass.is_arriving()`.

**Pourer:** `pourer.arrive(drink)` runs `setup(drink)` (full, upright),
places it off-screen right (spout lip at x = 680) and slides it home
(`GLASS_POS + drink.pourer_offset`). DOWN is ignored while it arrives (as
while refilling); `rotation = −(rest + tilt)`, the lean is on its draw
layers. `pourer.is_arriving()`.

**Vanish:** the glass or pourer that's leaving disappears at once and leaves a
puff of 4–6 pixels. The puff is drawn by a new `Effects` node (`effects.gd`),
because the same glass node immediately jumps off-screen for its next
arrival. `Effects` also draws a little dust at the base when an arrival lands,
and the flying cork and spray (see Refill). It is visual only, so it may use
`randf`. Scene order: Background, Glass, Stream, Pourer, **Effects**, HUD.

**When:**

- **Serve:** the served glass vanishes and the next glass arrives. If the next
  drink differs, the pourer vanishes and the new one arrives at the same
  moment (and `stream.set_drink` switches the stream's colors — the stream is
  empty at a serve). A serve now costs ≈ 0.3 s instead of 0.85 s, so a round
  fits a few more glasses. Space is ignored while the glass is arriving (as
  during today's swap); `main.is_swapping()` = the glass or the pourer is
  arriving.
- **Round start (INTRO):** the round's first glass and its pourer arrive at
  the start of the 1.5 s INTRO.
- **Last call:** the final served glass vanishes and none arrives; the summary
  appears 0.35 s later so the popup and puff read.

This replaces `main.gd`'s slide-out/slide-in swap (`_step_swap`,
`SWAP_OUT_TIME`, `SWAP_IN_TIME`).

## Refill

New `DrinkDef.refill_style`: `IN_PLACE` (pitcher, water) or `NEW_BOTTLE`
(wine).

Unchanged for both: below 1 % of full volume the pourer enters REFILLING,
ignores DOWN and swings back upright; the "REFILLING..." hint shows and Space
is ignored. `stats.refill_time` is the total from upright to ready, so a
faster-refill upgrade shortens both.

- **`IN_PLACE`:** unchanged — fills in place over `refill_time`.
- **`NEW_BOTTLE`:**
  1. Once upright, the empty bottle vanishes with a puff.
  2. A new, corked bottle arrives from the right (`ARRIVE_TIME`).
  3. The cork works its way out: the bottle wiggles with growing intensity
     for `max(refill_time − ARRIVE_TIME, 0.1)` s (0.7 s at the default), then
     pops — the cork (a 4×3 px brown block) flies out along the neck and
     falls off-screen, with a few droplets of spray. REFILLING ends at the
     pop.
- **Drink change and round start:** a bottle also arrives corked but pops
  straight away (`POP_TIME` 0.15 s after landing, no wiggle), so switching
  drinks stays quick. Pouring is possible once the cork is out.
- While corked, the cork sticks ≈ 3 px out of the neck, drawn by the
  pourer's `Front` layer; the flying cork and spray are drawn by `Effects`.

## Data Model

`drink_def.gd` gains:

- `@export var pourer_glass_color := Color(Palette.FROST, 0.1)` — the
  pourer's glass: rgb tints it, alpha is the body's tint strength (walls 3×,
  capped at 1). The default reproduces today's pitcher exactly; wine uses
  `Palette.BOTTLE` at 0.35 (solid green walls).
- `@export_range(0, 90) var pourer_rest_deg := 0.0` — the angle the pourer is
  held at when not pouring (see Wine).
- `enum RefillStyle { IN_PLACE, NEW_BOTTLE }` and
  `@export var refill_style := RefillStyle.IN_PLACE`.

`game_state.gd` gains `ROUND_UNLOCKS`, `rng` and `reset_session()`.
`owned_drinks` still starts as `[water]`.

## Components

New:

- `drinks/wine.tres` — the wine drink.
- `arrival.gd` (`Arrival`) — slide and lean curves.
- `effects.gd` (`Effects`) — puffs, landing dust, flying cork, spray.
- `tools/checks/check_arrival.gd` — the arrival curves.

Changed:

- `palette.gd`: `WINE`, `WINE_LIGHT`, `BOTTLE`.
- `drink_def.gd`, `game_state.gd`: as in Data Model.
- `glass.gd`: `arrive()`, `is_arriving()`, the lean; the fill-line fix (see
  Fixes).
- `pourer.gd`: `arrive()`, `is_arriving()`, the corked state and cork
  drawing, the `NEW_BOTTLE` refill sequence, the lean, `pourer_glass_color`.
- `main.gd`: picks drinks and triggers arrivals on serve and at round start
  (replacing the swap code); the last-call summary delay; the unlock banner;
  `--seed=N`; `--sweep=<id>` loads `res://drinks/<id>.tres`.
- `autopilot.gd`: a release share per drink id (wine needs an earlier
  release; value from the sweep).
- `tools/run_check.gd`: calls `GameState.reset_session()`.
- `main.tscn`: the `Effects` node.

## Fixes Included

From the known deferred work in `CLAUDE.md`:

- `--sweep=<id>` simulates the chosen drink (it always used
  `owned_drinks[0]`).
- `glass.gd` `_draw_fill_line`: the left tick and the band bracket assumed the
  walls slope outward going up. The bracket now sits 4 px left of the
  leftmost outer wall across the whole band, so it and the tick clear the
  bowl on glasses that narrow toward the rim.
- The LAST_CALL idle auto-serve now also waits while the pourer is refilling
  or arriving (it bypassed `request_serve`'s refill guard; with the bottle's
  vanish and slide-in it would fire mid-refill).

## Edge Cases

- **Time runs out while a glass is arriving:** the glass is empty, so the
  round ends straight away (same rule as during a swap today).
- **Wine glass overflows:** drips follow the outer outline, so they run down
  the bowl and the stem.
- **Serving while the pourer is arriving:** can't happen — a pourer only
  arrives together with a glass (or during a refill), and Space is ignored
  during both.
- **DOWN held through a serve:** pouring can continue into the arriving glass
  when the pourer stays; the lean doesn't affect where liquid lands.
- **DOWN held while a pourer arrives or uncorks:** ignored until it's ready;
  tilting starts then if DOWN is still held.

## Testing

Checks (`--check=all`, one OK line per check):

- `check_drinks`: every drink in `res://drinks/` has valid shapes (interior
  inside outer) and ordered payouts (`perfect_coins ≥ good_coins_max ≥
  good_coins_min`); on every drink's glass, PERFECT spans at least ±1 pixel
  row at the base `perfect_tol`; `owned_drinks` starts as `[water]`;
  `ROUND_UNLOCKS` unlocks wine at round 2.
- `check_glass`: the wine glass's capacity equals its interior pixel count and
  `level_for` is monotonic; the fill-line ticks have positive width on both
  glasses; `setup` water → wine → water leaves no state behind (same
  capacity, target, empty); an arriving glass is at home after
  `ARRIVE_TIME`; liquid received while the glass leans counts the same.
- `check_pourer`: an arriving pourer is full and ignores DOWN until it lands;
  a `NEW_BOTTLE` refill is ready at `refill_time` (±1 tick) after reaching
  upright, and sooner with `refill_time` 0.5; a bottle arriving on a drink
  change pops within `ARRIVE_TIME + POP_TIME`; the `IN_PLACE` refill is
  unchanged.
- `check_round` (fixed seed): round 1 serves only water; round 2's first
  glass is wine and later glasses include both; the same seed gives the same
  drink sequence; a drink change brings a full pourer and the same drink
  keeps the pourer's level; Space is ignored while a glass arrives; the
  last-call idle auto-serve waits during a refill.
- `check_ui`: round 2's banner contains "NEW DRINK: WINE".
- `check_arrival`: the slide starts off-screen and ends at home; the overshoot
  stays within 3 px; the lean returns to 0.

By hand:

- `--sweep=wine` meets the wine tuning targets; `--sweep` (water) is
  unchanged.
- `--autoplay` screenshots show arrivals, vanishing puffs and an uncork.
- Playtest.

After implementation, update `CLAUDE.md` to describe slice 2.

## Later (Not This Slice)

- **Choosing drinks in the shop (slice 3):** let the player pick the round's
  drink mix before leaving the shop, so that after several upgrades round 20
  isn't still serving cheap water.
- **Run limit on picks:** only if 50/50 feels streaky in playtest.

## Out of Scope

The shop and upgrades UI, drink selection, more drinks, beer foam, sound,
saving/loading, gamepad input.
