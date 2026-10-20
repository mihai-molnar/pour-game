# Pour Game — More Upgrades: Sparkling Water, Premium and Vintage Wine, Faster Refills

Date: 2026-10-20
Status: Approved in conversation (2026-10-20); the user then asked for the
spec, plan and implementation in one go ("come to me only in case of
blockers"), so the calls below marked *(my call)* were not reviewed by them.

## Overview

The shop's UPGRADES page gets its first real upgrades — the ones that aren't
garnishes. They take the places of the blacked-out lines water and wine have
today (2 for water, 3 for wine); beer keeps its 2 blacked-out lines.

| Drink | Upgrade | Price | Effect |
|-------|---------|-------|--------|
| Water | Sparkling | 25 | every water glass is sparkling: pays +40 % |
| Water | Refill speed | 30 | the pitcher refills 50 % faster |
| Wine | Premium quality | 50 | wine pays +40 % |
| Wine | Vintage | 70 | wine pays +60 %, replacing premium's +40 % (premium must be owned first) |
| Wine | Refill speed | 50 | a new bottle is brought and uncorked 50 % faster |

Why: the deferred-work list in `CLAUDE.md` notes that fully garnished water
(15 / 9 / 5) pays the same as plain wine, and that wine needs upgrades so it
pulls ahead. Sparkling also lifts water, so the progression keeps climbing:
fully garnished sparkling water 19 / 11 / 6, vintage wine 24 / 14 / 8, beer
25 / 15 / 8.

Prices and bonuses are first guesses, to be tuned in playtest; they live in
data (`.tres`), not code.

## Decisions made with the user

- **Sparkling shows**: the water visibly fizzes — gas bubbles.
- **Premium and vintage show**: the wine bottle gets a nicer label (each a
  step nicer).
- **Vintage replaces premium**: buy premium first; vintage's +60 % then takes
  the place of premium's +40 % (wine tops out at +60 %, not +100 %).
- **Wine's refill speed stays** even though a drink change always brings a
  full bottle (so a wine refill only happens after three wine glasses in a
  row): the user may run a wine-only menu, and then it pays off.
- Wine's refill speed costs **50** coins (the user wrote "cost 50%"; read as
  50 coins and played back without objection).

## How the upgrades work

### Pay bonuses (sparkling, premium, vintage)

- An upgrade's bonus is a share of each scoring step's coins, added to the
  garnish bonuses on the glass the same way garnishes add to each other: the
  sum of all bonuses, `× (1 + Σ bonus)`, rounded to whole coins, before the
  streak multiplier and `coin_mult`. A MISS still pays 0 and a spill still
  costs `spill_coins`, unchanged. *(Adding up with garnishes was my guess in
  the playback; the user didn't object.)*
- It is always on: once bought, every glass of that drink gets it, with no key
  to press *(my guess in the playback; not objected to)*.
- Vintage, once bought, is the only one of the two counted (premium's +40 %
  is replaced, not added).
- Resulting pay (PERFECT / GOOD / GOOD ENOUGH):
  - water: plain 10 / 6 / 3; sparkling 14 / 8 / 4; sparkling + ice
    16 / 10 / 5; sparkling + lime 17 / 10 / 5; sparkling + ice + lime
    19 / 11 / 6.
  - wine: plain 15 / 9 / 5; premium 21 / 13 / 7; vintage 24 / 14 / 8.

### Refill speed (water and wine)

- "+50 % speed" means the refill takes `1 / 1.5` of its time: the base
  `GameState.stats.refill_time` (1.0 s) becomes 0.67 s for that drink only.
  *(My reading; played back without objection.)*
- Pitcher (water): fills in place over 0.67 s instead of 1 s. The swing back
  upright before the fill is physics and stays as it is.
- Bottle (wine): the empty one vanishes, a new corked one slides in (0.3 s)
  and its cork pops at `max(refill_time − 0.3, 0.1)` after landing — 0.37 s
  instead of 0.7 s.
- `stats.refill_time` stays the global base (the seam for a future
  all-drinks refill upgrade); the per-drink speed-up multiplies on top:
  `refill_time(d) = stats.refill_time / (1 + Σ refill_speed of d's upgrades)`.
- The DOWN key's refill ring follows the shorter time.
- Beer has no refill (a bottle per glass), so no beer refill upgrade.

### Buying rules

- Each upgrade is bought once per session (nothing is saved yet).
- A drink's upgrades are on sale only once the drink is owned *(my call)*.
  Before that its section on the UPGRADES page shows that many lines blacked
  out, as wine's section does today — buying premium for a wine you don't
  serve would be a wasted purchase.
- Vintage can only be bought once premium is owned. Until then its line
  prints faded (like an unaffordable line) and its price can't be clicked;
  its description says it needs premium *(my guess in the playback was a
  note "after Premium"; the exact wording is my call, sized to fit the line)*.
- Buying vintage after premium leaves premium's line stamped OWNED too.

## What the player sees

### Sparkling water

*(The user: "we can see it is sparkling, meaning gas bubbles". The specifics
below are my calls.)*

- In the glass: a steady fizz of small bubbles rising from 3–5 points on the
  floor (like beer's fizz, which already exists: `DrinkDef.fizz` +
  `Glass._fizz_x`), finer and quicker than beer's, white-cyan, popping at the
  surface. A few tiny bubbles cling to the inside of the walls below the
  surface. Where a bubble reaches the surface, a tiny short-lived glint shows
  just above it.
- Pouring into a sparkling glass stirs up more bubbles than still water does
  (as beer's impacts already do).
- In the pitcher: bubbles rise through the water in it too (toward world-up,
  whatever the pitcher's tilt), and pop at its surface.
- Anti-goal: the fizz must not make the surface harder to read against the
  fill line — the surface line stays the clearest thing at the top of the
  water; bubbles stay small and faint.
- Beer's look is unchanged (its bottle doesn't start fizzing).

### Premium and vintage labels

*(The user: "a nicer label". Specifics are my calls, playback said "premium a
cleaner gold-trimmed one; vintage adds a year and a crest".)*

- Plain (today): cream label, two wine-red rules, an ink grape emblem, two
  lines of "print"; a dark red foil capsule.
- **Premium**: the same cream label, now framed by a thin gold double border,
  with the grape emblem in gold, and a gold band at the foot of the foil
  capsule.
- **Vintage**: a dark label (deep burgundy-black) with a gold frame, a gold
  crest (a small shield under a crown or wreath) and a year in gold under it;
  the foil capsule turns gold. It should read as clearly richer than premium at
  the game's zoom while the bottle is tipped over the glass.
- The label shows on every wine bottle once bought, including the ones that
  arrive at a refill and the counter reflection's flat copy (the reflection may
  stay simpler).
- No gameplay change (the bottle's shape, volume and pour feel stay).

### The shop

UPGRADES page, after this slice (nothing else on the page changes):

```
::WATER::                         ::WINE::            (only once wine is owned;
  ICE           Water pays +20% · UP to add    10       before that: 3 blacked-out rows)
  LIME          Water pays +30% · LEFT to add  15       PREMIUM QUALITY  Wine pays +40%   50
  SPARKLING     Water pays +40%                25       VINTAGE          Wine pays +60% … 70
  REFILL SPEED  Pitcher refills 50% faster     30       REFILL SPEED     Bottles open 50% faster  50
                                                      ::BEER::  (2 blacked-out rows, after round 3)
```

- Each line has a small ink drawing like the others *(my call)*: sparkling — a
  water glass with bubbles; refill speed — the drink's pourer with a curved
  "again" arrow; premium / vintage — the wine bottle with that label (gold
  label / dark label with gold).
- Every description must fit on its line (one line of Courier at 9 units;
  the line's text area is 158 units wide).
- The MENU page's "Pays a / b / c" for each owned drink includes the always-on
  upgrades it owns (e.g. "Pays 24 / 14 / 8" for vintage wine); garnishes,
  which depend on the glass, are not included *(my call)*. The DRINKS page
  keeps showing base pay.

## Data and code shape *(my calls)*

- New `UpgradeDef` resource (`upgrade_def.gd`) + `upgrades/*.tres`:
  `id`, `display_name`, `description`, `price`, `bonus` (pay share),
  `refill_speed` (0.5 = 50 % faster), `replaces: UpgradeDef` (must be owned
  first; this one's bonus takes its place), `fizz` (bubbles/s it gives the
  drink's glass), `label_look` (`PLAIN` / `PREMIUM` / `VINTAGE`).
- `DrinkDef.upgrades: Array[UpgradeDef]` in the Shop group; water lists
  sparkling and water_refill, wine premium, vintage and wine_refill.
- `GameState`: `owned_upgrades` (ids), `owns_upgrade`, `buy_upgrade` (false
  when owned, the drink isn't owned, the replaced one isn't owned, or too
  dear), `active_upgrades(d)` (owned, minus any replaced by another owned one),
  `refill_time(d)`, `fizz(d)` (`d.fizz` + upgrades), `label_look(d)`;
  `reset_session` clears them.
- `Scoring.score(..., garnishes, upgrades)` / `garnished_coins(base,
  garnishes, upgrades)`: the bonus is the sum over both. Main passes
  `GameState.active_upgrades(drink)`.
- Pourer reads `GameState.refill_time(def)` wherever it read
  `stats.refill_time`; Glass uses `GameState.fizz(def)` wherever it used
  `def.fizz`.
- Shop: `UPGRADE_TEASERS` becomes beer's 2 only; a `CardState` for "needs
  another upgrade first"; `MenuLine.show_price` can print a faded line for it.
- Autopilot: buys the new upgrades too, after what it buys today (ice, lime,
  wine, beer, then sparkling, premium, vintage, water refill, wine refill).

## Constraints

- Gameplay stays deterministic; bubbles, glints and wall bubbles are visual
  only (unseeded `randf`, like the existing bubbles).
- `--sweep`, `--sweep=wine` and `--sweep=beer` stay byte-identical (they run
  with nothing bought).
- Colours from `Palette` (add named ones if needed); shapes that are drawn as
  polygons must triangulate (checks call `Geometry2D.triangulate_polygon`).
- Shop text ≥ 9 HUD units (an existing check).

## Non-goals

- No change to garnishes, keys, beer, round length, scoring rows or the
  streak; no global upgrades (`stats`) yet; no saving.
- No garnishes for wine.
- No new teaser lines for water or wine.

## Verification

- Checks: shop (lines, prices, the buying rules, vintage needs premium,
  descriptions fit), scoring (the pay table above), pourer (per-drink refill
  times, bottle uncork time), glass/bubbles (sparkling fizz stays inside the
  glass; still water has none), vessel art (new label and crest shapes
  triangulate), round (autopilot shopping).
- Screenshots: a sparkling water glass and pitcher, premium and vintage
  bottles tipped over a glass, the UPGRADES page before and after buying.
- `CLAUDE.md` updated.
