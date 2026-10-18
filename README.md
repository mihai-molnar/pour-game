# Pour prototype

A side-view pouring game: fill each glass to the fill line before the round timer runs out. It is drawn smooth, close up, in an evening bar, and the liquid is see-through — water and wine bend and tint the bar behind them.

## Controls

- **Hold ↓** — tilt the pourer. It swings fast until the water reaches the lip, then slowly while pouring.
- **Release** — it eases back upright; liquid already in the air (and a little more from the lip) still lands.
- **Space** — serve the glass (waits for the stream to finish); on the summary screen, start the next round.
- **F1** debug readout · **Esc** quit

## Rounds

- 30 s timer. Serve as many glasses as you can, scored by how many rows (of the game's 640×360 grid) the surface is from the line: 0–1 = PERFECT (10 coins), 2–3 = GOOD (6), 4–6 = GOOD ENOUGH (3), further = MISS (0). Overflowing = SPILL, which costs 6 coins (never below 0).
- Streak multiplier (shown next to your coins): GOOD-or-better glasses in a row build it — x1 for the first, x1.2 after the second, then +0.1 per glass up to x3. GOOD ENOUGH keeps it; MISS/SPILL and a new round reset it. The multiplier before the glass pays out.
- At 0:00 it is LAST CALL: liquid in the air still lands and the last glass is served, then the summary and the next round. The pourer refills automatically when it runs dry.
- From round 2, wine joins water: each glass is randomly water or wine. Wine is poured from a bottle into a big stemmed glass with the line at its widest point (PERFECT 15, GOOD 9, GOOD ENOUGH 5; a spill costs 9); an empty bottle is replaced and uncorked.

## Dev flags and checks

```bash
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --path .                                                  # play
"$GODOT" --headless --path . -- --sweep                            # tuning table (--sweep=wine for the bottle)
"$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all
"$GODOT" --path . -- --autoplay --seed=11 --shots=/abs/prefix --shot-every=1.5 --quit=70   # --seed=N seeds the drink picks; shots at the window's resolution
tools/make_background.sh                                           # regenerate the bar background (needs Google Chrome)
```

See `CLAUDE.md` for architecture, tuning and the check runner.

## Tuning live

Run from the editor (F5), switch the Scene dock to **Remote**, select `Pourer` / `Glass` / `Stream` and edit the exported values. Gameplay tunables live in `GameState.stats`; the liquid look lives in each drink's `DrinkDef` (colour, absorption, scatter) and in each vessel's `Liquid` node material (lens, wobble, edge glow).
