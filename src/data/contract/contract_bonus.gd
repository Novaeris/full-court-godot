class_name FcContractBonus
extends RefCounted
## A bonus attached to a contract, counted in one specific season.
## How bonuses are prorated or treated by the salary cap is decided later by
## league rules; here we only record the facts.

enum Kind { SIGNING = 0, ROSTER = 1, PERFORMANCE = 2 }

var kind: int = Kind.SIGNING
var season: int = 2026
var amount: int = 0
## Guaranteed bonuses are owed regardless of release (e.g. signing bonuses).
var guaranteed: bool = true
## Whether this bonus counts against the salary cap in `season`.
var counts_against_cap: bool = true


func _init(bonus_kind: int = Kind.SIGNING, bonus_season: int = 2026, bonus_amount: int = 0) -> void:
	kind = bonus_kind
	season = bonus_season
	amount = bonus_amount


func validate() -> Array[String]:
	var errors: Array[String] = []
	if kind < Kind.SIGNING or kind > Kind.PERFORMANCE:
		errors.append("invalid bonus kind")
	if amount < 0:
		errors.append("bonus amount cannot be negative")
	if season < 1800 or season > 2300:
		errors.append("bonus season %d is out of range" % season)
	return errors


func to_dict() -> Dictionary:
	return {
		"kind": kind, "season": season, "amount": amount,
		"guaranteed": guaranteed, "counts_against_cap": counts_against_cap,
	}


static func from_dict(data: Dictionary) -> FcContractBonus:
	var b := FcContractBonus.new(int(data.get("kind", 0)), int(data.get("season", 0)), int(data.get("amount", 0)))
	b.guaranteed = bool(data.get("guaranteed", true))
	b.counts_against_cap = bool(data.get("counts_against_cap", true))
	return b
