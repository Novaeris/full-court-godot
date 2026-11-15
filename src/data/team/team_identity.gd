class_name FcTeamIdentity
extends RefCounted
## The team's name-level identity: nickname ("Kings"), abbreviation ("HBR")
## and founding year. The city is a separate entity (FcCity) referenced by the
## team, so the full name is built with display_name(city_name).

var nickname: String = ""
var abbreviation: String = ""
var founded_year: int = 2000


## e.g. display_name("Harbor City") -> "Harbor City Kings".
func display_name(city_name: String) -> String:
	return ("%s %s" % [city_name, nickname]).strip_edges()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if FcChecks.is_blank(nickname):
		errors.append("team nickname is required")
	if not FcChecks.is_abbreviation(abbreviation):
		errors.append("team abbreviation '%s' must be 2-4 uppercase letters" % abbreviation)
	if founded_year < 1800 or founded_year > 2200:
		errors.append("founded year %d is out of range" % founded_year)
	return errors


func to_dict() -> Dictionary:
	return {"nickname": nickname, "abbreviation": abbreviation, "founded_year": founded_year}


static func from_dict(data: Dictionary) -> FcTeamIdentity:
	var i := FcTeamIdentity.new()
	i.nickname = str(data.get("nickname", ""))
	i.abbreviation = str(data.get("abbreviation", ""))
	i.founded_year = int(data.get("founded_year", i.founded_year))
	return i
