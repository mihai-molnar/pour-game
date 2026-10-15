extends SceneTree
## Regression check: simulates pours and fails if any bubble is ever outside
## the glass interior. Run:
##   "$GODOT" --headless --path . --script res://tools/check_bubbles.gd


var _main: Node
var _done := false


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run(_main)
	return false


func _run(main: Node) -> void:
	var glass: Glass = main.glass
	var dt := 1.0 / 60.0
	var checked := 0
	var bad := 0
	var worst := ""
	for hold_s in [1.2, 2.0, 2.6, 3.4]:
		main.stream.clear()
		glass.reset()
		main.pitcher.reset()
		var t := 0.0
		while t < hold_s + 2.0:
			main._step_sim(dt, t < hold_s)
			for b in glass._bubbles:
				checked += 1
				var px := Vector2(floorf(b.x) + 0.5, floorf(b.y) + 0.5)
				if not Geometry2D.is_point_in_polygon(px, glass.interior):
					bad += 1
					if worst == "":
						worst = "hold %.1fs t=%.2fs bubble at (%.1f, %.1f), level %.1f" % [hold_s, t, b.x, b.y, glass._level]
			t += dt
	print("bubbles checked: %d, outside the glass: %d" % [checked, bad])
	if bad > 0:
		print("first offender: ", worst)
	quit(1 if bad > 0 else 0)
