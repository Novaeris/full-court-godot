class_name FcDefinitionSet
extends RefCounted
## Bundles every catalog of ratings the game uses. Loaded from
## data/definitions/*.json. Add a new catalog by adding a JSON file, a member
## here, and a line in load_default() and all().

const DEFINITIONS_DIR := "res://data/definitions/"

## Players: basketball ratings, off-court traits, how they like to play.
var attributes: FcAttributeCatalog
var personality: FcAttributeCatalog
var tendencies: FcAttributeCatalog
## Staff: professional skills and coaching/management philosophy.
var staff_skills: FcAttributeCatalog
var philosophy: FcAttributeCatalog


static func load_default() -> FcDefinitionSet:
	var s := FcDefinitionSet.new()
	s.attributes = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "attributes.json")
	s.personality = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "personality.json")
	s.tendencies = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "tendencies.json")
	s.staff_skills = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "staff_skills.json")
	s.philosophy = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "philosophy.json")
	return s


func all() -> Array[FcAttributeCatalog]:
	return [attributes, personality, tendencies, staff_skills, philosophy]


func validate() -> Array[String]:
	var errors: Array[String] = []
	for c in all():
		if c == null:
			errors.append("missing catalog")
			continue
		errors.append_array(c.load_errors)
		if c.size() == 0:
			errors.append("catalog '%s' is empty" % c.kind)
	return errors
