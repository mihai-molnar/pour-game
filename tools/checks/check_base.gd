class_name CheckBase
extends Node
## Base for headless checks in res://tools/checks/, run by tools/run_check.gd
## after autoloads exist (so checks may use GameState and typed game classes).
## Override run(); record failures with expect / eq / near.

var failures := 0


func run() -> void:
	pass


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)


func eq(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		failures += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])


func near(got: float, want: float, what: String, tolerance := 1e-4) -> void:
	if absf(got - want) > tolerance:
		failures += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])
