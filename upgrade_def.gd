class_name UpgradeDef
extends Resource
## Something bought once in the shop that changes a drink for good, with no
## key to press: it pays more on every glass (sparkling water, premium and
## vintage wine), or its pourer refills faster. One .tres per upgrade in
## res://upgrades/, listed on its drink's `upgrades`.

## The wine bottle's label: plain, premium (gold-trimmed) or vintage (dark,
## with a gold crest and a year).
enum LabelLook { PLAIN, PREMIUM, VINTAGE }

@export var id: StringName
@export var display_name := ""
## The shop line's text, e.g. "Water pays +40%".
@export var description := ""
@export var price := 25
## The share added to each step's coins; it adds up with the garnishes'.
@export_range(0.0, 2.0) var bonus := 0.0
## How much faster its drink refills: 0.5 = 50 % faster (the time / 1.5).
@export_range(0.0, 4.0) var refill_speed := 0.0
## Must be owned first; this one's bonus then takes its place (vintage
## replaces premium).
@export var replaces: UpgradeDef
## Bubbles per second it adds to its drink's glass (sparkling). Visual only.
@export var fizz := 0.0
@export var label_look := LabelLook.PLAIN
