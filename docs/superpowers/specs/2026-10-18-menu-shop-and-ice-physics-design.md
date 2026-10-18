# Pour Game — The Shop as a Drinks Menu, and Ice Physics

Date: 2026-10-18
Status: Approved (2026-10-18: "plan and build it")

## Overview

Changes after the user's first playtest of slice 3 (the shop, garnishes and
the drink menu, `2026-10-18-upgrade-shop-design.md`):

1. **No report screen.** Having the end-of-round report and then the shop
   "makes no sense" (user): the round now ends straight into the shop.
2. **The shop becomes a printed drinks menu**, full screen, with coloured
   index tabs on its right edge; clicking a tab turns the page. Drinks and
   upgrades that will unlock later are already listed, blacked out with
   marker.
3. **Bigger ice cubes with physics**, so they don't "look glued on the bottom
   of the glass": they bounce, tumble and knock against the glass and each
   other, float and bob in water, and get pushed by the stream.

What can be bought, the prices, the bonuses, and the rules for buying and
switching drinks don't change ("no logic change, just the way things look
needs to be improved" — user). Scoring doesn't change either.

## Decisions Made

Settled with the user (2026-10-18):

- **Round end:** straight into the shop; the report screen goes.
- **Menu look:** like the user's "BEVERAGES" reference: a printed menu on
  off-white paper in dark ink — a big bold condensed title, a small ornament,
  section headers in the `::SPARKLING WINE::` style, each item a line with a
  bold name on the left, the price on the right and a short description
  under it in lighter, typewriter-like type, thin rules between parts.
- **Full screen, no background picture.** The liquor-shop background goes.
- **Tabs:** coloured index tabs sticking out of the page's right edge,
  stacked top to bottom, like the divider tabs in the user's reference photo
  (rounded tabs on the side of a stack of divider pages, labels written
  along them), with the folder-tab shape of the other reference (a raised
  tab with sloped, rounded shoulders).
- **Flipping:** clicking a tab turns the page.
- **Future content shown censored:** wine "and then a bunch more" drinks
  listed but blacked out with marker until unlocked; the same for upgrades.
  Nothing new can be unlocked yet — these are placeholders.
- **Ice:** two bigger cubes instead of three (same total ice, so the water
  still rises about 5 rows at the line and scoring is unchanged), with
  physics that is purely visual.

Suggested by the builder and accepted by the user ("sounds good", "all
good"):

- The round's result moves onto the menu, one line under the title.
- The price is the button; a bought item reads OWNED; unaffordable lines
  are printed faded; the MENU page's lines end in ON / OFF.
- Small drawings beside the lines (ice, lime, the wine bottle, the glasses),
  like the illustrations on the user's chalkboard-menu reference.
- The coin total in the page's top corner, like a running bar tab.
- NEXT ROUND · SPACE as a line at the bottom of the page.
- Plain dark behind the page.
- Two new free fonts: a bold condensed one for titles and names, a
  typewriter one for descriptions and prices. Fredoka stays for the HUD.
- The physics is a small hand-made simulation of the cubes inside the
  glass, stepped with the rest of the game, not Godot's physics engine.

## The References

The user's reference images aren't committed (stock images, one marked
"designed by freepik"); this is what they show:

- **"BEVERAGES" (the chosen look):** a portrait printed menu on off-white
  paper, dark grey ink. A huge bold condensed sans title across the top, a
  tiny ornament under it, then two columns separated by a thin vertical
  rule. Section headers like `::SPARKLING WINE::`, `::COCKTAILS::` in bold
  caps. Lines: a bold sans name on the left, prices right-aligned
  (`$25 / $6`), and under cocktails a one- or two-line description in a
  typewriter-like serif. Generous margins, no pictures.
- **A white printed "DRINKS MENU":** boxed section headers (a thin rectangle
  round `SOFTDRINKS & WATER`), name + price lines with a grey description
  underneath; a dark photo band down the left side.
- **A chalkboard "DRINK MENU":** white hand lettering on a dark board,
  dotted leaders from names to prices, and colourful hand-drawn drinks
  (outlined, flat-coloured glasses with straws, fruit slices) beside the
  groups — the model for the item drawings.
- **Folder tabs:** manila folders whose tabs are raised trapezoids with
  rounded, sloped shoulders, each in a strong colour (red, purple, blue,
  green), staggered.
- **Divider tabs:** a stack of coloured divider pages with rounded tabs down
  the right edge, staggered top to bottom, each labelled along its length
  (`Files`, `Forms`, `Receipts`…) — the model for the tabs' placement.

## Round End

- `Main`'s phases become INTRO → PLAYING → LAST_CALL → SHOP. SUMMARY and
  the report go: `round_summary.gd` / `round_summary.tscn` and their node
  are deleted.
- Where the summary used to appear, the shop opens instead: right away when
  time runs out on an untouched glass (or one still arriving); after the
  last-call glass vanishes, with the same 0.35 s delay (`SUMMARY_DELAY`, to
  be renamed) so its popup reads first.
- The shop's existing 0.5 s Space lock now also covers a Space pressed to
  serve that last glass.
- `--shop` still opens the shop at startup (no round line: nothing has been
  played). Autoplay waits `AUTOPLAY_SHOP_WAIT` in the shop as before.

## The Menu

### The page

Everything is laid out by hand in the 640×360 HUD space, as today.

- **Behind it:** plain dark (`Palette.INK`), nothing else.
- **The page:** one landscape page as tall as the screen allows (a few
  units of dark around it), shifted left so the tabs fit on its right
  within the screen. Off-white paper (new `Palette` entries, e.g. `PAPER`
  ≈ `#f3eee3` and a warm dark-grey ink `MENU_INK` ≈ `#2e2a2b`), a very faint
  grain or vignette, a thin double frame inset from the edge like the
  reference, soft shadow under the page.
- **Header:** the page's title big and bold in the condensed font, letter-
  spaced, centred — the tab's name: UPGRADES, DRINKS, MENU. A small drawn
  ornament (a flourish of thin lines) under it.
- **Round line:** under the ornament, small typewriter type, centred:
  `ROUND 2 · 6 GLASSES · 4 PERFECT · BEST x1.6 · +134` (round number,
  glasses served, perfects, best multiplier, coins this round signed — the
  numbers the report showed). Hidden when no round has been played.
- **Coins:** top right of the page, like a running bar tab: the coin icon
  and the total in the condensed font.
- **Body:** two columns, as in the reference, with sections. A section
  header is `::NAME::` in the condensed font with a thin rule under it.
- **NEXT ROUND · SPACE:** a line centred at the bottom of the page in the
  condensed font, clickable (darker and underlined on hover). It replaces
  the gold NEXT ROUND button.

### Item lines

- **Anatomy:** a small drawing at the left (about 18–22 units tall), the
  name in bold condensed capitals, the price right-aligned on the same
  line, and one description line under the name in typewriter type, lighter
  ink.
- **Drawings, printed-menu style** (builder's call, made in this design): the
  game's glassy art is made for dark backgrounds (white edges, frost fills at
  low alpha, clear glass walls) and would nearly vanish on paper. So the
  lines get small ink illustrations instead, drawn from the same shapes
  (the `GarnishArt` cube and wedge geometry, the `DrinkDef` glass and bottle
  outlines, rounded with `VesselArt.rounded`): a dark-ink outline of even
  weight with flat, slightly translucent watercolour-like fills — ice pale
  blue with a white glint, the lime green peel and pale flesh with segment
  lines, the water glass outlined with a blue fill to its line, the wine
  glass outlined with a red fill, the wine bottle dark green with its cream
  label. Like the coloured hand-drawn drinks on the user's chalkboard
  reference, but on paper. A "menu ink" drawing helper (new, e.g.
  `menu_art.gd`) holds them; `VesselPreview` and the old card pictures go
  unused by the shop.
- **Price as the button:** the typewriter price with a small coin icon.
  Hovering an affordable price makes it clearly clickable (e.g. darker ink
  and a hand-drawn pen underline or circle, plus a small BUY); clicking buys.
- **Owned:** the price is replaced by OWNED, like a rubber stamp (slightly
  tilted, coloured ink), and the line stays fully printed.
- **Can't afford:** the whole line printed faded; the price can't be
  clicked.
- **Menu page:** each owned drink's line ends in a drawn checkbox with ON or
  OFF; clicking the line or the box switches it. The last drink on can't
  be switched off: its box is disabled and a small note under the line says
  `At least one drink`.
- **Buying feedback:** a small stamp-like pop as OWNED appears; the coin
  total updates at once.

### What each page lists

Copy, prices and rules as today (`Water pays +20%`, `UP to add`,
`Pays 15 / 9 / 5`, …):

- **UPGRADES:** `::WATER::` with Ice (10) and Lime (15), then a couple of
  blacked-out lines (future water upgrades); `::WINE::` with a few
  blacked-out lines (wine has no upgrades yet), shown whether or not wine is
  owned; optionally one more section whose header is blacked out too.
- **DRINKS:** Wine (80), then a bunch (about five or six) of blacked-out
  lines — drinks to come.
- **MENU:** a line per owned drink with its ON/OFF box (no blacked-out
  lines: this page is only what you own).

### Blacked-out lines

- The name and the description are hidden under thick black marker
  strokes: rough-edged, slightly slanted dark bars (`Palette.INK`, nearly
  opaque, a little texture) of varying length, as if someone redacted the
  line by hand. The price reads `??`. No drawing, or a dark silhouette
  blob.
- They are drawn placeholders, with fixed shapes (seeded per line so they
  don't change between visits). A count per section lives in the shop code;
  when real drinks and upgrades are added later, real lines replace them.
- They aren't clickable.

### Tabs

- Three index tabs on the page's right edge, top to bottom in page order:
  UPGRADES, DRINKS, MENU. Each is a rounded tab with sloped shoulders
  sticking out about 26–30 units, in its own colour (muted, paper-like:
  e.g. terracotta, sage, dusty blue — new `Palette` entries), its label
  running along it (rotated, reading top to bottom) in the condensed font.
- The current page's tab sits in front, joined to the page; the others sit
  slightly behind it, a little darker, as if their pages are underneath.
- Clicking a tab turns to its page (below). Hover lightens a tab.
- The shop still opens on the tab used last.

### Page turn

- Clicking a tab turns the page in about 0.35 s. Going to a later page, the
  current page turns over to the left, folding toward the spine (its left
  edge), and the new page is revealed underneath; going back, the earlier
  page turns back in from the left over the current one. One turn per
  click, however many pages apart.
- The turning page is shaded toward the fold, with a highlight on its
  curling edge, and casts a soft shadow on the page underneath.
- During a turn the tabs and lines don't react; a tab clicked mid-turn
  finishes the turn at once and starts the next.
- Suggested implementation: the turning page is the page itself, scaled
  horizontally about its left edge (text and drawings squish with it, the
  usual 2D page-turn trick), with a shading overlay. The builder may choose
  another way.

### Fonts

- Two OFL fonts from Google Fonts, in `fonts/` with their licence files:
  **Oswald** (variable weight; titles, section headers, names, tabs, NEXT
  ROUND, OWNED) and **Courier Prime** (Regular and Bold; descriptions,
  prices, the round line, notes).
- A cached-font helper like `Hud.font()` for them.

## Ice Physics

### Size

- `garnishes/ice.tres`: `cube_count` 2, `cube_size` 10.4 (two cubes of
  10.4 px hold 216 px², the same as three of 8.5). The rise at the water
  line stays 4–6 rows (check_glass already pins it) and the cubes side by
  side (20.8 px) still fit the tumbler's 30 px floor.
- The displacement rule (`surface_level`, `displaced`, `max_liquid`) is
  unchanged: it stays the deterministic gameplay truth.

### Behaviour (visual only)

- **Bodies:** each cube is a rounded square with position, velocity, angle
  and spin, simulated in the glass's local space inside its interior
  outline. Collisions: the cubes with the interior's walls and floor and
  with each other — a little bounce, friction so they slide and stop, and
  torque so they tip and settle on a face.
- **Falling in:** the fall from above the view stays as now (the landing
  time `ICE_FALL_TIME` still decides when the displacement applies and a
  serve may fire); when the cubes reach the glass the simulation takes
  over with their falling velocity and a small random spin, so they hit
  the floor (or the water), bounce, tumble, slide, knock against the walls
  and each other, and settle within about half a second. Where they end up
  varies a little each time.
- **In liquid:** buoyancy proportional to how much of a cube is under the
  surface, with water drag, so a floating cube rides with about
  `float_share` of it under and bobs on the waves (the surface height and
  slope under it); a cube plunging in goes under and pops back up. In
  shallow liquid the cubes rest on the floor and lift off as it rises.
- **The stream:** liquid landing near a cube pushes it sideways and down a
  little.
- **Drawing:** as now — the body in `Back` (refracted and tinted by the
  liquid), the edges in `Front` — at the simulated pose. Cubes never draw
  outside the glass's walls.
- **Randomness:** visual only (`randf`), never `GameState.rng`; gameplay
  stays deterministic and `--sweep` byte-identical.

## Components

New: `fonts/Oswald*.ttf`, `fonts/CourierPrime-*.ttf` (+ OFL licence
files); the menu page drawing (in `shop.gd` or split into helpers as the
builder sees fit); the ice simulation (in `glass.gd` or a small helper,
e.g. `ice_physics.gd`).

Changed: `main.gd` (no SUMMARY; round end opens the shop; round stats
handed to the shop), `main.tscn` (no RoundSummary node), `shop.gd` /
`shop_card.gd` (the menu replaces the cards; `ShopCard` may go or become a
menu line), `glass.gd` (cube poses from the simulation), `garnishes/ice.tres`,
`palette.gd` (paper, ink, tab colours), `autopilot.gd` (no summary step),
the checks, `CLAUDE.md`.

Removed: `round_summary.gd`, `round_summary.tscn`, `art/shop_background.png`
(+ `.import`), `tools/background/shop.html`, the `shop` target in
`tools/make_background.sh`.

## Edge Cases

- **Time runs out on an untouched or arriving glass:** the shop opens at
  once (as the summary did).
- **Space held / mashed through the round end:** the shop's 0.5 s lock.
- **A tab clicked during a page turn:** the turn finishes at once, the next
  one starts.
- **Buying the last affordable thing:** other lines turn faded at once.
- **Ice dropped into a glass already holding ice:** can't happen (one ice
  per glass).
- **Ice and a near-full glass:** overflow and SPILL as today; the floating
  cubes ride at the rim.
- **Window sizes:** the menu is laid out in 640×360 units like the HUD and
  scales with the window (4:3 letterboxes).

## Testing

Checks (`--check=all`, one OK line per check):

- `check_round`: time up goes straight to SHOP (no SUMMARY phase), on an
  untouched glass at once and after the last-call glass with the delay;
  Space in the shop starts the next round; the shop's lock holds right after
  the round ends; the round line shows the round's numbers.
- `check_shop`: purchases, menu rules, card/line states as today, now
  through the menu lines (states follow coins on reopen; a double click
  buys once; the last drink on can't be switched off); the pages list
  what's above (UPGRADES: ice, lime + blacked-out lines; DRINKS: wine +
  blacked-out lines; MENU: owned drinks only); blacked-out lines aren't
  clickable; a tab click turns the page (the page ends on the tab after the
  turn time; a click mid-turn finishes it and starts the next); no menu
  text under ~9 units.
- `check_ui`: the summary tests go; the round-line text format.
- `check_shop` also: every menu illustration's polygons triangulate.
- `check_glass` (ice): two cubes; the rise is still 4–6 rows; dropped into
  an empty glass many times (different random spins), the cubes always stay
  inside the interior and come to rest (speed near zero) within about a
  second; in liquid at the line they float with their tops near the surface;
  the stream pushes a nearby cube; drawn outlines triangulate.
- `check_drinks`: ice is 2 × 10.4 and fits the floor side by side.

By hand: windowed `--shots` of each page, a page turn mid-way, blacked-out
lines, hover on a price; ice dropping into an empty glass (a frame sequence)
and floating; grep for `SHADER ERROR`. `--sweep` and `--sweep=wine`
byte-identical.

After implementation, update `CLAUDE.md`.

## Left to the Builder

- Exact page, column, line and tab sizes and positions; colours within the
  description; the ornament and frame drawing; how hover looks.
- How the page turn is drawn.
- The physics' constants (gravity, bounce, friction, buoyancy, drag) and
  how the bodies collide with the interior outline.
- How many blacked-out lines each section shows.
- Whether `ShopCard` is reworked into a menu line or replaced.

## Later (Not This Slice)

- Real drinks and upgrades behind the blacked-out lines, and what unlocks
  them.
- Keyboard shortcuts in the shop.

## Out of Scope

Any change to prices, bonuses, buying or menu rules, scoring, or the round
timing; sound; saving.
