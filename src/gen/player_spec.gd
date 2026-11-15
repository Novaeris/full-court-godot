class_name FcPlayerSpec
extends RefCounted
## What the caller wants from the player generator. Everything else (body,
## attributes, personality, tendencies, development profile) is generated.

var age: int = 25
var position: int = FcPosition.Id.SF
## Current overall ability, 0-100: attributes are centered on this value
## (adjusted by position). ~35 = bench/fringe, ~50 = solid rotation,
## ~65 = starter, 75+ = star.
var level: float = 50.0
var country_key: String = ""
## The date on which `age` is measured.
var reference_date: FcDate = FcDate.new(2026, 10, 1)
## Full names already taken (see FcNameGenerator.generate_unique); optional.
var used_names: Dictionary = {}
