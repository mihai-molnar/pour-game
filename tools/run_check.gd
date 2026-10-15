extends SceneTree
## Runs headless checks from res://tools/checks/ once autoloads exist — a
## --script file itself can't reference GameState or any class that uses it.
## Usage (from the project root):
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=round
##   "$GODOT" --headless --path . --quit-after 900 --script res://tools/run_check.gd -- --check=all
## Prints "check_<name>: OK" per passing check and exits 1 if any failed. A
## check fails if it records a failure or logs any script error. No OK line at
## all means the runner itself crashed — read the error output.

const DIR := "res://tools/checks/"


class ErrorCounter extends Logger:
	var errors := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors += 1


func _process(_delta: float) -> bool:
	var wanted := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--check="):
			wanted = a.trim_prefix("--check=")
	var names: Array[String] = []
	if wanted == "all":
		for file in DirAccess.get_files_at(DIR):
			if file.begins_with("check_") and file.ends_with(".gd") and file != "check_base.gd":
				names.append(file.trim_prefix("check_").trim_suffix(".gd"))
	else:
		names.append(wanted)
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var gs: Node = root.get_node("GameState")
	var failed := 0
	for n in names:
		gs.reset_session(1)
		var errors_before := counter.errors
		var script: Script = load(DIR + "check_%s.gd" % n)
		var check: Node = script.new() if script != null and script.can_instantiate() else null
		if check == null:
			print("check_%s: FAILED (could not load tools/checks/check_%s.gd)" % [n, n])
			failed += 1
			continue
		root.add_child(check)
		check.run()
		var errors := counter.errors - errors_before
		if check.failures == 0 and errors == 0:
			print("check_%s: OK" % n)
		else:
			print("check_%s: FAILED (%d failures, %d script errors)" % [n, check.failures, errors])
			failed += 1
		check.free()
	OS.remove_logger(counter)
	quit(1 if failed > 0 else 0)
	return false
