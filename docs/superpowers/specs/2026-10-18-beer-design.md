# Pour Game — Beer: Foam, a Tilted Glass and a Bottle per Glass

Date: 2026-10-18
Status: Approved in conversation (2026-10-18: "that's it. feel free to design
it, plan it, and implement it") — plan `docs/superpowers/plans/2026-10-18-beer.md`

## Overview

Adds beer, a third drink, sold in the shop for 150 once round 3 is over. It
is the hardest drink so far, and the most real-feeling. The skill is how
fast you pour. Beer makes foam: a fast pour builds a tall head that can run
over the rim, which is a spill. A slow pour makes little foam but costs time
on the clock. The glass is held tipped toward the bottle while you pour, the
way a barman does it, so you can't line the beer up with the line by eye
until you stop. Each glass gets its own bottle, holding a little more than
the glass needs. It pays more than wine.

Builds on slices 1–3, the scoring steps, the smooth art style, the menu shop
and the key art (see `CLAUDE.md`). Water and wine don't change at all.

## Why

The user wants a third drink that asks for a new skill rather than another
line height to learn. Beer brings three new things:

- controlling the pour speed by feathering DOWN (hold and release);
- foam, which hides beer inside it, can spill, and slowly settles so the
  beer creeps up after the pour;
- a tipped glass that hides where the beer stands against the line until you
  stop.

## How foam works in real life (the basis for the model)

The user asked how foam affects the beer level in real life. This is what
the design copies:

- The head is mostly gas: CO₂ bubbles in thin films of beer. Only about a
  fifth to a quarter of its volume is liquid, so the visible top sits well
  above the actual beer.
- How you pour decides how much foam you get. Pouring hard and fast churns
  the beer and makes a big head. A gentle pour down the side of a tilted
  glass makes very little.
- During the pour the foam piles up faster than the beer, so the white top
  climbs quickly. After the pour it collapses. The top drops, and the beer
  underneath rises a little as foam turns back into liquid.
- A glass's fill mark measures the beer, with the head sitting above it.
  Foam running over the rim is the classic mess.

## Decisions Made (with the user)

- **Scoring:** the *beer* (not the foam) is scored against the target line,
  with the same steps as the other drinks (PERFECT / GOOD / GOOD ENOUGH /
  MISS by rows). A perfect beer has the beer at the line and about **two
  fingers** of foam on top. MISS is beer outside the allowed rows, or a
  spill. Foam running over the rim **is a spill**. The amount of foam
  doesn't change the coins otherwise (no bonus for a nice head).
- **Foam behaviour** (proposed, accepted): how fast the beer lands decides
  how much foam forms. During the pour, foam piles up faster than the beer.
  After the pour, the foam slowly settles: the head shrinks and the beer
  underneath creeps up a little, which the player has to anticipate. The
  beer is scored **where it is at the moment of serving**: waiting lets it
  creep up but costs time.
- **The tilted glass:** while you pour, the glass tips toward the bottle,
  like a barman holding it so the beer runs down the side. When you stop
  pouring it eases back to vertical. Serving happens after the pour has
  stopped, so a beer is always upright when it is scored. While tipped, the
  beer's surface stays level in the world but the line tilts with the glass,
  so you can't line them up by eye.
- **Pour speed is the deciding factor.** You control it by holding and
  releasing DOWN. On release the beer bottle **eases out**: it tilts back
  toward rest much more slowly than water or wine, so tapping DOWN on and off
  holds a steady, slower pour.
- **One bottle per glass:** a beer bottle holds about **5 % more** than the
  glass needs (than the beer at the target line; the room above the line is
  for the foam). The leftover isn't refilled, it's replaced: every new beer
  glass comes with a new, full bottle, whatever was left in the old one.
- **Looks:** from the user's reference photos, drawn in the game's current
  smooth style. A tall wheat-beer glass (photo 3: heavy clear base, narrow
  waist, widening toward the top with a slight bulge). A brown longneck
  bottle (photo 1): dark amber glass that is still see-through, so you can
  see the beer level in it, a big label on the body and a gold crown cap that
  pops off and tumbles the way the wine cork does. If a longneck doesn't fit
  the view when tipped far, a shorter bottle like photo 2. Beer is amber-gold
  and a little cloudy, but the bar still shows through it. It shows lots of
  rising bubbles while pouring, fewer after. Foam is creamy off-white with a
  slightly lumpy top and small bubbles visible against the glass.
- **Shop:** beer costs **150**. It is **unlocked after round 3**: from the
  first shop it is listed on the DRINKS page but blacked out, and it goes on
  sale in the shop after round 3. Once bought, the next round opens with it
  under "NEW DRINK: BEER", as wine does today.
- **Coins:** beer pays **more than wine** (wine 15 / 9 / 5). Starting point
  20 / 12 / 6, a spill costs 12, tuned in playtest (see Tuning).
- **No garnishes for beer** yet.

## My calls (the user can override)

- The glass tips about the centre of its mouth: the mouth stays under the
  bottle, and the base swings away to the left and lifts off the counter, as
  if held in a hand. Tipping over the right foot corner would move the mouth
  about 50 px into the bottle.
- The tilt is about 35° when the pour starts and straightens to about 15° as
  the beer nears the line (a barman straightens the glass as it fills). It is
  never upright while pouring, so the line stays hard to read at the end.
- The glass starts tipping as soon as DOWN is pressed (a barman readies the
  glass before the beer flows). It stays tipped while beer is flowing or
  still in the air. It eases back upright once all of that has stopped for a
  short moment (about 0.25 s), so brief gaps while feathering don't make it
  twitch.
- If the bottle runs dry before the glass is done, the usual auto-refill
  brings a new full bottle (as wine does today). The empty bottle swings
  back with the ordinary quick return, not the slow ease-out, so a refill
  doesn't take 3 s longer than wine's.
- The bottle is held at the wine bottle's 55° rest angle, its spout over the
  glass's mouth.
- A "finger" of foam is 10 world px.
- The DRINKS page keeps its length: the locked beer is one blacked-out row
  under BY THE GLASS (after wine), and the separate teaser section shrinks
  from 5 rows to 4. Once beer unlocks, its row becomes a normal line.
- The UPGRADES page gets a BEER section with two blacked-out lines, like
  water's and wine's. It only appears once beer is unlocked, so the
  blacked-out DRINKS row isn't spoiled.
- The autopilot (used by `--autoplay` and the round check) buys beer last,
  after ice, lime and wine. It pours beer by feathering toward a medium flow.
- A new dev flag `--round=N` makes the session start as if N rounds had been
  played. With `--shop --coins=200 --round=3`, beer is on sale.
- No foam lacing on the glass walls, and no head bonus.

## Goals, non-goals, anti-goals

**Goals**

- A beer round feels different: you feather the pour and watch the head. You
  learn the creep after the pour and the tipped line.
- Holding DOWN flat out from start to finish is punished: the foam spills
  before the beer reaches the line.
- A medium, feathered pour reaches the line with about two fingers of foam
  and no spill.
- Beer is worth buying: it pays more per glass than wine, and a round of
  beer earns at least as much as a round of wine.

**Non-goals** (not this slice)

- Garnishes or upgrades for beer.
- A head bonus, or any score for the amount of foam other than spilling.
- Letting the player tilt the glass themselves.
- Saving, keyboard shortcuts in the shop, other drinks.

**Anti-goals** (a failure even if it technically works)

- Water or wine changing in any way: `--sweep` and `--sweep=wine` must stay
  byte-identical, and all existing checks pass.
- The beer/foam boundary being hard to see in an upright glass. The player
  must always be able to read where the beer stands once the glass is up.
- Scoring that depends on the tilt. A beer is always scored upright, by the
  same rows rule as the others.
- A normal pour that needs the bottle tipped so far it leaves the view. Only
  draining the very last drop may take its base past the top edge.
- Randomness in gameplay. Foam, tilt and the slow return are deterministic,
  stepped from `main.tick()` like everything else. Only visuals use `randf`.

## Beer

`drinks/beer.tres` (`id` beer, `display_name` "Beer"), added to
`GameState.DRINKS` after wine and as `GameState.BEER`.

### Glass

- A weizen-style glass, about 104 world px tall overall: a heavy, thick base
  (solid glass, about 12 px) with a ring or two like the photos. The
  interior's narrow waist is about 16 px wide just above the base. It widens
  smoothly to about 40 px near the top, the widest point a little under the
  rim, then narrows a touch (about 37 px) at the rim. Taller and slimmer
  than the wine glass, it still fits the view at rest and at its pour tilt.
- The line sits so that at least **two fingers plus a margin** (about 26 px)
  stand between it and the rim, for the foam (`fill_fraction` follows from
  the shape).
- The interior must stay "column-convex": each pixel column's inside is one
  run, which the glass's column spans already assume.
- The line, the band bracket and the marker are drawn as for the other
  glasses. They tilt with the glass because they are on it.

### Bottle

- A brown longneck: a body, a shoulder, a long narrow neck. The spout lip
  (the node origin) is the top-left of the neck's mouth, as on the wine
  bottle. Dark amber glass (new `Palette` colour): darker than the wine
  bottle's green, but the beer level shows through it.
- `full_volume` = 1.05 × the glass's target (±1 %), set through the shape and
  `pourer_full_fraction`. A full bottle doesn't pour at rest.
- Sizing worked through while designing (a guide, not a rule): an interior
  waist 16 px wide widening to 40–42 px gives about 2 800 px², and
  `fill_fraction` ≈ 0.61 leaves 26 px above the line (target ≈ 1 700 px²). A
  bottle with a 7 px neck 26 px long, a 14 px shoulder and a 26 px-wide body
  60 px long (about 100 × 30 px outside) holds 1.05 × that at
  `pourer_full_fraction` ≈ 0.9. With its spout about 12 px above the glass's
  rim it doesn't pour at rest, is empty by about 50° past rest, and stays well
  inside the view's top edge on the way.
- A big label on the body (photo 1: an oval or rounded label, cream with a
  red band and a small barley or hop emblem, in the game's style), a neck
  label in the same colours where the wine bottle has its foil, and a gold
  **crown cap** instead of the cork. The cap is crimped, a touch wider than
  the mouth and short. It pops off POP_TIME after landing, as the cork does,
  with a small foamy spray, and tumbles away (a new `Effects` kind). The
  label art, foil/neck-label art and cap art become per-drink styles instead
  of being wine-only.
- Refill: `NEW_BOTTLE`, as wine. In addition, every new beer glass brings a
  new bottle (see Arrivals).

### Pour feel

- Holding DOWN tips the bottle, as for every drink.
- **Release eases out**: the forward tipping eases to a stop, then the bottle
  drifts back toward rest slowly and eases into rest without a clunk. A full
  return from a steep pour takes about 3 s, against about 1 s for wine.
  Pressing DOWN mid-return carries on tipping from where it is. This is a new
  return behaviour chosen per drink in the `DrinkDef`. Water and wine keep
  today's constant-force return exactly.
- Values (`tilt_speed_deg`, `pour_tilt_speed_deg`, `max_flow`, the new return
  values …) are tuned against the targets in Tuning.

### Liquid look

- Amber-gold `liquid_color`, pale gold `liquid_highlight` (new `Palette`
  colours `BEER` and `BEER_LIGHT`). `liquid_absorb` sits between water's and
  wine's, so the bar shows through, dimmed and warm. `liquid_scatter` is
  higher than water's for a slightly cloudy look.
- **Fizz:** beer has bubbles all the time, not only where the stream lands.
  Streams of fine bubbles rise from a few points on the glass's floor and
  walls, many more while beer is landing, then thinning out. Tinted pale
  gold. The bubble cap is raised for beer. Visual only.
- The stream is drawn in the beer's colours like any other.

## Foam

Foam is gameplay: it decides spills, and it holds beer that later settles
into the glass.

- **State** on the glass: `volume` stays the liquid beer (what is scored).
  New `foam`: the foam's volume (px², as it takes up room in the glass), and
  `foam_beer`: the beer held in it.
- **Where it sits:** on top of the liquid. Its top is the surface that
  `volume + foam` would have. Liquid and foam surfaces are both level in the
  world, so they are tilted lines in the glass's frame while it is tipped.
- **Making foam:** the glass keeps a smoothed rate of how fast beer is landing
  (px²/s, averaged over about 0.2 s). That rate is "how fast you pour", so
  drops landing one by one count as slow. Of each bit of beer that lands, a
  share k turns into foam. That beer goes into `foam_beer`, and the foam
  grows by it divided by the wet share (fresh foam is wet: about a fifth
  beer). The rest joins the liquid. k grows with the landing rate: near 0
  for a trickle, high for a full-speed pour, capped. The curve's parameters
  live in the `DrinkDef`.
- **Settling** has two parts, as in a real glass:
  - **Draining** (fast, about 1–1.5 s): wet foam drains toward dry foam (a
    few percent beer). The beer that drains out joins the liquid. This is
    the creep: right after the pour the beer rises a few rows while the head
    barely changes.
  - **Collapsing** (slow, tens of seconds): the foam itself shrinks, and its
    beer joins the liquid. So the head is still there, about two fingers,
    when you serve.
- **Spilling:** when liquid + foam no longer fit below the rim (with the glass
  as it stands, tipped or not), the foam on top runs over first. Its beer
  content counts as spilled, then any liquid beyond that. A spill is scored
  SPILL as today (`glass.spilled > 0.5`), and foam drips run down the outside.
- **Conservation:** beer landed = `volume + foam_beer + spilled` at every
  tick (to rounding).
- **Fitting the bottle:** two fingers of drained foam must hold less beer than
  the bottle's 5 % extra, so a medium pour to the line leaves a little in the
  bottle. In this flat 2D glass, two fingers of foam are about half the
  target's area, so the dry share has to stay small (about 0.05). That is
  "mostly gas", as the user was told.
- Water and wine have no foam (the foam parameters default to off). Their
  glasses behave exactly as now.
- **Look:** creamy off-white (new `Palette.FOAM`), a little beer-tinted and
  wetter where it meets the beer, with a soft, slightly lumpy top (gentle
  bumps, steady per glass, not waving like the liquid), and small bubbles
  visible against the glass, bigger near the top. Drawn inside the walls
  (under the glass's front highlights). The liquid's surface sheen is hidden
  under the foam. The boundary between beer and foam stays clearly visible.

## The tilted glass

- New `DrinkDef` values: the tilt when a pour starts and the tilt as the beer
  reaches the line, both 0 for water and wine (no tilt at all). For beer,
  about 35° and 15°: the glass straightens as it fills, by the beer's share
  of the target. Positive means the top leans toward the bottle (right).
- **When:** the glass tips toward its pour tilt while DOWN is held (and the
  pourer could pour), or beer is flowing or in the air. Once none of that has
  been true for about 0.25 s, it eases back to exactly upright, in about
  0.5 s. Tipping in takes about 0.35 s. Deterministic, stepped in `tick()`.
  It never tips while arriving or vanishing, and never during INTRO or the
  shop.
- **Pivot:** the centre of its mouth (see My calls). The base swings left and
  lifts off the counter. The contact shadow shrinks and fades as it lifts,
  and the counter reflection follows the tipped glass.
- **It is gameplay, not just a picture:**
  - The liquid and foam surfaces are level in the world, so in the glass's
    frame they are tilted lines. Their height for a volume is found over the
    glass's pixel columns: the area under a sloped line is the sum over
    columns of the column's run below the line. At tilt 0 this is exactly
    today's `level_for`, so the upright glass is unchanged and nothing jumps
    when the tilt reaches 0.
  - What fits before spilling shrinks while tipped. The limit is the level
    line through the rim's lowest corner. A glass tipped further with a full
    head can spill.
  - The stream lands in the glass as drawn. A parcel enters when it crosses
    the tipped opening and stays inside the walls (running down the side).
    It lands on the foam's top if there is foam, otherwise on the liquid.
    Waves and bubbles live in the glass's frame.
  - The glass's helpers that the stream and Main use (opening, rim, surface
    at x, receive) account for the tilt. When the tilt is 0 they give exactly
    today's results.
- **Scoring is always upright.** A serve waits until the glass is upright
  (along with today's conditions: not pouring, nothing in the air, no
  garnish falling). `rows_from_line(volume)` is unchanged, and so is the last
  call's idle check, which also waits for the glass to be upright.
- The fill line, band and marker tilt with the glass; the HUD keys don't move.

## Arrivals and serving

- After a beer is served, the bottle vanishes with a puff along with the
  glass, and a new full, capped bottle arrives with the next glass, even if
  the next glass is beer too. It pops its cap POP_TIME after landing, as on a
  drink change. A new `DrinkDef` flag says "a new pourer with every glass"
  (beer only).
- Everything else is as today: the next glass slides in from the left, a
  drink change brings the other pourer from the right, LAST_CALL auto-serves
  after 3 s idle, and the round ends into the shop.

## Shop and unlocking

- `DrinkDef.unlock_round` (0 = always on sale; beer 3): the drink is on sale
  in a shop opened once that many rounds have been played
  (`GameState.round_number >= unlock_round` while in the shop; under
  `--shop` before any round the count is 0). `GameState.is_unlocked(d)`.
  `buy_drink` refuses a locked drink.
- **DRINKS page:** under BY THE GLASS, wine's line, then beer's: blacked out
  while locked (a redacted row like the teasers), a normal line
  ("Beer · Pays 20 / 12 / 6 · 150", the bottle drawing) once unlocked. The
  teaser section below shrinks from 5 rows to 4.
- **UPGRADES page:** a BEER section with 2 blacked-out lines, shown once beer
  is unlocked.
- **MENU page:** unchanged (beer appears once owned and can be switched off;
  at least one drink stays on).
- Buying it: the next round opens with beer under "NEW DRINK: BEER".
- `MenuArt.draw_bottle` / `draw_glass` draw beer's bottle and glass from its
  shapes (the label in the beer's colours, the cap instead of the foil).

## Tuning

Starting values are first guesses; these targets decide the final ones. A
`--sweep=beer` mode prints what is needed to check them: continuous holds
**and** feathered pours (hold/release in a fixed rhythm, and a flow-target
pour like the autopilot's). For each it reports beer level vs the line in
rows, foam height in fingers when the glass comes upright, time to reach the
line, spill, and how far the beer creeps over the next 2 s.

1. **Flat-out is punished:** holding DOWN without letting go from a full
   bottle spills foam before the beer reaches the GOOD ENOUGH band.
2. **A medium feathered pour works:** the autopilot-style pour, stopped a
   little under the line, ends at the line once the head has drained, with
   1.5–2.5 fingers of foam, no spill, and a little beer left in the bottle,
   pouring for roughly 3–6 s. (Worked through for a glass of about 1 700 px²
   target: wet foam at a fifth beer and dry at 0.05 hold about 165 and
   40 px² in two fingers. A pour of about 1.025 × target stops about 3 rows
   under the line, creeps up to it, and leaves about 2.5 % in the bottle. The
   bottle's 1.05 × target therefore fits, and the auto-refill stays a rare
   fallback.)
3. **A trickle is safe but slow:** the slowest steady pour leaves under one
   finger of foam but takes at least 1.5× as long as the medium pour.
4. **The creep matters:** after a medium pour, the beer rises 2–4 rows over
   the next 2 s as the head drains, while the head stays about two fingers
   tall for at least 10 s.
5. **Feathering works:** releasing DOWN for 0.3 s mid-pour lowers the flow
   without stopping it; releasing for about 1.2 s stops it.
6. **The bottle:** holds 1.05 × the target (±1 %); a medium pour to the line
   leaves a little in it. The bottle stays in view (the existing view rules,
   with the timer it may pass behind) at the tilts a medium pour reaches.
7. **Worth buying:** an autopilot round of only beer earns at least as much
   as one of only wine. If 20 / 12 / 6 falls short, the payout goes up (spill
   cost about 60 % of PERFECT, like wine).

## Testing

Checks (`tools/checks/`, run through `tools/run_check.gd`):

- `check_drinks`: beer's data. Price 150, unlock round 3, it pays more than
  wine at every step, no garnishes, the bottle holds 1.05 × target (±1 %),
  the room above the line is at least two fingers, the catalog is water,
  wine, beer, and water and wine have no foam and no tilt.
- `check_glass`: foam conservation (`volume + foam_beer + spilled` = beer
  landed); foam made grows with the landing rate; draining moves beer from
  the foam into the liquid quickly while the head barely shrinks; collapsing
  is slow; foam overflow is a spill. The tilted
  level at a tiny tilt matches the upright one (< 0.5 px), what fits shrinks
  while tipped, and an upright glass is unchanged.
- `check_stream`: a stream into a tipped glass lands inside it (nothing
  passes through a wall), and lands on the foam when there is foam.
- `check_pourer`: the beer bottle eases back slowly (still tipped after 1 s,
  at rest after about 4 s, no bounce); water and wine return as before.
- `check_round`: the serve waits for the glass to be upright; a beer serve
  brings a new bottle with the next beer; the autopilot plays a beer round
  with mostly GOOD-or-better glasses.
- `check_shop`: beer is blacked out before round 3 and on sale after it;
  buying a locked drink is refused; the BEER upgrades section appears once
  unlocked; the page keeps its row count.
- `check_view`: the beer glass fits the view upright and at its pour tilt;
  the bottle fits at the tilts a medium pour reaches.
- `check_vessel_art`: beer's glass, bottle, cap, label and foam polygons
  triangulate.
- Water and wine: `--sweep` and `--sweep=wine` byte-identical to before; all
  existing checks still pass.

Visual verification: windowed `--shots` runs (and the movie writer for
motion) of autoplayed beer rounds (`--autoplay --shop --coins=400 --round=3`),
looking at the tipped pour, the head building and settling, the fizz, the
cap pop, the bottle swap, and the shop's beer line before and after
unlocking. Grep for `SHADER ERROR` if the shader changes.

## Left to the builder

Exact shapes and numbers within the targets above. How the foam's look is
drawn (bumps, bubble texture, gradient). The fizz rates. The cap and label
art. How the slow return is formulated, as long as it eases out and leaves
water and wine untouched. Where the tilt-aware helpers live (glass methods
or a small helper). Whether bubbles rise along world-up or the glass's axis
while tipped (world-up preferred).
