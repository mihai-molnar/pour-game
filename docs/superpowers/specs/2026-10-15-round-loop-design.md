# Pour Game — Slice 1: Round Loop Design

Date: 2026-10-15
Status: Draft — awaiting review

## Overview

Turns the pour prototype (playtest verdict: "felt pretty good") into the first
real slice of the game: timed rounds of water pours with a streak multiplier,
a pitcher that drains across glasses, a last-call ending, and a round summary.
Drinks become data (`DrinkDef` resources) so slice 2 can add a second drink
mostly as content.

### Where this sits in the whole game (outline, not a contract)

- Purpose: start small, decide later; Steam is a someday goal, so avoid
  choices that block it (drinks as data, input that can map to a gamepad)
  without building for it yet.
- Core action: hold DOWN to tilt, release and the container swings back with
  momentum, still pouring; fill to the drink's line.
- Rounds: 30 s timer, serve as many glasses as you can; a streak multiplier
  rewards consecutive good pours.
- Drinks: glass + container pairs, each with a fixed fill line per drink type
  (water glass almost full, beer mug bigger and almost full, tea cup lower).
  New drinks are bought in the shop; each glass in a round is a random drink
  you own; harder drinks pay more.
- Containers drain across glasses and refill automatically when empty.
- Shop between rounds: upgrades (coin gain, pour speed, wider tolerance) and
  drink unlocks.
- Slices: **1 round loop with water (this spec)** → 2 second drink + mixed
  rounds → 3 shop → later: more drinks, long-term goal, saving, juice/sound,
  gamepad. No lose state for now; the game is endless.

## Decisions Made

- **Round pressure:** 30 s timer plus streak multiplier (not customers, not a
  fixed glass count).
- **Streak:** GOOD = +1 step, PERFECT = +2 steps; steps map to ×1, ×1.5, ×2,
  ×2.5, ×3 (cap at 4 steps). MISS or SPILL resets to ×1; every round starts
  at ×1.
- **Timer end:** "last call" — no new glass after 0:00, but the current glass
  can be finished and served.
- **Fill line:** fixed per drink type. Water: 90 % of the glass.
- **Container level:** drains across glasses; automatic refill when empty
  (no key press). Other key-press actions are reserved and will be discussed
  later — Space keeps serving for now.
- **Build approach:** evolve the prototype; drinks are Godot `Resource` files
  editable in the Inspector (not code dictionaries, not a rewrite).
- **Band markers:** the ±GOOD tolerance band is drawn on the glass alongside
  the fill line.

## Round Flow

Phases, owned by `main.gd`: `INTRO → PLAYING → LAST_CALL → SUMMARY → INTRO`.

1. **INTRO** (1.5 s): "ROUND N" banner; the pitcher starts full; the timer is
   not running; DOWN and Space are ignored.
2. **PLAYING:** the timer counts down from `stats.round_duration` (30 s).
   Pour and serve as in the prototype. Serving (Space) queues and fires once
   the pourer isn't pouring and no liquid is in the air, so in-flight liquid
   always counts. The glass then slides out (0.35 s) and a new one slides in
   (0.5 s); the timer keeps running through swaps and refills.
3. **At 0:00:** if the current glass is *active* — it holds ≥ 1 % of its
   capacity, or liquid is in the air, or the pourer is pouring — enter
   **LAST_CALL**; otherwise (mid-swap, untouched glass) go straight to
   **SUMMARY**.
4. **LAST_CALL:** "LAST CALL!" banner. No new glass will come. Space serves as
   usual; if nothing happens for 3 s (DOWN not held, not pouring, nothing in
   the air) the glass is served automatically. After that serve's glass has
   slid out → **SUMMARY**.
5. **SUMMARY:** a screen showing glasses served, perfects, best streak
   multiplier, coins this round, and total coins. Space or a click on
   "NEXT ROUND" → `GameState.round_number += 1` → **INTRO**.

Coins persist across rounds for the session only (saving is a later slice).

## Scoring

Error is signed and relative to the target: `error = (volume − target) / target`.

| Band | Rule | Base coins |
|---|---|---|
| SPILL | the glass overflowed at any point | 0 |
| PERFECT | \|error\| ≤ `stats.perfect_tol` (0.03) | `perfect_coins` (10) |
| GOOD | \|error\| ≤ `stats.good_tol` (0.10) | lerp from `good_coins_max` (8) at the PERFECT edge to `good_coins_min` (2) at the GOOD edge |
| MISS | otherwise | 0 |

Band edges are inclusive. Coins paid for a glass:
`roundi(base × multiplier × stats.coin_mult)`, where `multiplier` is the streak
multiplier *before* this glass is applied (the HUD shows what the next glass
pays). The streak is then updated from the band.

Serving a glass holding < 1 % of its capacity is ignored (no score, no streak
change) so a stray Space press costs nothing.

## Pitcher Level and Refill

- The water pitcher holds about 2.5 glasses at the fill line
  (≈ 2.5 × 0.9 × glass capacity ≈ 5 300 px² with the current glass); its exact
  shape is tuned with the sweep (see Testing).
- Each round starts with a full pitcher; it drains across glasses.
- **Auto-refill:** when the pourer's volume drops below 1 % of its capacity it
  enters REFILLING: input is ignored, it returns upright with its normal return
  motion, then its volume refills over `stats.refill_time` (1.0 s). The glass
  stays in place; liquid already in the air still lands. If DOWN is still held
  when the refill finishes, tilting continues.

## Data Model

### `drink_def.gd` (`class_name DrinkDef extends Resource`) + `drinks/water.tres`

Everything that makes a drink a drink, all `@export`ed:

- Identity and look: `id: StringName`, `display_name: String`,
  `liquid_color: Color`, `liquid_highlight: Color` (stream core, sparkles).
- Glass: `glass_interior`, `glass_outer: PackedVector2Array` (local px, origin
  at the glass's bottom center), `fill_fraction: float` (water 0.9).
- Payout: `perfect_coins` (10), `good_coins_max` (8), `good_coins_min` (2).
- Pourer shape: `pourer_interior`, `pourer_outer`, `pourer_handle:
  PackedVector2Array` (local px, origin at the spout lip = pivot; handle may be
  empty), `spout_dir: Vector2`, `pourer_offset: Vector2` (spout lip position
  relative to the glass origin when at rest).
- Pour feel (the prototype's tuned values as defaults): `tilt_speed_deg`,
  `pour_tilt_speed_deg`, `tilt_response`, `return_force`, `return_damp`,
  `max_tilt_deg`, `rest_bounce`, `pour_rate`, `max_flow`, `stream_speed_min`,
  `stream_speed_k`, `slosh_spring`, `slosh_damp`, `slosh_gain`, `slosh_max`.

World constants (gravity, drip thresholds, counter height) stay on `Stream`.
Shader look parameters other than the liquid color stay in the materials in
`main.tscn` for now.

### `game_state.gd` (autoload `GameState`)

- `coins: int`, `round_number: int`, `owned_drinks: Array[DrinkDef]` (water
  only in this slice).
- `stats` dictionary — the upgrade seam, same pattern as ultra-kill: gameplay
  reads these at point of use and never hard-codes a value that has a key.
  Slice 1 keys and values: `round_duration = 30.0`, `perfect_tol = 0.03`,
  `good_tol = 0.10`, `coin_mult = 1.0`, `pour_speed_mult = 1.0` (multiplies
  both `tilt_speed_deg` and `pour_tilt_speed_deg`; return motion is
  unaffected), `refill_time = 1.0`.

## Components

- `scoring.gd` (`class_name Scoring`, static functions only): band from error
  and spill flag; base coins from band/error and a `DrinkDef`; streak step
  update; multiplier from steps; paid coins. No scene dependencies.
- `pourer.gd` (`class_name Pourer`, from `pitcher.gd`): `setup(def)` takes
  shape and tuning from the `DrinkDef`; adds the REFILLING state; draws itself
  generically from the def's polygons (faint body fill, outer and inner
  outlines, handle, base, and a highlight stripe derived from the left inner
  wall — no hand-placed coordinates).
- `glass.gd`: `setup(def)`; target is fixed at `fill_fraction × capacity`
  (no more random targets); draws from the def's polygons; draws the fill line
  and the band markers (below); evaluation moves to `Scoring`.
- `stream.gd`: liquid colors from the current `DrinkDef`; exposes
  `parcel_count()` instead of the debug readout reading `_parcels`.
- `liquid.gdshader`: unchanged; `tint` is set from `liquid_color`.
- `main.gd`: phases, timer, serve queue, glass swaps, last-call idle timer,
  refill trigger, per-round stats; keeps the fixed simulation order
  (`pourer.step` → `stream.emit` → `stream.step` → `glass.step`) in
  `_step_sim`, and the dev flags (`--sweep[=drink_id]`, `--hold`, `--shots`,
  `--quit`).
- `hud.gd`: timer (top center, `M:SS`, red in the last 5 s), coins (top left),
  streak multiplier near the glass (pops when it changes), result popups,
  "ROUND N" and "LAST CALL!" banners, F1 debug readout.
- `round_summary.gd` + `round_summary.tscn`: the summary screen on a
  `CanvasLayer`; emits `next_pressed`.

## Visuals

- **Fill line:** must read clearly against both the tiled background and the
  liquid. Starting style: a 1 px light line (`Palette.WHITE`) with 1 px dark
  rows (`Palette.INK`) above and below, spanning the glass interior, plus
  outlined tick marks just outside both walls.
- **Band markers:** a thin vertical bracket just outside the glass's left wall
  from the −`good_tol` level to the +`good_tol` level (levels from
  `level_for(target × (1 ± good_tol))`), with short end ticks, dark-outlined
  like the fill line. Upgrading `good_tol` later visibly widens it. For water
  the upper edge sits at ~99 % of the glass, just under the rim.
- Styles are tuned with autopilot screenshots; the palette stays the
  ENDESGA 32 subset in `palette.gd`.

## Edge Cases

- Space is ignored during INTRO, glass swaps, REFILLING and SUMMARY.
- A glass that overflows is a SPILL whenever it's served, even if later
  levels look fine.
- The pitcher running dry mid-pour: in-flight liquid still lands; refill
  follows; the glass waits.
- 0:00 during a glass swap or with an inactive glass ends the round
  immediately (no LAST_CALL).
- LAST_CALL idle detection resets whenever DOWN is held, the pourer pours, or
  liquid is in the air.

## Testing

No test framework (as in ultra-kill); headless check scripts exit 1 on failure
and run with `--quit-after` as a safety net.

- `tools/check_scoring.gd` — band edges at exactly ±3 % / ±10 % (inclusive),
  GOOD coin interpolation endpoints, streak steps (GOOD → ×1.5, PERFECT → ×2,
  cap ×3, MISS/SPILL reset), multiplier-before-update payout, rounding,
  `coin_mult`.
- `tools/check_round.gd` — fast-forwarded rounds with a scripted autopilot:
  phase order; no new glass after 0:00; LAST_CALL auto-serve after 3 s idle;
  immediate SUMMARY when 0:00 hits mid-swap or with an inactive glass; round
  coins equal the sum of paid glasses; refill triggers when dry and blocks
  pouring for `refill_time`; streak and phase reset on the next round.
- `tools/check_bubbles.gd` — unchanged, kept passing.
- `--sweep=water` — after resizing the pitcher, keep the prototype's feel:
  pouring starts ~0.5 s into a hold from a full pitcher, and ~11–14 % of glass
  capacity lands after release; the sweep also reports pours from a half-full
  pitcher.
- Autopilot screenshots: fill line and band contrast, HUD, banners, summary.
- Playtest by the user.

## Out of Scope

Shop and upgrades UI, any second drink or drink mixing, saving/loading, sound,
gamepad input, key actions other than Space-to-serve, a long-term goal or
ending, resolution or vessel-scale changes.

After implementation, update `CLAUDE.md` (and `README.md`) to describe the
round loop instead of the prototype.
