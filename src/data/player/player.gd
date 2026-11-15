class_name FcPlayer
extends RefCounted
## A player as a stable entity. Composed of small parts, each with one job:
##   identity     (FcPlayerIdentity)    who he is
##   physical     (FcPlayerPhysical)    body measurements
##   attributes   (FcAttributeSet)      basketball ratings
##   personality  (FcAttributeSet)      off-court traits
##   tendencies   (FcAttributeSet)      how he likes to play
##   development  (FcPlayerDevelopment) growth profile
##
## Deliberately NOT stored here: contracts (FcContract, by player_id), team
## membership (FcRoster), and statistics/history (future records keyed by
## player_id). That keeps this object small and lets history grow without
## bloating the player.

const SCHEMA_VERSION := 1

enum Status { PROSPECT = 0, ACTIVE = 1, RETIRED = 2 }

var id: int
var status: int = Status.ACTIVE
## Season in which the player retired; 0 while not retired.
var retired_season: int = 0
var primary_position: int = FcPosition.Id.SF
var secondary_position: int = FcPosition.Id.NONE

var identity := FcPlayerIdentity.new()
var physical := FcPlayerPhysical.new()
var development := FcPlayerDevelopment.new()
var attributes: FcAttributeSet
var personality: FcAttributeSet
var tendencies: FcAttributeSet


func _init(player_id: int, defs: FcDefinitionSet) -> void:
	id = player_id
	attributes = FcAttributeSet.new(defs.attributes)
	personality = FcAttributeSet.new(defs.personality)
	tendencies = FcAttributeSet.new(defs.tendencies)


## Age in whole years on the given date.
func age_on(date: FcDate) -> int:
	return identity.birth_date.years_until(date)


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("player id must be positive")
	errors.append_array(identity.validate())
	errors.append_array(physical.validate())
	errors.append_array(development.validate())
	errors.append_array(attributes.validate())
	errors.append_array(personality.validate())
	errors.append_array(tendencies.validate())
	if not FcPosition.is_valid(primary_position):
		errors.append("primary position is invalid")
	if not FcPosition.is_valid(secondary_position, true):
		errors.append("secondary position is invalid")
	elif secondary_position == primary_position:
		errors.append("secondary position must differ from primary")
	if status < Status.PROSPECT or status > Status.RETIRED:
		errors.append("invalid status %d" % status)
	elif status == Status.RETIRED and retired_season <= 0:
		errors.append("retired player needs a retirement season")
	elif status != Status.RETIRED and retired_season != 0:
		errors.append("only retired players may have a retirement season")
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"id": id,
		"status": status,
		"retired_season": retired_season,
		"primary_position": primary_position,
		"secondary_position": secondary_position,
		"identity": identity.to_dict(),
		"physical": physical.to_dict(),
		"development": development.to_dict(),
		"attributes": attributes.to_dict(),
		"personality": personality.to_dict(),
		"tendencies": tendencies.to_dict(),
	}


static func from_dict(data: Dictionary, defs: FcDefinitionSet) -> FcPlayer:
	var p := FcPlayer.new(int(data.get("id", 0)), defs)
	p.status = int(data.get("status", Status.ACTIVE))
	p.retired_season = int(data.get("retired_season", 0))
	p.primary_position = int(data.get("primary_position", FcPosition.Id.SF))
	p.secondary_position = int(data.get("secondary_position", FcPosition.Id.NONE))
	p.identity = FcPlayerIdentity.from_dict(data.get("identity", {}))
	p.physical = FcPlayerPhysical.from_dict(data.get("physical", {}))
	p.development = FcPlayerDevelopment.from_dict(data.get("development", {}))
	p.attributes = FcAttributeSet.from_dict(defs.attributes, data.get("attributes", {}))
	p.personality = FcAttributeSet.from_dict(defs.personality, data.get("personality", {}))
	p.tendencies = FcAttributeSet.from_dict(defs.tendencies, data.get("tendencies", {}))
	return p
