class_name FcPosition
extends RefCounted
## Basketball positions. Stored as integers in saves; never renumber them.

enum Id { NONE = 0, PG = 1, SG = 2, SF = 3, PF = 4, C = 5 }

const ABBREVIATIONS := {0: "-", 1: "PG", 2: "SG", 3: "SF", 4: "PF", 5: "C"}
## The five real positions in id order (no "none"). Content validation, Dynasty slots and screens all reuse this one list
## instead of keeping their own copies, so a position rule can only drift in one place.
const PLAYABLE := ["PG", "SG", "SF", "PF", "C"]


static func is_valid(value: int, allow_none: bool = false) -> bool:
	if value == Id.NONE:
		return allow_none
	return value >= Id.PG and value <= Id.C


static func abbreviation(value: int) -> String:
	return ABBREVIATIONS.get(value, "?")
