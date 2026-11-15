class_name FcStaffContract
extends RefCounted
## An employment agreement between one staff member and one team for a
## specific job (`role`). Separate from FcContract (players) on purpose:
## staff pay comes out of the operating budget, not the salary cap, and has no
## guarantees/bonuses/cap-hit rules. Reuses FcContractYear for seasonal pay.
##
## A staff member's current job is their ACTIVE contract; there is no separate
## "staff list" on the team, so there is a single source of truth.

const SCHEMA_VERSION := 1

var id: int
var staff_id: int = 0
var team_id: int = 0
var role: int = FcStaffRole.Id.ASSISTANT_COACH
var signed_on: FcDate = FcDate.new(2026, 7, 1)
## Uses FcContract.Status (ACTIVE / EXPIRED / TERMINATED).
var status: int = FcContract.Status.ACTIVE
var years: Array[FcContractYear] = []


func _init(contract_id: int = 0) -> void:
	id = contract_id


func start_season() -> int:
	return years[0].season if not years.is_empty() else 0


func end_season() -> int:
	return years[years.size() - 1].season if not years.is_empty() else 0


func year_for(season: int) -> FcContractYear:
	for y in years:
		if y.season == season and y.is_in_effect():
			return y
	return null


func is_in_force_in(season: int) -> bool:
	return status == FcContract.Status.ACTIVE and year_for(season) != null


func salary_for(season: int) -> int:
	var y := year_for(season)
	return y.salary if y != null else 0


func total_value() -> int:
	var total := 0
	for y in years:
		if y.is_in_effect():
			total += y.salary
	return total


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("staff contract id must be positive")
	if staff_id <= 0:
		errors.append("staff contract needs a staff member")
	if team_id <= 0:
		errors.append("staff contract needs a team")
	if not FcStaffRole.is_valid(role):
		errors.append("staff contract role is invalid")
	if not signed_on.is_valid():
		errors.append("signing date is not valid")
	if status < FcContract.Status.ACTIVE or status > FcContract.Status.TERMINATED:
		errors.append("invalid contract status")
	if years.is_empty():
		errors.append("staff contract needs at least one year")
	for i in years.size():
		errors.append_array(years[i].validate())
		if i > 0 and years[i].season != years[i - 1].season + 1:
			errors.append("contract seasons must be consecutive and ascending")
	return errors


func to_dict() -> Dictionary:
	var year_dicts: Array = []
	for y in years:
		year_dicts.append(y.to_dict())
	return {
		"schema": SCHEMA_VERSION, "id": id, "staff_id": staff_id, "team_id": team_id,
		"role": role, "signed_on": signed_on.to_iso(), "status": status, "years": year_dicts,
	}


static func from_dict(data: Dictionary) -> FcStaffContract:
	var c := FcStaffContract.new(int(data.get("id", 0)))
	c.staff_id = int(data.get("staff_id", 0))
	c.team_id = int(data.get("team_id", 0))
	c.role = int(data.get("role", FcStaffRole.Id.ASSISTANT_COACH))
	var d := FcDate.from_iso(str(data.get("signed_on", "")))
	c.signed_on = d if d != null else FcDate.new(0, 0, 0)
	c.status = int(data.get("status", FcContract.Status.ACTIVE))
	for y in data.get("years", []):
		c.years.append(FcContractYear.from_dict(y))
	return c
