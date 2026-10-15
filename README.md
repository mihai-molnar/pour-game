# Pour prototype

A side-view pouring game at 640×360: fill each glass to the fill line before the round timer runs out, and the liquid is pixel-art refracted water.

## Controls

- **Hold ↓** — tilt the pourer. It swings fast until the water reaches the lip, then slowly while pouring.
- **Release** — it eases back upright; liquid already in the air (and a little more from the lip) still lands.
- **Space** — serve the glass (waits for the stream to finish); on the summary screen, start the next round.
- **F1** debug readout · **Esc** quit

## Rounds

- 30 s timer. Serve as many glasses as you can: within ±3 % of the line = PERFECT (10 coins), within ±10 % = GOOD (8→2), else MISS; overflowing = SPILLED.
- Streak multiplier x1 → x3: GOOD adds a step, PERFECT two; MISS/SPILL resets it. The multiplier before the glass pays out.
- At 0:00 it is LAST CALL: liquid in the air still lands and the last glass is served, then the summary and the next round. The pourer refills automatically when it runs dry.

## Dev flags and checks

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --path .                                                  # play
"$GODOT" --headless --path . -- --sweep                            # tuning table (--sweep=<drink_id>)
"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all
"$GODOT" --path . --windowed --resolution 1280x720 -- --autoplay --shots=/abs/prefix --shot-every=1.5 --quit=40
```

See `CLAUDE.md` for architecture, tuning and the check runner.

## Tuning live

Run from the editor (F5), switch the Scene dock to **Remote**, select `Pourer` / `Glass` / `Stream` and edit the exported values. Gameplay tunables live in `GameState.stats`; the liquid look lives in each vessel's `Liquid` node material.
