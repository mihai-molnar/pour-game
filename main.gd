extends Node2D
## Pour prototype: hold DOWN to tilt the pitcher, release and it swings back
## (still pouring while it does). SPACE serves the glass once the stream has
## finished; the score depends on how close the fill is to the gold line.
##
## Dev modes (pass after `--` on the command line):
##   --sweep            headless: simulate holds of 0.2–1.6 s and print the results
##   --hold=S           autopilot: hold DOWN for S seconds, starting at 0.6 s
##   --shots=PREFIX     save screenshots to PREFIX_<n>.png during an autopilot run
##   --quit=S           quit after S seconds

const GLASS_X := 256.0
const SHOT_TIMES := [0.5, 1.6, 2.6, 3.15, 3.35, 3.6, 4.0, 5.0, 6.2]

@onready var glass: Glass = $Glass
@onready var pitcher: Pitcher = $Pitcher
@onready var stream: Stream = $Stream

var coins := 0
var served := 0
var _streak_steps := 0
var _serve_queued := false
var _swapping := false
var _time := 0.0
var _auto_from := INF
var _auto_to := INF
var _auto_serve_at := INF
var _quit_at := INF
var _shot_prefix := ""
var _shot_index := 0

var _hud: Control
var _coins_label: Label
var _status_label: Label
var _debug_label: Label


func _ready() -> void:
	var drink: DrinkDef = GameState.owned_drinks[0]
	glass.setup(drink)
	stream.set_drink(drink)
	_build_hud()
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("sweep"):
		_sweep()
		get_tree().quit()
		return
	if args.has("hold"):
		_auto_from = 0.6
		_auto_to = 0.6 + float(args["hold"])
		_auto_serve_at = _auto_to + 0.8
	if args.has("shots"):
		_shot_prefix = args["shots"]
	if args.has("quit"):
		_quit_at = float(args["quit"])


func _physics_process(dt: float) -> void:
	_time += dt
	var hold := Input.is_physical_key_pressed(KEY_DOWN) or (_time >= _auto_from and _time < _auto_to)
	_step_sim(dt, hold)
	if _time >= _auto_serve_at:
		_auto_serve_at = INF
		_serve_queued = true
	if _serve_queued and not _swapping and not pitcher.is_pouring() and stream.is_empty():
		_serve()
	_update_hud()
	if _time >= _quit_at:
		get_tree().quit()


func _process(_dt: float) -> void:
	if _shot_prefix != "" and _shot_index < SHOT_TIMES.size() and _time >= SHOT_TIMES[_shot_index]:
		_shot_index += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_shot_prefix, _shot_index])


func _step_sim(dt: float, hold: bool) -> void:
	var out := pitcher.step(dt, hold)
	if out > 0.0:
		stream.emit(pitcher.global_position, pitcher.exit_velocity(), out, dt)
	stream.step(dt, glass)
	glass.step(dt)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			if not _swapping:
				_serve_queued = true
		KEY_F1:
			_debug_label.visible = not _debug_label.visible
		KEY_R:
			coins = 0
			served = 0
			_streak_steps = 0
			stream.clear()
			glass.reset()
			pitcher.reset()
		KEY_ESCAPE:
			get_tree().quit()


func _serve() -> void:
	_serve_queued = false
	_swapping = true
	var result := Scoring.score(glass.volume, glass.target, glass.spilled > 0.5, _streak_steps, GameState.owned_drinks[0], GameState.stats)
	_streak_steps = result.steps
	coins += result.coins
	served += 1
	_popup(result)
	var tw := create_tween()
	tw.tween_property(glass, "position:x", -40.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		glass.reset()
		if pitcher.refill_on_serve:
			pitcher.refill()
	)
	tw.tween_property(glass, "position:x", GLASS_X, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _swapping = false)


func _popup(result: Dictionary) -> void:
	var pct := roundi(result.error * 100.0)
	var text: String
	var color: Color
	if result.band == Scoring.PERFECT:
		text = "PERFECT! +%d" % result.coins
		color = Palette.GOLD
	elif result.band == Scoring.GOOD:
		text = "GOOD %+d%% +%d" % [pct, result.coins]
		color = Palette.GREEN
	elif result.band == Scoring.SPILL:
		text = "SPILLED!"
		color = Palette.RED
	else:
		text = "MISS %+d%%" % pct
		color = Palette.RED
	var label := _label(Vector2(GLASS_X - 100, 168), color)
	label.size = Vector2(200, 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	var tw := create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 24.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(label.queue_free)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = load("res://fonts/PressStart2P-Regular.ttf")
	theme.default_font_size = 8
	_hud.theme = theme
	layer.add_child(_hud)
	_coins_label = _label(Vector2(8, 8), Palette.GOLD)
	_status_label = _label(Vector2(8, 344), Palette.FROST)
	_debug_label = _label(Vector2(8, 24), Palette.FROST)


func _label(pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Palette.INK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 4)
	_hud.add_child(l)
	return l


func _update_hud() -> void:
	_coins_label.text = "COINS %d   GLASSES %d" % [coins, served]
	_status_label.text = "SERVING..." if _serve_queued else "HOLD DOWN: POUR   SPACE: SERVE   F1: DEBUG   R: RESET"
	if _debug_label.visible:
		var err := (glass.volume - glass.target) / glass.target * 100.0
		_debug_label.text = "TILT %3d  FLOW %4d\nJUG  %4d/%d\nGLASS %4d/%d  %+.1f%%\nIN AIR %d" % [
			roundi(rad_to_deg(pitcher.tilt)), roundi(pitcher.flow),
			roundi(pitcher.volume), roundi(pitcher.capacity),
			roundi(glass.volume), roundi(glass.target), err,
			stream._parcels.size(),
		]


## Simulates holds of increasing length and prints how much ends up in the
## glass, how much of it arrived after DOWN was released (the overshoot),
## and how far the pitcher kept tilting after release (momentum).
func _sweep() -> void:
	var dt := 1.0 / 60.0
	print("glass capacity %d px², pitcher %d px² (starts %d)" % [glass.capacity, pitcher.capacity, pitcher.capacity * pitcher.start_fill])
	print("hold_s  release_deg  peak_deg  fill%  after_release%  settle_s  spilled")
	var h := 0.6
	while h <= 4.21:
		stream.clear()
		glass.reset()
		pitcher.reset()
		var t := 0.0
		var peak := 0.0
		var at_release := -1.0
		var release_tilt := 0.0
		while t < 15.0:
			var hold := t < h
			if not hold and at_release < 0.0:
				at_release = glass.volume
				release_tilt = pitcher.tilt
			_step_sim(dt, hold)
			peak = maxf(peak, pitcher.tilt)
			t += dt
			if t > h and pitcher.at_rest() and stream.is_empty():
				break
		print("%5.2f  %11d  %8d  %5.1f  %14.1f  %8.2f  %7d" % [
			h, roundi(rad_to_deg(release_tilt)), roundi(rad_to_deg(peak)), glass.volume / glass.capacity * 100.0,
			(glass.volume - at_release) / glass.capacity * 100.0, t - h, roundi(glass.spilled + stream.spilled),
		])
		h += 0.2
