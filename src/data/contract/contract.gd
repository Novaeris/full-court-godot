class_name FcContract
extends RefCounted
## An agreement between one player and one team. A first-class entity with its
## own ID: players and teams refer to it, not the other way round, so a player
## can have a contract history and a team can have many contracts.
##
## This class answers factual questions (value, guaranteed money, cap hit for
## a season). The RULES about the salary cap (limits, exceptions, proration)
## are a future league-rules system that will use these answers.

const SCHEMA_VERSION := 1

enum Status { ACTIVE = 0, EXPIRED = 1, TERMINATED = 2 }

var id: int
var player_id: int = 0
var team_id: int = 0
var signed_on: FcDate = FcDate.new(2026, 7, 1)
var status: int = Status.ACTIVE
var years: Array[FcContractYear] = []
var bonuses: Array[FcContractBonus] = []


func _init(contract_id: int = 0) -> void:
	id = contract_id


## Years that are actually part of the deal (declined options removed).
func effective_years() -> Array[FcContractYear]:
	var out: Array[FcContractYear] = []
	for y in years:
		if y.is_in_effect():
			out.append(y)
	return out


func length() -> int:
	return effective_years().size()


## First season of the contract, or 0 if it has no years.
func start_season() -> int:
	return years[0].season if not years.is_empty() else 0


## Last season actually in effect, or 0 if none.
func end_season() -> int:
	var eff := effective_years()
	return eff[eff.size() - 1].season if not eff.is_empty() else 0


## The year entry for a season if it is in effect, else null.
func year_for(season: int) -> FcContractYear:
	for y in years:
		if y.season == season and y.is_in_effect():
			return y
	return null


## True when the contract is ACTIVE and covers the given season.
func is_in_force_in(season: int) -> bool:
	return status == Status.ACTIVE and year_for(season) != null


func salary_for(season: int) -> int:
	var y := year_for(season)
	return y.salary if y != null else 0


## Salary plus cap-counting bonuses for a season. 0 if not in force then.
func cap_hit_for(season: int) -> int:
	var y := year_for(season)
	if y == null:
		return 0
	var total := y.salary
	for b in bonuses:
		if b.season == season and b.counts_against_cap:
			total += b.amount
	return total


func total_value() -> int:
	var total := 0
	for y in effective_years():
		total += y.salary
	for b in bonuses:
		total += b.amount
	return total


func total_guaranteed() -> int:
	var total := 0
	for y in effective_years():
		total += y.guaranteed
	for b in bonuses:
		if b.guaranteed:
			total += b.amount
	return total


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("contract id must be positive")
	if player_id <= 0:
		errors.append("contract needs a player")
	if team_id <= 0:
		errors.append("contract needs a team")
	if not signed_on.is_valid():
		errors.append("signing date is not valid")
	if status < Status.ACTIVE or status > Status.TERMINATED:
		errors.append("invalid contract status")
	if years.is_empty():
		errors.append("contract needs at least one year")
	for i in years.size():
		errors.append_array(years[i].validate())
		if i > 0 and years[i].season != years[i - 1].season + 1:
			errors.append("contract seasons must be consecutive and ascending")
	for b in bonuses:
		errors.append_array(b.validate())
		if not years.is_empty() and (b.season < years[0].season or b.season > years[years.size() - 1].season):
			errors.append("bonus season %d is outside the contract" % b.season)
	return errors


func to_dict() -> Dictionary:
	var year_dicts: Array = []
	for y in years:
		year_dicts.append(y.to_dict())
	var bonus_dicts: Array = []
	for b in bonuses:
		bonus_dicts.append(b.to_dict())
	return {
		"schema": SCHEMA_VERSION, "id": id, "player_id": player_id,
		"team_id": team_id, "signed_on": signed_on.to_iso(), "status": status,
		"years": year_dicts, "bonuses": bonus_dicts,
	}


static func from_dict(data: Dictionary) -> FcContract:
	var c := FcContract.new(int(data.get("id", 0)))
	c.player_id = int(data.get("player_id", 0))
	c.team_id = int(data.get("team_id", 0))
	var d := FcDate.from_iso(str(data.get("signed_on", "")))
	c.signed_on = d if d != null else FcDate.new(0, 0, 0)
	c.status = int(data.get("status", Status.ACTIVE))
	for y in data.get("years", []):
		c.years.append(FcContractYear.from_dict(y))
	for b in data.get("bonuses", []):
		c.bonuses.append(FcContractBonus.from_dict(b))
	return c
