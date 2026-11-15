class_name FcLeague
extends RefCounted
## A league: a name plus its structure (conferences > divisions > teams).
## Customizable in size and shape. This is STRUCTURE only. Rules (season
## length, playoff format, salary cap) will be separate league-rules data
## keyed by league_id, so different leagues can have different rules.
##
## A team belongs to a league by being in one of its divisions. The league is
## the single source of truth for membership; teams do not store it.

const SCHEMA_VERSION := 1

var id: int
var name: String = ""
var conferences: Array[FcConference] = []


func _init(league_id: int = 0, league_name: String = "") -> void:
	id = league_id
	name = league_name


## A league with `conferences` x `divisions_per_conference` equal divisions
## holding the team ids 1..team_count in order. Used for previews and
## validation before a real league exists. Remainder teams go to the first
## divisions, so an uneven count still produces a structure.
static func make_even(league_id: int, league_name: String, conference_count: int,
		divisions_per_conference: int, team_count: int) -> FcLeague:
	var league := FcLeague.new(league_id, league_name)
	var cells := maxi(1, conference_count * divisions_per_conference)
	var base := floori(float(team_count) / cells)
	var extra := team_count % cells
	var next_team := 1
	var next_division := 1
	for c in conference_count:
		var conference := FcConference.new(c + 1, "Conference %d" % (c + 1))
		for d in divisions_per_conference:
			var division := FcDivision.new(next_division, "Division %d" % next_division)
			next_division += 1
			var size := base + (1 if (c * divisions_per_conference + d) < extra else 0)
			for i in size:
				division.team_ids.append(next_team)
				next_team += 1
			conference.divisions.append(division)
		league.conferences.append(conference)
	return league


func all_divisions() -> Array[FcDivision]:
	var out: Array[FcDivision] = []
	for c in conferences:
		out.append_array(c.divisions)
	return out


## All team ids in structure order (conference, then division).
func all_team_ids() -> Array[int]:
	var out: Array[int] = []
	for d in all_divisions():
		out.append_array(d.team_ids)
	return out


func team_count() -> int:
	return all_team_ids().size()


func contains_team(team_id: int) -> bool:
	return division_of_team(team_id) != null


func division_of_team(team_id: int) -> FcDivision:
	for d in all_divisions():
		if d.team_ids.has(team_id):
			return d
	return null


func conference_of_team(team_id: int) -> FcConference:
	for c in conferences:
		for d in c.divisions:
			if d.team_ids.has(team_id):
				return c
	return null


func get_division(division_id: int) -> FcDivision:
	for d in all_divisions():
		if d.id == division_id:
			return d
	return null


## Puts a team into a division. OK, ERR_INVALID_PARAMETER (bad team id),
## ERR_DOES_NOT_EXIST (no such division) or ERR_ALREADY_EXISTS (already in this league).
func add_team(division_id: int, team_id: int) -> Error:
	if team_id <= 0:
		return ERR_INVALID_PARAMETER
	var division := get_division(division_id)
	if division == null:
		return ERR_DOES_NOT_EXIST
	if contains_team(team_id):
		return ERR_ALREADY_EXISTS
	division.team_ids.append(team_id)
	return OK


## Removes a team from the league. OK or ERR_DOES_NOT_EXIST.
func remove_team(team_id: int) -> Error:
	var division := division_of_team(team_id)
	if division == null:
		return ERR_DOES_NOT_EXIST
	division.team_ids.erase(team_id)
	return OK


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("league id must be positive")
	if FcChecks.is_blank(name):
		errors.append("league needs a name")
	if conferences.is_empty():
		errors.append("league needs at least one conference")
	var conference_ids := {}
	var division_ids := {}
	var team_seen := {}
	for c in conferences:
		errors.append_array(c.validate())
		if conference_ids.has(c.id):
			errors.append("duplicate conference id %d" % c.id)
		conference_ids[c.id] = true
		for d in c.divisions:
			if division_ids.has(d.id):
				errors.append("duplicate division id %d" % d.id)
			division_ids[d.id] = true
			for tid in d.team_ids:
				if tid <= 0:
					errors.append("division '%s' has invalid team id %d" % [d.name, tid])
				elif team_seen.has(tid):
					errors.append("team %d appears twice in the league" % tid)
				team_seen[tid] = true
	return errors


func to_dict() -> Dictionary:
	var conf_dicts: Array = []
	for c in conferences:
		conf_dicts.append(c.to_dict())
	return {"schema": SCHEMA_VERSION, "id": id, "name": name, "conferences": conf_dicts}


static func from_dict(data: Dictionary) -> FcLeague:
	var l := FcLeague.new(int(data.get("id", 0)), str(data.get("name", "")))
	for c in data.get("conferences", []):
		l.conferences.append(FcConference.from_dict(c))
	return l
