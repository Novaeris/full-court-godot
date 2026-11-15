class_name FcTeam
extends RefCounted
## A franchise. The team's `id` never changes, even through relocation or
## rebranding. Layers of change, from most to least permanent:
##   id + identity.founded_year     permanent
##   identity / branding / city / arena / owner   change rarely (relocation, rebrand)
##   roster                          changes constantly
## Not stored here (future records keyed by team_id, plus season):
## finances, season records, coaching staff, history.
##
## `owner_id` is reserved for the Owner Mode owner entity; 0 means none. It is
## not checked against a repository until that entity exists.

const SCHEMA_VERSION := 1

var id: int
var city_id: int = 0
var arena_id: int = 0
var owner_id: int = 0
var identity := FcTeamIdentity.new()
var branding := FcTeamBranding.new()
var roster := FcRoster.new()


func _init(team_id: int = 0) -> void:
	id = team_id


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("team id must be positive")
	if city_id <= 0:
		errors.append("team needs a city")
	if arena_id <= 0:
		errors.append("team needs an arena")
	if owner_id < 0:
		errors.append("owner id cannot be negative")
	errors.append_array(identity.validate())
	errors.append_array(branding.validate())
	errors.append_array(roster.validate())
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "city_id": city_id,
		"arena_id": arena_id, "owner_id": owner_id,
		"identity": identity.to_dict(), "branding": branding.to_dict(),
		"roster": roster.to_dict(),
	}


static func from_dict(data: Dictionary) -> FcTeam:
	var t := FcTeam.new(int(data.get("id", 0)))
	t.city_id = int(data.get("city_id", 0))
	t.arena_id = int(data.get("arena_id", 0))
	t.owner_id = int(data.get("owner_id", 0))
	t.identity = FcTeamIdentity.from_dict(data.get("identity", {}))
	t.branding = FcTeamBranding.from_dict(data.get("branding", {}))
	t.roster = FcRoster.from_dict(data.get("roster", {}))
	return t
