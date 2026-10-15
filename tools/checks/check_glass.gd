extends CheckBase
## Checks the glass set up from water.tres: exact capacity, fixed target,
## band levels following stats.good_tol, and geometry helpers. Run:
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=glass


func run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	var glass: Glass = main.glass
	var water: DrinkDef = GameState.owned_drinks[0]
	expect(glass.def == water, "glass is set up with water")
	expect(glass.capacity == 2346.0, "capacity = interior pixel count (got %d)" % glass.capacity)
	var want := 0.9 * glass.capacity
	expect(is_equal_approx(glass.target, want), "target = fill_fraction x capacity")
	for i in 5:
		glass.reset()
	expect(is_equal_approx(glass.target, want), "target stays fixed across resets")
	expect(glass.volume == 0.0 and glass.spilled == 0.0, "reset empties the glass")
	expect(is_equal_approx(glass.level_for(0.0), -5.0), "empty level is the floor")
	expect(is_equal_approx(glass.level_for(glass.capacity), -74.0), "full level is the rim")
	var band := glass.band_levels()
	expect(band.x < glass.target_y() and glass.target_y() < band.y, "band edges straddle the fill line (%s vs %.1f)" % [band, glass.target_y()])
	GameState.stats.good_tol = 0.2
	var wide := glass.band_levels()
	GameState.stats.good_tol = 0.1
	expect(wide.x <= band.x and wide.y > band.y, "a wider good_tol widens the band (%s vs %s)" % [wide, band])
	expect(glass.opening_world() == Vector2(237, 275), "opening at the rim (got %s)" % glass.opening_world())
	expect(is_equal_approx(glass.rim_y_world(), 206.0), "rim at y=206 (got %.1f)" % glass.rim_y_world())
	var walls := glass.outer_x_at(-37.0)
	expect(walls.is_equal_approx(Vector2(-19, 19)), "outer walls at mid height (got %s)" % walls)
