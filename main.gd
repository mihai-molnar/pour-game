class_name Main
extends Node2D
## Slice 1 round loop: INTRO → PLAYING → LAST_CALL → SUMMARY (see
## docs/superpowers/specs/2026-10-15-round-loop-design.md). All round logic
## advances only in tick(dt, hold), so check scripts can fast-forward it
## headless (`manual = true`); tweens are used for HUD visuals only.
##
## Dev flags (after `--`):
##   --sweep[=drink_id]   headless tuning table (pourer full and half full), then quit
##   --autoplay           the Autopilot plays: pours, serves, starts the next round
##   --shots=PREFIX       save PREFIX_<nn>.png every --shot-every=S seconds (default 1)
##   --quit=S             quit after S seconds

enum Phase { INTRO, PLAYING, LAST_CALL, SUMMARY }

const GLASS_POS := Vector2(256, 280)
const OFFSCREEN_X := -40.0
const INTRO_TIME := 1.5
const SWAP_OUT_TIME := 0.35
const SWAP_IN_TIME := 0.5
const LAST_CALL_IDLE := 3.0
## A glass counts as touched once it holds this share of its capacity; less can't be served.
const ACTIVE_SHARE := 0.01
const POPUP_POS := Vector2(256, 168)
const STREAK_POS := Vector2(184, 196)
const AUTOPLAY_SUMMARY_WAIT := 1.5
const HINT := "HOLD DOWN: POUR   SPACE: SERVE   F1: DEBUG"

@onready var glass: Glass = $Glass
@onready var pourer: Pourer = $Pourer
@onready var stream: Stream = $Stream
@onready var hud: Hud = $Hud
@onready var summary: RoundSummary = $RoundSummary

## When true, _physics_process does nothing and a check script drives tick().
var manual := false
var phase := Phase.INTRO
var phase_time := 0.0
var time_left := 0.0
var drink: DrinkDef
var streak_steps := 0
## This round's tallies: served, perfects, best_steps, coins.
var round_stats := {}
## Every glass scored this round (Scoring.score results).
var results: Array[Dictionary] = []

var _serve_queued := false
var _swap_t := -1.0  # < 0 when no glass swap is running
var _swap_reset := false
var _swap_brings_glass := true
var _idle := 0.0
var _autopilot: Autopilot
var _clock := 0.0
var _quit_at := INF
var _shot_prefix := ""
var _shot_every := 1.0
var _next_shot := 0.0
var _shot_index := 0


func _ready() -> void:
	drink = GameState.owned_drinks[0]
	glass.setup(drink)
	stream.set_drink(drink)
	pourer.setup(drink)
	pourer.position = GLASS_POS + drink.pourer_offset
	hud.place_streak(STREAK_POS)
	summary.next_pressed.connect(next_round)
	var args := _parse_args()
	if args.has("sweep"):
		_sweep(args["sweep"])
		get_tree().quit()
		return
	if args.has("autoplay"):
		_autopilot = Autopilot.new()
	_shot_prefix = args.get("shots", "")
	_shot_every = float(args.get("shot-every", "1.0"))
	if args.has("quit"):
		_quit_at = float(args["quit"])
	start_round()


func _parse_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	return args


func start_round() -> void:
	phase = Phase.INTRO
	phase_time = 0.0
	time_left = GameState.stats.round_duration
	streak_steps = 0
	round_stats = {"served": 0, "perfects": 0, "best_steps": 0, "coins": 0}
	results.clear()
	_serve_queued = false
	_swap_t = -1.0
	_idle = 0.0
	stream.clear()
	glass.position = GLASS_POS
	glass.reset()
	pourer.reset()
	summary.hide_results()
	hud.show_banner("ROUND %d" % GameState.round_number, INTRO_TIME)
	_refresh_hud()


func next_round() -> void:
	if phase != Phase.SUMMARY:
		return
	GameState.round_number += 1
	start_round()


func is_swapping() -> bool:
	return _swap_t >= 0.0


func is_serving_phase() -> bool:
	return phase == Phase.PLAYING or phase == Phase.LAST_CALL


func request_serve() -> void:
	if not is_serving_phase() or is_swapping() or pourer.refilling:
		return
	_serve_queued = true


func _physics_process(dt: float) -> void:
	if manual:
		return
	_clock += dt
	var hold := Input.is_physical_key_pressed(KEY_DOWN)
	if _autopilot != null:
		var d := _autopilot.decide(self)
		hold = d.hold
		if d.serve:
			request_serve()
		if phase == Phase.SUMMARY and phase_time >= AUTOPLAY_SUMMARY_WAIT:
			next_round()
	tick(dt, hold)
	if _clock >= _quit_at:
		get_tree().quit()


func _process(_dt: float) -> void:
	if _shot_prefix != "" and _clock >= _next_shot:
		_next_shot += _shot_every
		_shot_index += 1
		var path := "%s_%02d.png" % [_shot_prefix, _shot_index]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)


## One fixed step of the whole game. `hold` = DOWN is held this tick.
func tick(dt: float, hold: bool) -> void:
	phase_time += dt
	if phase == Phase.INTRO or phase == Phase.SUMMARY:
		hold = false
	if phase == Phase.INTRO and phase_time >= INTRO_TIME:
		_enter(Phase.PLAYING)
	_step_sim(dt, hold)
	_step_swap(dt)
	if phase == Phase.PLAYING:
		time_left = maxf(time_left - dt, 0.0)
		if time_left <= 0.0:
			_on_time_up()
	if _serve_queued and not is_swapping() and not pourer.is_pouring() and stream.is_empty():
		_serve()
	if phase == Phase.LAST_CALL and not is_swapping():
		if hold or pourer.is_pouring() or not stream.is_empty():
			_idle = 0.0
		else:
			_idle += dt
			if _idle >= LAST_CALL_IDLE:
				_idle = 0.0
				_serve_queued = true
	_refresh_hud()


func _step_sim(dt: float, hold: bool) -> void:
	var out := pourer.step(dt, hold)
	if out > 0.0:
		stream.emit(pourer.global_position, pourer.exit_velocity(), out, dt)
	stream.step(dt, glass)
	glass.step(dt)


func _enter(p: Phase) -> void:
	phase = p
	phase_time = 0.0


func _glass_active() -> bool:
	return glass.volume >= glass.capacity * ACTIVE_SHARE or not stream.is_empty() or pourer.is_pouring()


func _on_time_up() -> void:
	if not is_swapping() and _glass_active():
		_enter(Phase.LAST_CALL)
		_idle = 0.0
		hud.show_banner("LAST CALL!", 1.5)
	else:
		_finish_round()


func _serve() -> void:
	_serve_queued = false
	if glass.volume < glass.capacity * ACTIVE_SHARE:
		if phase == Phase.LAST_CALL:
			_finish_round()
		return
	var r := Scoring.score(glass.volume, glass.target, glass.spilled > 0.5, streak_steps, drink, GameState.stats)
	streak_steps = r.steps
	results.append(r)
	round_stats.served += 1
	if r.band == Scoring.PERFECT:
		round_stats.perfects += 1
	round_stats.best_steps = maxi(round_stats.best_steps, streak_steps)
	round_stats.coins += r.coins
	GameState.coins += r.coins
	hud.popup(r, POPUP_POS)
	_swap_t = 0.0
	_swap_reset = false
	_swap_brings_glass = phase == Phase.PLAYING


## Slides the served glass out, empties it off-screen, and (unless the round
## is ending) slides it back in as the next glass.
func _step_swap(dt: float) -> void:
	if _swap_t < 0.0:
		return
	_swap_t += dt
	if _swap_t < SWAP_OUT_TIME:
		glass.position.x = Tween.interpolate_value(GLASS_POS.x, OFFSCREEN_X - GLASS_POS.x, _swap_t, SWAP_OUT_TIME, Tween.TRANS_QUAD, Tween.EASE_IN)
		return
	if not _swap_reset:
		_swap_reset = true
		glass.position.x = OFFSCREEN_X
		if not _swap_brings_glass:
			_swap_t = -1.0
			if phase == Phase.LAST_CALL:
				_finish_round()
			return
		glass.reset()
	var t_in := _swap_t - SWAP_OUT_TIME
	if t_in >= SWAP_IN_TIME:
		glass.position.x = GLASS_POS.x
		_swap_t = -1.0
		return
	glass.position.x = Tween.interpolate_value(OFFSCREEN_X, GLASS_POS.x - OFFSCREEN_X, t_in, SWAP_IN_TIME, Tween.TRANS_BACK, Tween.EASE_OUT)


func _finish_round() -> void:
	_enter(Phase.SUMMARY)
	_serve_queued = false
	_swap_brings_glass = false
	summary.show_results(GameState.round_number, round_stats, GameState.coins)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			request_serve()
		KEY_F1:
			hud.toggle_debug()
		KEY_ESCAPE:
			get_tree().quit()


func _refresh_hud() -> void:
	hud.set_time(time_left)
	hud.set_coins(GameState.coins)
	hud.set_streak(streak_steps)
	var hint := HINT
	if _serve_queued:
		hint = "SERVING..."
	elif pourer.refilling:
		hint = "REFILLING..."
	hud.set_hint(hint)
	if hud.is_debug_visible():
		var err := (glass.volume - glass.target) / glass.target * 100.0
		hud.set_debug("TILT %3d  FLOW %4d\nJUG  %4d/%d\nGLASS %4d/%d  %+.1f%%\nIN AIR %d  PHASE %s" % [
			roundi(rad_to_deg(pourer.tilt)), roundi(pourer.flow),
			roundi(pourer.volume), roundi(pourer.full_volume),
			roundi(glass.volume), roundi(glass.target), err,
			stream.parcel_count(), Phase.keys()[phase],
		])


## Simulates holds of increasing length — with the pourer full, then half
## full — and prints how much ends up in the glass, how far from the line,
## how much arrived after DOWN was released (the overshoot), and settle time.
func _sweep(drink_id: String) -> void:
	var dt := 1.0 / 60.0
	var d: DrinkDef = GameState.owned_drinks[0]
	for owned in GameState.owned_drinks:
		if String(owned.id) == drink_id:
			d = owned
	print("%s: glass %d px², line at %d px², pourer full %d px² (%.2f glasses)" % [
		d.id, glass.capacity, glass.target, pourer.full_volume, pourer.full_volume / glass.target,
	])
	for fill in [1.0, 0.5]:
		print("-- pourer starts %d%% full --" % roundi(fill * 100.0))
		print("hold_s  release_deg  peak_deg  fill%  vs_line%  after_release%  settle_s  spilled")
		var h := 0.6
		while h <= 4.61:
			stream.clear()
			glass.reset()
			pourer.reset(fill)
			var t := 0.0
			var peak := 0.0
			var at_release := -1.0
			var release_tilt := 0.0
			while t < 15.0:
				var hold := t < h
				if not hold and at_release < 0.0:
					at_release = glass.volume
					release_tilt = pourer.tilt
				_step_sim(dt, hold)
				peak = maxf(peak, pourer.tilt)
				t += dt
				if t > h and pourer.at_rest() and stream.is_empty():
					break
			print("%5.2f  %11d  %8d  %5.1f  %8.1f  %14.1f  %8.2f  %7d" % [
				h, roundi(rad_to_deg(release_tilt)), roundi(rad_to_deg(peak)),
				glass.volume / glass.capacity * 100.0, (glass.volume - glass.target) / glass.target * 100.0,
				(glass.volume - at_release) / glass.capacity * 100.0, t - h, roundi(glass.spilled + stream.spilled),
			])
			h += 0.2
