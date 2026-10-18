class_name Main
extends Node2D
## The round loop: INTRO → PLAYING → LAST_CALL → SHOP, each glass a random
## drink from the menu (see docs/superpowers/specs/2026-10-15-round-loop-design.md,
## 2026-10-15-second-drink-design.md, 2026-10-18-upgrade-shop-design.md and
## 2026-10-18-menu-shop-and-ice-physics-design.md). Glasses and pourers arrive by
## sliding in. All round logic advances only in tick(dt, hold), so check
## scripts can fast-forward it headless (`manual = true`); tweens are used for
## HUD visuals only.
##
## Dev flags (after `--`):
##   --sweep[=drink_id]   headless tuning table for that drink (default water), pourer full and half full, then quit
##   --autoplay           the Autopilot plays: pours, serves, visits the shop, starts the next round
##   --seed=N             seed the drink picks so a run repeats
##   --coins=N            start the session with N coins
##   --shop               open the shop at startup (round 1 comes after it)
##   --shots=PREFIX       save PREFIX_<nn>.png every --shot-every=S seconds (default 1)
##   --quit=S             quit after S seconds

enum Phase { INTRO, PLAYING, LAST_CALL, SHOP }

const GLASS_POS := Vector2(256, 280)
## The static camera: the world point at the screen centre, and how much closer
## than 1:1 it shows the 640x360 world.
const CAMERA_CENTER := Vector2(300, 199)
const CAMERA_ZOOM := 1.65
const SCREEN_SIZE := Vector2(640, 360)
## The world rect the background image covers (art/background.png, 7 image px
## per world px; tools/background/bar.html draws it with the same numbers).
const BACKGROUND_RECT := Rect2(100, 84, 400, 230)
## The counter lip's lower edge (world y; bar.html's LIP_BOTTOM): below it is
## the bar's front, where the key row sits.
const COUNTER_LIP_Y := 286.5
## How much counter front (HUD units) the view shows below the lip for the key row.
const KEY_ROOM := 34.0
const INTRO_TIME := 1.5
## The last-call glass vanishes this long before the shop opens, so its popup reads.
const SHOP_DELAY := 0.35
const LAST_CALL_IDLE := 3.0
## A glass counts as touched once it holds this share of its capacity; less can't be served.
const ACTIVE_SHARE := 0.01
## Result popups float this far above the glass's rim (world px).
const POPUP_ABOVE_RIM := 14.0
const AUTOPLAY_SHOP_WAIT := 1.5

@onready var glass: Glass = $Glass
@onready var pourer: Pourer = $Pourer
@onready var stream: Stream = $Stream
@onready var effects: Effects = $Effects
@onready var hud: Hud = $Hud
@onready var shop: Shop = $Shop
@onready var camera: Camera2D = $Camera
@onready var shadows: Shadows = $Shadows
@onready var reflection: Reflection = $Reflection

## When true, _physics_process does nothing and a check script drives tick().
var manual := false
var phase := Phase.INTRO
var phase_time := 0.0
var time_left := 0.0
## The current glass's drink; the pourer always matches it.
var drink: DrinkDef
## GOOD-or-better glasses in a row this round (Scoring.multiplier turns it into the payout multiplier).
var streak := 0
## This round's tallies: served, perfects, best_mult, coins.
var round_stats := {}
## Every glass scored this round (Scoring.score results plus "drink", its id).
var results: Array[Dictionary] = []
## The DOWN hold the last tick() used (false during INTRO and in the shop) — the DOWN key shows it.
var hold_down := false

var _serve_queued := false
var _shop_in := -1.0  # >= 0 while the last-call glass's puff plays before the shop opens
var _force_next: DrinkDef  # the next glass's drink when it isn't random (a just-bought drink)
var _idle := 0.0
var _autopilot: Autopilot
var _clock := 0.0
var _quit_at := INF
var _shot_prefix := ""
var _shot_every := 1.0
var _next_shot := 0.0
var _shot_index := 0


func _ready() -> void:
	shadows.glass = glass
	shadows.pourer = pourer
	reflection.glass = glass
	reflection.pourer = pourer
	shop.next_pressed.connect(next_round)
	glass.landed.connect(_on_landed)
	glass.garnish_landed.connect(_on_garnish_landed)
	pourer.landed.connect(_on_landed)
	pourer.vanished.connect(effects.puff)
	pourer.popped.connect(effects.cork)
	var args := _parse_args()
	if args.has("seed"):
		GameState.rng.seed = int(args["seed"])
	if args.has("sweep"):
		_sweep(args["sweep"])
		get_tree().quit()
		return
	if args.has("coins"):
		GameState.coins = int(args["coins"])
	if args.has("autoplay"):
		_autopilot = Autopilot.new()
	_shot_prefix = args.get("shots", "")
	_shot_every = float(args.get("shot-every", "1.0"))
	if args.has("quit"):
		_quit_at = float(args["quit"])
	if args.has("shop"):
		GameState.round_number = 0  # the round after this shop is round 1
		open_shop()
	else:
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
	streak = 0
	round_stats = {"served": 0, "perfects": 0, "best_mult": 1.0, "coins": 0}
	results.clear()
	_serve_queued = false
	_shop_in = -1.0
	_idle = 0.0
	stream.clear()
	effects.clear()  # bits frozen while the shop was open don't replay
	var fresh := GameState.take_new_drink()
	_force_next = fresh
	drink = _pick_drink()
	stream.set_drink(drink)
	glass.arrive(drink, GLASS_POS)
	pourer.arrive(drink, GLASS_POS + drink.pourer_offset)
	hud.show_banner(Hud.round_banner(GameState.round_number, fresh), INTRO_TIME)
	hud.set_streak(1.0, false)  # a new round's x1 isn't a broken streak
	_refresh_hud()


## The round is over: the shop opens with the round's numbers (none before
## the first round, under --shop); the bar and the HUD hide while it is open.
func open_shop() -> void:
	_enter(Phase.SHOP)
	_serve_queued = false
	_show_world(false)
	shop.open(Shop.round_line(GameState.round_number, round_stats) if not round_stats.is_empty() else "")


## From the shop to the next round.
func next_round() -> void:
	if phase != Phase.SHOP:
		return
	shop.close()
	_show_world(true)
	GameState.round_number += 1
	start_round()


## Shows or hides the bar (this node's canvas items) and the HUD; the shop is
## a layer of its own.
func _show_world(on: bool) -> void:
	visible = on
	hud.visible = on


## The next glass's drink: a just-bought drink first, otherwise any drink on the menu.
func _pick_drink() -> DrinkDef:
	if _force_next != null:
		var d := _force_next
		_force_next = null
		return d
	var menu := GameState.menu
	return menu[GameState.rng.randi_range(0, menu.size() - 1)]


## The world rect the camera shows.
static func view_rect() -> Rect2:
	var size := SCREEN_SIZE / CAMERA_ZOOM
	return Rect2(CAMERA_CENTER - size * 0.5, size)


## A world point in HUD (screen) coordinates, through the static camera.
func world_to_hud(p: Vector2) -> Vector2:
	return (p - CAMERA_CENTER) * CAMERA_ZOOM + SCREEN_SIZE * 0.5


## Where a result popup for the current glass starts (HUD), above its rim.
func popup_at() -> Vector2:
	return world_to_hud(Vector2(GLASS_POS.x, glass.rim_y_world() - POPUP_ABOVE_RIM))


func is_swapping() -> bool:
	return glass.is_arriving() or pourer.is_arriving()


func is_serving_phase() -> bool:
	return phase == Phase.PLAYING or phase == Phase.LAST_CALL


## Adds the current drink's garnish for `key` (UP ice, LEFT lime) to the glass
## — while serving, once the glass has landed, if the player owns it and it
## isn't on the glass yet. True if it was added.
func try_garnish(key: Key) -> bool:
	if not _can_garnish():
		return false
	for g in drink.garnishes:
		if g.key == key and GameState.owns_garnish(g):
			if not glass.add_garnish(g):
				return false
			hud.keys.press_garnish(key)
			return true
	return false


## True while a garnish can go on the glass: serving, the glass landed, the round not ending.
func _can_garnish() -> bool:
	return is_serving_phase() and _shop_in < 0.0 and glass.visible and not glass.is_arriving() and drink != null


## The garnishes a key press would add right now (the current drink's, owned,
## not on the glass yet), in the drink's order — the garnish keys on screen.
func garnish_keys() -> Array[GarnishDef]:
	var out: Array[GarnishDef] = []
	if not _can_garnish():
		return out
	for g in drink.garnishes:
		if GameState.owns_garnish(g) and not glass.has_garnish(g.id):
			out.append(g)
	return out


## True while serving with something (ACTIVE_SHARE or more) in the glass:
## the SPACE key shows then — mid-pour too, where a press queues the serve
## until the pour lands. Only an empty glass has no SPACE key.
func glass_has_drink() -> bool:
	return is_serving_phase() and _shop_in < 0.0 and glass.visible and glass.volume >= glass.capacity * ACTIVE_SHARE


## True while a serve waits for the pour to land (the SPACE key stays down).
func is_serve_queued() -> bool:
	return _serve_queued


func request_serve() -> void:
	if not is_serving_phase() or is_swapping() or pourer.is_busy():
		return
	_serve_queued = true
	hud.keys.space.press()


func _physics_process(dt: float) -> void:
	if manual:
		return
	_clock += dt
	var hold := Input.is_physical_key_pressed(KEY_DOWN)
	if _autopilot != null:
		var d := _autopilot.decide(self)
		hold = d.hold
		for k in d.keys:
			try_garnish(k)
		if d.serve:
			request_serve()
		if phase == Phase.SHOP and phase_time >= AUTOPLAY_SHOP_WAIT:
			_autopilot.shop(self)
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
	if phase == Phase.SHOP:
		hold_down = false
		return  # the round is over and the bar is hidden
	if phase == Phase.INTRO:
		hold = false
	hold_down = hold
	if phase == Phase.INTRO and phase_time >= INTRO_TIME:
		_enter(Phase.PLAYING)
	_step_sim(dt, hold)
	effects.step(dt)
	if _shop_in >= 0.0:
		_shop_in -= dt
		if _shop_in <= 0.0:
			_shop_in = -1.0
			_finish_round()
		_refresh_hud()
		return
	if phase == Phase.PLAYING:
		time_left = maxf(time_left - dt, 0.0)
		if time_left <= 0.0:
			_on_time_up()
	if _serve_queued and not is_swapping() and not pourer.is_pouring() and stream.is_empty() and not glass.garnish_busy():
		_serve()
	if phase == Phase.LAST_CALL and not is_swapping():
		if hold or pourer.is_pouring() or pourer.is_busy() or not stream.is_empty() or glass.garnish_busy():
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
	# Only an arriving glass is empty; a bottle refill can arrive with the glass mid-pour.
	if not glass.is_arriving() and _glass_active():
		_enter(Phase.LAST_CALL)
		_idle = 0.0
		hud.show_banner("LAST CALL!", 1.5)
	else:
		_finish_round()


## Scores the glass; it vanishes and (unless it's last call) the next glass
## arrives — with the other pourer when the drink changes.
func _serve() -> void:
	_serve_queued = false
	if glass.volume < glass.capacity * ACTIVE_SHARE:
		if phase == Phase.LAST_CALL:
			_finish_round()
		return
	var error := (glass.volume - glass.target) / glass.target
	var r := Scoring.score(glass.rows_from_line(glass.volume), error, glass.spilled > 0.5, streak, drink, GameState.stats, glass.garnishes)
	r.coins = maxi(r.coins, -GameState.coins)  # a spill can't take the total below 0
	r["drink"] = drink.id
	streak = r.streak
	results.append(r)
	round_stats.served += 1
	if r.band == Scoring.PERFECT:
		round_stats.perfects += 1
	round_stats.best_mult = maxf(round_stats.best_mult, Scoring.multiplier(streak, GameState.stats))
	round_stats.coins += r.coins
	GameState.coins += r.coins
	hud.popup(r, popup_at())
	effects.puff(glass.center_global())
	if phase == Phase.LAST_CALL:
		glass.vanish()
		_shop_in = SHOP_DELAY
		return
	var next := _pick_drink()
	if next != drink:
		effects.puff(pourer.center_global())
		pourer.arrive(next, GLASS_POS + next.pourer_offset)
		stream.set_drink(next)
	drink = next
	glass.arrive(drink, GLASS_POS)


## Ice landing in liquid splashes.
func _on_garnish_landed(g: GarnishDef, at: Vector2) -> void:
	if g.kind == GarnishDef.Kind.ICE and glass.volume >= 0.5:
		effects.splash(at, drink.liquid_highlight)


## Dust only where an arrival lands on the counter (a held bottle lands in mid-air).
func _on_landed(at: Vector2) -> void:
	if at.y >= GLASS_POS.y - 1.0:
		effects.dust(at)


func _finish_round() -> void:
	open_shop()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			request_serve()
		KEY_UP, KEY_LEFT:
			try_garnish(key.physical_keycode)
		KEY_F1:
			hud.toggle_debug()
		KEY_ESCAPE:
			get_tree().quit()


func _refresh_hud() -> void:
	hud.set_time(time_left)
	hud.set_coins(GameState.coins)
	hud.set_streak(Scoring.multiplier(streak, GameState.stats))
	hud.keys.sync(self)
	if hud.is_debug_visible():
		var err := (glass.volume - glass.target) / glass.target * 100.0
		var extras: Array[String] = []
		for g in glass.garnishes:
			extras.append(String(g.id))
		hud.set_debug("TILT %3d  FLOW %4d\nJUG  %4d/%d\nGLASS %4d/%d  %+.1f%%\nIN AIR %d  PHASE %s\nGARNISH %s" % [
			roundi(rad_to_deg(pourer.tilt)), roundi(pourer.flow),
			roundi(pourer.volume), roundi(pourer.full_volume),
			roundi(glass.volume), roundi(glass.target), err,
			stream.parcel_count(), Phase.keys()[phase], ", ".join(extras) if not extras.is_empty() else "-",
		])


## Simulates holds of increasing length — with the pourer full, then half
## full — and prints how much ends up in the glass, how far from the line,
## how much arrived after DOWN was released (the overshoot), and settle time.
func _sweep(drink_id: String) -> void:
	var dt := 1.0 / 60.0
	var d: DrinkDef = GameState.WATER
	if drink_id != "":
		var path := "res://drinks/%s.tres" % drink_id
		if not ResourceLoader.exists(path):
			printerr("no drink %s" % path)
			return
		d = load(path)
	glass.setup(d)
	glass.place(GLASS_POS)
	pourer.setup(d)
	pourer.place(GLASS_POS + d.pourer_offset)
	stream.set_drink(d)
	print("%s: glass %d px², line at %d px², pourer full %d px² (%.2f glasses)" % [
		d.id, glass.capacity, glass.target, pourer.full_volume, pourer.full_volume / glass.target,
	])
	for fill in [1.0, 0.5]:
		print("-- pourer starts %d%% full --" % roundi(fill * 100.0))
		print("hold_s  release_deg  peak_deg  fill%  vs_line%  after_release%  settle_s  spilled")
		var h := 0.6
		while h <= 4.61:
			stream.clear()
			stream.spilled = 0.0  # per row: stream.clear() keeps the running total
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
