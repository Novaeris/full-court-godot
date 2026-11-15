class_name FcDefinitionSet
extends RefCounted
## Bundles the three catalogs every player needs: basketball attributes,
## personality traits and tendencies. Loaded from data/definitions/*.json.

const DEFINITIONS_DIR := "res://data/definitions/"

var attributes: FcAttributeCatalog
var personality: FcAttributeCatalog
var tendencies: FcAttributeCatalog


static func load_default() -> FcDefinitionSet:
	var s := FcDefinitionSet.new()
	s.attributes = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "attributes.json")
	s.personality = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "personality.json")
	s.tendencies = FcAttributeCatalog.from_file(DEFINITIONS_DIR + "tendencies.json")
	return s


func validate() -> Array[String]:
	var errors: Array[String] = []
	for c in [attributes, personality, tendencies]:
		if c == null:
			errors.append("missing catalog")
			continue
		errors.append_array(c.load_errors)
		if c.size() == 0:
			errors.append("catalog '%s' is empty" % c.kind)
	return errors
