class_name DrinkDef
extends Resource
## Everything that makes a drink a drink: the glass, the container you pour
## from, the fill line, the payout and the pour feel. One .tres per drink in
## res://drinks/. Shapes are local pixels with y down: the glass origin is its
## bottom center; the pourer origin is the spout lip (the tilt pivot). Pourer
## shapes are authored upright even when the pourer is held tipped
## (pourer_rest_deg).

## IN_PLACE: the pourer fills up where it stands (a pitcher). NEW_BOTTLE: the
## empty one is replaced by a new, corked one that gets uncorked.
enum RefillStyle { IN_PLACE, NEW_BOTTLE }

@export var id: StringName
@export var display_name := ""
@export var liquid_color := Color("0099db")
## Stream core, sparkles, drips.
@export var liquid_highlight := Color("2ce8f5")

@export_group("Glass")
@export var glass_interior := PackedVector2Array()
@export var glass_outer := PackedVector2Array()
## The fill line as a share of the glass interior — fixed per drink type.
@export_range(0.1, 1.0) var fill_fraction := 0.9
## Corner rounding (px) for drawing the glass smooth; the physics keeps the sharp shapes.
@export var glass_corner_radius := 2.0

@export_group("Payout")
## Coins per scoring step, before the streak multiplier.
@export var perfect_coins := 10
@export var good_coins := 6
@export var ok_coins := 3
## What an overflow costs (never multiplied; the coin total stops at 0).
@export var spill_coins := 6

@export_group("Pourer")
@export var pourer_interior := PackedVector2Array()
@export var pourer_outer := PackedVector2Array()
## Optional handle polyline (empty for bottles).
@export var pourer_handle := PackedVector2Array()
## The pourer's glass: rgb tints it, alpha is the body's tint strength (the
## walls get 3× that, capped at 0.85; tinted glass also shades the liquid).
@export var pourer_glass_color := Color(Palette.FROST, 0.1)
## Corner rounding (px) for drawing the pourer smooth; the physics keeps the sharp shapes.
@export var pourer_corner_radius := 3.0
## A label on the body, local and upright (zero size = none).
@export var pourer_label := Rect2()
## A foil capsule round the neck, local and upright (zero size = none).
@export var pourer_foil := Rect2()
## "Full" as a share of the pourer interior (a brim-full pitcher would pour at the slightest tilt).
@export_range(0.1, 0.99) var pourer_full_fraction := 0.9
@export var spout_dir := Vector2(-1.0, -0.25)
## Spout lip position relative to the glass origin with the pourer at rest.
@export var pourer_offset := Vector2(14, -87)
## The angle (°) it is held at when not pouring: 0 = standing upright; a bottle
## is held tipped over the glass. Tilt and max_tilt_deg count from here.
@export_range(0.0, 90.0) var pourer_rest_deg := 0.0
## How it comes back full once it runs dry.
@export var refill_style := RefillStyle.IN_PLACE

@export_group("Tilt")
## Tilt speed (°/s) while DOWN is held and the liquid hasn't reached the lip yet.
@export var tilt_speed_deg := 45.0
## Tilt speed (°/s) while DOWN is held and it is pouring (careful hands).
@export var pour_tilt_speed_deg := 15.0
## How quickly it reaches that speed (1/s). Lower = heavier container.
@export var tilt_response := 6.0
## Constant pull back toward upright once DOWN is released (rad/s²). Lower = more momentum.
@export var return_force := 3.0
## Velocity damping while returning (1/s); caps the return speed at return_force / return_damp.
@export var return_damp := 2.0
@export_range(30.0, 175.0) var max_tilt_deg := 140.0
## Fraction of speed kept when it clunks back onto the table.
@export var rest_bounce := 0.2

@export_group("Pour")
## Share of the over-the-lip excess that leaves per second.
@export var pour_rate := 7.0
## Hard cap on flow (px²/s).
@export var max_flow := 3000.0
@export var stream_speed_min := 15.0
## Exit speed grows with sqrt(excess), like a weir.
@export var stream_speed_k := 5.0

@export_group("Slosh")
@export var slosh_spring := 60.0
@export var slosh_damp := 4.0
## How strongly tilt acceleration sloshes the surface (braking surges liquid toward the spout).
@export var slosh_gain := 0.04
@export var slosh_max := 0.25
