# Pour Game — Keyboard Keys Instead of the Hint Pill

Date: 2026-10-18
Status: Approved (2026-10-18: "go"); implemented 2026-10-18, awaiting playtest — plan `docs/superpowers/plans/2026-10-18-key-art.md`

## Overview

The controls are currently spelled out in a pill in the bottom-right corner
("HOLD DOWN pour · UP ice · LEFT lime · SPACE serve · F1 debug", or
"SERVING..." / "REFILLING..."). The user wants them shown as **keyboard key
artwork placed where the action happens** instead:

- the glass and the pourer move up on screen so there is room at the bottom;
- a **DOWN arrow key under the pourer**, which turns into a **refilling
  loading state** while the pourer refills;
- a **SPACE key under the glass**, shown only when the drink can be served;
- for a drink with garnishes the player owns (water: ice, lime), the
  **garnish keys at the matching side of the glass**: UP above it, LEFT on
  its left, each with a drawing of its garnish, each disappearing once that
  garnish is on the glass.

This is a presentation change. Gameplay, input rules, timing, scoring and
the shop don't change (the `--sweep` tables must stay byte-identical).

## Decisions Made

Settled with the user (2026-10-18):

- **Room at the bottom:** the glass and pourer sit higher on screen; the keys
  live in the space this opens below them.
- **DOWN under the pourer.** While the pourer refills, the key turns into a
  loading state.
- **SPACE under the glass.** It does **not glow**: it **appears** when the
  drink can be served and is **absent otherwise** — in particular there is
  no SPACE key while the glass is empty.
- **Garnish keys:** UP **above** the glass, LEFT on the glass's **left**
  side. Each carries a **drawing of its garnish** (ice cube, lime wedge).
  Each **disappears once its garnish has been added**; they come back for
  the next (bare) glass. Drinks without owned garnishes (wine, or water
  before buying) show none.
- **No words near the keys** — no POUR / SERVE / ICE / LIME labels.
- **The bottom-right hint pill goes.**
- **Framing (option 2 of three offered):** zoom out a little (vessels about
  6 % smaller) and **move the timer pill to the top-right corner**, so the
  tipped pourers stay clear of every HUD pill; the wine bottle's base may
  graze the top edge of the screen at its steepest pour. (Rejected: zooming
  out ~11 % with the HUD unchanged; zooming out a little and letting steep
  pours pass behind the timer.)

Played back to the user as guesses and accepted ("looks right, write it up"):

- The view moves rather than the vessels: the camera is reframed (not the
  world coordinates), and the bar background gets a taller counter front for
  the keys to sit on.
- The DOWN key presses down while DOWN is held. Its loading state is a ring
  that fills over the refill, then the arrow comes back.
- The DOWN key dims briefly while a new pourer slides in or a bottle is
  still corked (DOWN does nothing then).
- SPACE pops in when it appears and shrinks away when it goes; it presses
  down when hit. If the player pours more after it appeared, it hides again
  until that pour has landed.
- Garnish keys appear only once the glass has landed; a pressed garnish key
  presses down and vanishes as the garnish goes in.
- All the keys hide in the shop and during the round intro. The shop's own
  "NEXT ROUND · SPACE" stays as it is.
- F1 still toggles the debug readout; it just isn't advertised any more.
- The keys are chunky rounded keycaps in the family of the HUD's soft dark
  pills: a lighter top face over a darker, thicker bottom edge, a white
  glyph.

## The Keys

All keys are HUD elements (drawn in the `Hud` layer, laid out in 640×360 HUD
units like the rest of the HUD, positioned from world points through
`Main.world_to_hud`). They are purely visual: they read game state, they
never change it, and pressing the real keys works exactly as before whether
or not a key is on screen.

### When each key is on screen

Only during PLAYING and LAST_CALL (never during INTRO or in the shop, and
not during the short SHOP_DELAY after the last glass vanished, when there is
no glass). Within that:

| Key | Shown when |
|---|---|
| DOWN | always (dimmed while the pourer is arriving or corked but not refilling; the loading ring while `pourer.refilling`) |
| SPACE | a press would serve **right now**: not swapping (`!is_swapping()`), pourer not busy, glass volume ≥ `ACTIVE_SHARE` of capacity, `!pourer.is_pouring()`, `stream.is_empty()`, `!glass.garnish_busy()`, no serve already queued, the round not already ending (`_shop_in < 0`) |
| garnish (one per garnish) | the current drink has the garnish, the player owns it, it isn't on the glass yet, and `try_garnish` would accept it now (glass visible and landed, serving phase, round not ending) |

These rules should live in one place in `Main` (e.g. a `can_serve_now()`
and a "which garnish keys" query) that both the HUD and the checks read, so
the key on screen can never disagree with what a press would do. Note that
SPACE is still *accepted* while pouring (it queues a serve, as now) — the
key just isn't shown then. That is intended: the key advertises "serve now".

Visibility must be a deterministic function of game state computed when the
HUD refreshes (so the checks, which drive `tick()` themselves, can assert
it); only the pop-in / shrink-out / press animations are tweens.

### Where each key sits

- **DOWN:** on the counter front, centred under the current pourer's body as
  it rests at home (`pourer` home position + its resting outline's centre
  x — the wine bottle is held in the air, its key still goes on the counter
  front below it). On a drink change it glides to the new pourer's x over
  the arrival time.
- **SPACE:** on the counter front, centred under the glass (`GLASS_POS.x`),
  in the same row as DOWN. It is a wide key — about as wide as the glass —
  so it reads as a space bar.
- **UP (ice):** above the glass, centred on the glass. It must stay clear of
  the pourer and the stream at rest and at the common pouring tilts
  (`check_view`'s `COMMON_TILT`) for both drinks, and clear of the HUD pills.
  The falling ice passes through this spot, but the key is gone by then.
- **LEFT (lime):** left of the glass, roughly level with its upper third,
  clear of the fill-line bracket and target marker (`glass.bracket_x()`)
  with a visible gap.
- Garnish key positions come from the garnish's `key`, not its id, so a
  future garnish on another key gets a sensible spot: a small table from
  key to placement (UP above, LEFT left; DOWN and SPACE are taken, RIGHT is
  where the pourer is and would need its own decision — not needed now).

### What each key looks like

- **Keycap:** a rounded rectangle with a soft drop shadow on the counter
  front, a darker base showing as a thicker bottom edge, and a lighter top
  face. Arrow keys are square; SPACE is wide. Colours from `Palette` (dark,
  in the HUD pills' family, reading clearly against the dark counter front;
  gradients and alpha variants are fine).
- **Pressed:** the top face moves down onto the base (the thick bottom edge
  shrinks) for as long as the key is held (DOWN) or briefly on the press
  (SPACE, garnish keys). DOWN's pressed state follows the `hold` that
  `tick()` uses, so `--autoplay` screenshots show it too.
- **DOWN:** a white downward arrow drawn as a polygon (Fredoka has no arrow
  glyphs).
- **DOWN, refilling:** the arrow is replaced by a circular ring that fills
  clockwise from empty to full over the refill. It is a track plus a filled
  arc; it reaches full exactly as `refilling` turns false, then the arrow
  returns. Progress covers the whole refill as the pourer experiences it:
  for the pitcher (`IN_PLACE`) the swing back upright then the fill; for the
  bottle (`NEW_BOTTLE`) the swing, the vanish, the new bottle's arrival and
  its uncork. The pourer needs a public `refill_progress()` (0..1) for this;
  how it's derived (e.g. a fixed 0 while still swinging, then time over the
  known remaining duration) is the builder's call as long as it is
  monotonic and ends at 1 when the refill ends.
- **SPACE:** blank except for the "open box" space symbol (␣ — a horizontal
  line with short upturned ends), drawn as a polyline. *Builder's/my call:*
  the user said no words, and a wide key with ␣ reads as a space bar without
  any text.
- **Garnish keys:** the garnish's drawing fills the middle of the cap (the
  in-game ice cube / lime wedge style from `GarnishArt`, which reads on a
  dark cap — not the menu's ink drawings, which are meant for paper), with a
  small arrow in a corner showing the direction. *Builder's/my call:* the
  user asked for the drawings on the keys; the corner arrow keeps the
  direction readable for players who don't connect "above the glass" with
  UP.
- **Animations** (HUD tweens, visual only): appear = pop in (scale from ~0.6
  with a slight overshoot, ~0.15 s, fading in); disappear = shrink out
  (~0.1 s); press = ~0.08 s down, and for SPACE / garnish keys the
  disappearance follows straight on. Exact timings are the builder's call.

## Framing

The counter top (world y = 280, the lip's lower edge at 286.5) is now at the
very bottom of the view (view bottom ≈ 289). For the keys, the view must
show a strip of counter front below the lip, roughly **35–45 HUD units**
tall (a ~24-unit keycap plus margins).

The constraint that makes this a trade-off: the tipped pourers already
reach close to the top of the view. Measured from the drink shapes:

- the water pitcher at 70° past rest (its second glass) reaches world
  y ≈ 100 at x ≈ 316 — right under the timer pill; today it clears the
  pill's bottom edge by a fraction of a HUD unit;
- the wine bottle at 55° past rest reaches world y ≈ 89 at x ≈ 401 — today
  the view top is 83.

So any shift down of the view alone pushes the steep pours behind the timer
pill or off the top of the screen.

**Decided (user, option 2):**

- **Zoom out a little — to about 1.65** (from 1.75; the vessels look ~6 %
  smaller) — and move the view down so the key row fits below the counter
  lip. The exact centre and zoom are the builder's call within this: as
  little zoom-out as gives ~35–40 HUD units of key room while the rules
  below hold.
- **The timer pill moves to the top-right corner** (mirroring the coin pill:
  10 HUD units from the right edge, same top and height as now —
  `Hud.TIMER_PILL` ≈ `Rect2(570, 8, 60, 22)`). Its behaviour (red in the
  last 5 s) is unchanged. The coin pill and the banners stay where they
  are.
- With the timer out of the middle, the pourers stay clear of **every** HUD
  pill at rest and at the common tilts (`check_view` keeps this rule, with
  the new timer rect in its pill list).
- **The top edge:** the wine bottle's base may graze the top edge of the
  screen at its steepest common pour (55° past rest, base at world y ≈ 89).
  `check_view`'s "fits the view" rule is relaxed for the top edge only — a
  pourer may reach up to the top of the view (no inner margin there, and at
  most ~2 world px past it); the other three edges keep the `MARGIN`.
  Everything else (both glasses, the water pitcher) must fit with the margin
  as today.

Also:

- `Main.CAMERA_CENTER` / `CAMERA_ZOOM` and the `Camera` node in `main.tscn`
  change together (`check_view` asserts they match).
- `check_view` keeps its checks (arriving vessels start off-screen, vessels
  fit the view at rest and at common tilts, the background covers the view)
  with its numbers updated to the new framing, and gains: the key row fits
  between the counter lip and the bottom of the screen.
- The counter reflection strip (`Reflection`, x 100–500) is widened if the
  wider view shows past its ends.
- The background (`tools/background/bar.html` + `BACKGROUND_RECT` +
  `tools/make_background.sh`'s size comment) is extended to cover the new
  view, wider too if the zoom-out makes the view wider than 380 world px.
  The new area below the lip is the bar's **front face**: dark wood, calm
  and low-contrast (a soft shadow under the lip, faint grain or panel seams
  at most, darkening toward the bottom), so the keys read on it. Nothing
  bright; keep the vignette.
- `Glass.OFFSCREEN_X` / `Pourer.OFFSCREEN_X` may need to move further out if
  the view widens, so arrivals still start off-screen.
- HUD things placed from world points (result popups) follow automatically
  through `world_to_hud`; the coin pill, the streak flyer and the banners
  stay where they are in HUD units; the timer pill moves as above.

## What Goes

- The hint pill: `Hud.set_hint`, `hint_label`, `_hint_pill`, `HINT_SIZE`;
  `Main.hint_text()`, `HINT_SEP`, and the SERVING... / REFILLING... strings.
- The `check_round` expectations on `hint_text()` are replaced by
  expectations on the new key visibility (below).

## Verification

- A new check (e.g. `check_keys`) drives `tick()` and asserts the visibility
  table above: no SPACE on an empty glass; SPACE appears after a pour has
  landed and hides while pouring again; SPACE hidden while a garnish falls,
  while a glass or pourer arrives, while the pourer refills, after a serve
  is queued; garnish keys only for owned garnishes of the current drink,
  only once the glass has landed, gone once added, back on the next glass;
  none on wine; DOWN dimmed while arriving/corked, ring while refilling with
  progress rising to 1 as the refill ends (both refill styles); no keys
  during INTRO or in the shop.
- Geometry (in the same check or `check_view`): every key inside the screen;
  DOWN and SPACE below the counter lip and not overlapping each other; UP
  and LEFT clear of the glass, the bracket, the HUD pills, and the pourers
  at rest and common tilts; generated polygons (arrow, ring, ␣, garnish
  drawings) pass `Geometry2D.triangulate_polygon`.
- All existing checks pass; `--sweep` and `--sweep=wine` output unchanged.
- A windowed `--autoplay --shots` run (with `--coins` so ice, lime and wine
  get bought) to look at the keys at 1280×720: DOWN pressed while pouring,
  the refill ring, SPACE appearing after a pour lands, UP/LEFT vanishing as
  the autopilot adds garnishes, no garnish keys on wine. Check the log for
  `SHADER ERROR` / triangulation errors.
- `CLAUDE.md` updated (current state, the camera numbers, the timer's new
  place, the HUD keys, the removed hint, the new check).

## Left to the Builder

- Exact keycap sizes, colours, corner radii, shadow and animation timings
  within the look above.
- How the key layer is structured (one `Control` drawing all keys, or a
  small `Keycap` class per key) and how `Main` hands it state.
- The exact camera centre and zoom within the decided framing (about 1.65,
  timer top right), and the details of the counter front's painting.
- The precise spots for UP and LEFT within the clearance rules.
