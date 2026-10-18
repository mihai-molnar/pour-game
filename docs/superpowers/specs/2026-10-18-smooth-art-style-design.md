# Pour Game — Smooth Art Style Design

Date: 2026-10-18
Status: Approved (2026-10-18: "continue with the implementation … go with your
recommendations")

## Overview

The game plays well but looks "like it was made in MS Paint" (user). This
replaces the pixel-art look with a smooth, stylized 2D look, puts the camera
about twice as close so the glass and pourer are what the player looks at,
and makes the liquid properly see-through: through water or wine you see the
bar behind it, bent and tinted the way a filled glass really bends and tints
it.

Direction was settled with a browser mockup the user approved ("this looks
better"), kept as a reference at
`docs/superpowers/specs/2026-10-18-smooth-art-style-mockup.html` (open it in a
browser; it plays itself; `?d=wine` starts on wine). The game must end up
looking like that mockup, with three changes the user asked for after seeing
it:

1. The background **less blurry** (the mockup's heavy blur goes).
2. A real **bar setting** (more convincing than the mockup's shelf of
   bottles).
3. The liquid **see-through, with shaders**, so it looks like you are actually
   looking through water or wine (the mockup's liquid was a flat gradient).

Gameplay doesn't change at all. This is purely how it is drawn and framed.

## Why the current look fails (diagnosis the design answers)

- The subject is tiny: the water glass is ~74 of 360 px (20 % of the screen
  height) and the brick wall is the loudest thing on screen.
- Vessels are 1-px pale outlines with no light, highlights or shadow.
- The liquid refracts the brick pattern, so it reads as noise.
- Code-drawn polygons rotated at native pixel resolution get uneven
  stair-steps; continuous rotation is what pixel art handles worst.

## Goals

- Smooth, anti-aliased rendering at the window's resolution; nothing snaps to
  a 640×360 pixel grid any more.
- The glass and pourer large and central: camera about 1.8× closer than today
  (water glass ≈ 35–40 % of the screen height, wine glass ≈ half).
- A dim, warm evening bar behind them: readable as a real place, a little soft
  so it stays behind the vessels, never busy enough to compete with them.
- Glassware that reads as glass: thickness, highlights, rim, contact shadow.
- See-through liquid: refraction of the bar behind it, colour that deepens
  with how much liquid you look through, a bright surface line.
- HUD and round summary restyled to match (rounded font, soft pills), as in
  the mockup.

## Non-goals

- Any gameplay change: physics, units, tunables (`GameState.stats`, the
  `DrinkDef` pour values), scoring rules, timings, the phase machine. The
  `--sweep` table must come out byte-identical before and after.
- A moving camera, parallax, or screen shake.
- New drinks, the shop, new sounds.
- Keeping a pixel-art mode around (git has it).

## Anti-goals (a failure even if it technically works)

- A muddy or heavily blurred background that hides the refraction.
- A background so detailed or bright that the glass is hard to read, or the
  liquid's refraction turns back into noise (the brick-wall problem).
- Liquid that looks like opaque paint, or like nothing at all (water must
  still read as water at a glance; the fill level must be obvious).
- A drawn surface or fill line that disagrees with what scoring measures:
  at 1.8× zoom one scoring row is 3–6 screen pixels, so a half-row error is
  visible.
- Text that is blurry or hard to read at 1280×720.

## Constraints

- Godot 4.5.1, Forward Plus. The sim stays deterministic (randomness only in
  visuals) and keeps running headless for the sweep, the checks and the
  autopilot.
- World units stay 640×360 "game pixels" (counter top y = 280, all shapes,
  speeds and volumes unchanged). Only rendering and the camera change.
- All checks keep passing (`--check=all`); visual-only expectations that the
  restyle makes wrong (HUD label positions/texts in `check_ui`, any pixel-art
  draw helpers) are updated to the new layout, keeping what they guard
  (e.g. "the multiplier sits right after the coin counter and moves with it").
- The scene order stays: Background, Glass (Liquid, Front), Stream, Pourer
  (Liquid, Front), Effects, HUD. Godot copies the screen once, at the first
  item that reads it, so the liquids refract the background only, not each
  other — that is fine.
- Vessel drawing and physics keep sharing the `DrinkDef` polygons; any
  rounding is a drawing-time derivative of them, never a change to them.
- Fonts must be freely licensed (OFL) and bundled in `fonts/` with their
  licence file.

## Decisions

### Rendering and camera

- **Stretch:** `canvas_items` with base size 640×360 (so HUD layout and world
  units stay), aspect `keep`, fractional scaling; default window 1280×720.
  2D transform/vertex snapping off, default texture filter linear, 2D MSAA 4×
  for polygon edges.
- **Camera:** a static `Camera2D`, zoom ≈ 1.8, framed on the play area
  (roughly world x 122–478, y 86–286: the counter edge at the bottom, the
  glass left of centre, the pourer right of it). The exact numbers are the
  builder's to tune, with these rules: at common pouring tilts the whole
  pourer stays in frame (a near-empty pitcher or bottle tipped far, i.e. its
  third glass, may clip at the top edge); arriving vessels still start fully off-screen (glass from
  x = −40, pourer from x = 680, both outside the view); popups and banners
  stay on screen.
- **Screenshots:** `--shots` saves at the window's resolution (e.g.
  1280×720), not 640×360.

### Background: a bar

- A new background image of an evening bar, generated by a script and
  committed (replacing `art/background.png` and `tools/make_background.py`).
- **Generator (my call):** an HTML canvas page under `tools/` rendered to PNG
  by headless Google Chrome (installed on the dev machine), via a small
  script. The canvas API (gradients, arcs, Béziers, `filter: blur`) is far
  better for illustration than Pillow, and the approved mockup's background
  is already canvas code to start from. Seeded randomness, so it regenerates
  identically. The resulting PNG is what the game uses; Chrome is only a dev
  tool.
- **Resolution:** at least 2560×1440 for the camera's view (≈ 7 image pixels
  per world unit), placed in world space so the counter's top surface lines
  up with world y = 280 under the camera. A little margin beyond the view.
- **Content:** a dim, warm bar at night.
  - Back bar: two or three backlit shelves of bottles in varied shapes and
    colours, with labels and glints; a dark wood or mirror-backed cabinet.
  - Warm pendant lamps (or their light pools) above, a neon sign (the
    mockup's cocktail glass is fine), a few soft bokeh lights.
  - The bar counter in the foreground: polished dark wood whose top surface
    holds the vessels at y = 280, with a bright front edge and a warm light
    pool where the glass stands.
- **Softness:** far layers slightly soft (about 1–1.5 px of blur at 1280×720,
  far less than the mockup), the counter sharp. Behind the glass and pourer
  there is mid-level detail (bottles, shelf edges, lights) so refraction has
  something to bend, but at lower contrast and brightness than the vessels.
- **Readability:** the glass walls and fill line must read clearly against
  every part of the background they can sit in front of; a vignette and
  a darker band behind the play area are allowed.

### Vessels (glass and pourers)

Drawn as in the mockup:

- **Shape:** rounded copies of the physics polygons (small corner radii,
  larger on the wine glass bowl so it reads as a curve). Rounding never moves
  the fill line or the drawn liquid level.
- **Walls:** filled between outer and interior with a horizontal light
  gradient (brighter at the edges), a soft dark outline for separation from
  the background.
- **Light:** a specular streak following the inside of the left wall, a
  thinner second streak, a rim light on the right edge, a bright rim line on
  top of the glass with a faint rim ellipse.
- **Grounding:** a soft contact shadow on the counter under the glass and
  under the pourer when it is near the counter; a faint reflection of the
  vessels in the polished counter (lowest priority: can be dropped if it costs
  real complexity).
- **Pitcher:** clear glass, faint blue tint; the handle a thick rounded
  glassy stroke with a highlight.
- **Wine bottle:** green glass (`pourer_glass_color`), a cream label with a
  simple emblem, a dark-red foil on the neck, a lighter lip ring; the cork
  (while corked) and the flying cork drawn smooth.
- **Fill line and band:** the same meaning as today — a white line with a
  dark outline at the target, a bracket left of the glass spanning GOOD
  ENOUGH (±`ok_rows`) with inner ticks at ±`good_rows`, the line's outline
  marking PERFECT — drawn smooth as in the mockup. The line sits
  exactly where `rows_from_line` measures from (anti-goal above).
  My call: since scoring rounds both the settled level and the target to
  whole rows, the line is centred on `round(target_y)` and the marks sit
  where the step really changes: the dark outline spans ±1.5 rows (PERFECT),
  the inner ticks ±3.5 (GOOD), the bracket ends ±6.5 (GOOD ENOUGH). That
  makes the outline a bit thicker than the mockup's, which is fine.

### See-through liquid (the shader)

`liquid.gdshader` is rewritten for smooth rendering (no whole-pixel
rounding, no dithering, linear screen sampling). What the player should see:

- **Refraction:** the bar behind the liquid, magnified and bent across the
  vessel's width the way a liquid-filled cylinder acts as a lens (strongest
  toward the walls), with a gentle wobble while the surface moves. It follows
  the vessel's rotation (the tilting pourer).
- **Absorption:** colour deepens with how much liquid the eye looks through —
  thicker in the middle of a round vessel, deeper toward the bottom.
  - Water: clear, the bar plainly visible through it, a light blue tint that
    grows with depth; it must still read as water (blue) at a glance.
  - Wine: deep red; the bar shows through only dimly, mostly as a lighter
    ruby near the walls where the wine is thin.
- **Surface:** a bright surface line with a slightly lighter band just under
  it, following the waves.
- **Light:** a soft vertical highlight inside the left wall, matching the
  glass's streak.
- Per-drink look values live in the `DrinkDef` or the material, in the
  existing pattern (look uniforms in materials; geometry uniforms set by the
  vessel scripts).
- **Liquid shape:** the glass's liquid becomes a smooth polygon whose top is
  the per-column wave surface (the 1D wave sim is unchanged), clipped to the
  rounded interior; the pourer's liquid is today's clipped polygon, clipped
  to the rounded interior. Bubbles become small soft circles; overflow drips
  smooth.

### Stream and effects

- **Stream:** a smooth tapered ribbon through the parcels (thinner as it
  falls and speeds up), semi-transparent drink colour with a bright core,
  attached to the spout while flow is continuous; drops at low flow as small
  round drops. The joining rules (consecutive ticks, landing, spout) stay as
  today. No refraction shader on the stream (my call — it is thin and fast).
- **Effects:** puffs, dust, cork spray and splash droplets as soft round
  particles instead of pixel squares; same triggers, counts and lifetimes.

### HUD and round summary

- **Font (my call):** Fredoka (SIL OFL, Google Fonts), bundled with its
  licence; replaces Press Start 2P everywhere.
- **Layout as in the mockup:** coins top left as a coin icon + number in a
  soft dark pill, the streak multiplier right after it in the same pill (dim
  at x1, gold above; the pop-up-and-fly and the "denied" shake stay), the
  timer top centre in a pill (red in the last 5 s), the key hint bottom left.
- Result popups (coins only, coloured by step, as today — my call: the
  mockup's small step name under the number is left out) with a soft
  shadow, at the glass; ROUND / LAST CALL / NEW DRINK banners large and centred.
- The round summary as a rounded dark panel in the same style; its contents
  and input lock are unchanged.
- Text renders crisp at the window resolution.

### Colours

- `Palette` stays the single place for named colours and grows the new ones
  (bar woods, label cream, neon pink, …). Gradients and alpha variants
  between them are expected; the strict ENDESGA-32-only rule is retired.

## Left to the builder

- Exact zoom and framing within the camera rules above.
- Exact colours, gradient stops, corner radii, highlight and shader
  constants, font sizes, the background's composition within the content
  list.
- How rounding, gradients, shadows and the reflection are implemented in
  Godot (e.g. `Geometry2D.offset_polygon` with round joins, gradient textures
  with UVs, a small wall shader).
- Which pixel-art helpers become dead code and are removed.

## Done means

- The game, played at 1280×720 and at fullscreen, looks like the mockup with
  the three requested changes; the user playtests and approves.
- `--sweep` and `--sweep=wine` output byte-identical to before the change.
- All checks print their OK lines.
- `--autoplay` screenshots at window resolution show both drinks pouring.
- CLAUDE.md updated (rendering, camera, background generator, visual
  identity, commands).
