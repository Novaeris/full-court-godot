class_name FcPlayerBuild
extends RefCounted
## Career Mode player builds: the rules that decide whether a created player is allowed, and the function that
## turns a valid build into a real FcPlayer in the world. Everything here is PURE (no UI, no saved state, no
## randomness except through the FcRng passed in) so the identical code can run on a future online server:
## a client may only ask for a build; the server calls validate() and decides.
##
## A build ("spec") is a plain Dictionary so it can travel and be saved:
##   first_name, last_name, country, position, secondary_position (0 = none), height_cm, weight_kg, wingspan_cm,
##   handedness (0 right, 1 left, 2 both), jersey_number, archetype (key in data/career/archetypes.json),
##   potential (0-100), attributes {attribute key: int}, appearance {skin, hair, face, facial_hair}.
## The attributes are the shared 0-100 catalog (data/definitions/attributes.json); nothing here defines a second set.
## The numbers live in data/career/build_rules.json.

static func rules() -> Dictionary:
	return FcBuildRules.rules()


## An integer from untrusted input: ints and floats pass, numeric text is parsed, anything else (null, text, lists)
## gives `fallback`, so validation reports a clear error instead of crashing.
static func _int(value, fallback: int = 0) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return fallback


## Which version of these rules a build was validated under; stored on every profile.
static func ruleset_version() -> int:
	return int(rules().get("ruleset_version", 1))


## The highest potential a body allows: taller and longer-armed players can be better than the reference body,
## smaller ones are capped lower. Potential is a ceiling for development, never a promise.
static func potential_cap(spec: Dictionary) -> int:
	var cfg: Dictionary = rules()["potential_cap"]
	var height := _int(spec.get("height_cm", 198), 198)
	var wingspan := _int(spec.get("wingspan_cm", height + 5), height + 5)
	var value := float(cfg["base"]) + float(cfg["per_cm_over_reference"]) * (height - int(rules()["physical"]["reference_height_cm"])) \
		+ float(cfg["per_cm_wingspan_over_height"]) * (wingspan - height - 5)
	return clampi(roundi(value), int(cfg["min"]), int(cfg["max"]))


## The most an attribute can ever reach for this build: set by potential, bent by the body (height, wingspan, weight).
## Always between the attribute floor + 20 and the attribute cap, so every attribute can be developed somewhat.
static func attribute_ceiling(key: String, spec: Dictionary) -> int:
	var r := rules()
	var potential := _int(spec.get("potential", 50), 50)
	var value := float(r["ceiling_base"]) + float(r["ceiling_per_potential"]) * potential
	var mods: Dictionary = r["ceiling_modifiers"]
	var height := _int(spec.get("height_cm", 198), 198)
	var wingspan := _int(spec.get("wingspan_cm", height + 5), height + 5)
	var weight := _int(spec.get("weight_kg", 95), 95)
	value += float(mods["per_cm_height"].get(key, 0.0)) * (height - int(r["physical"]["reference_height_cm"]))
	value += float(mods["per_cm_wingspan"].get(key, 0.0)) * (wingspan - height - 5)
	value += float(mods["per_10kg"].get(key, 0.0)) * (weight - int(r["physical"]["reference_weight_kg"])) / 10.0
	return clampi(roundi(value), int(r["attribute_floor"]) + 20, int(r["attribute_cap"]))


## The build values of an existing player that decide his ceilings (height, weight, wingspan, potential).
## `build_potential` (from the career profile, 0 = use the player's current potential) keeps the ceilings from shrinking as the
## league ages the player.
static func spec_of(player: FcPlayer, build_potential: int = 0) -> Dictionary:
	return {"height_cm": player.physical.height_cm, "weight_kg": player.physical.weight_kg, "wingspan_cm": player.physical.wingspan_cm,
		"potential": build_potential if build_potential > 0 else player.development.potential}


## Points spent above (or saved below) the baseline: the sum of (value - baseline) over every attribute.
static func budget_used(attributes: Dictionary) -> int:
	var total := 0
	for key in attributes:
		total += _int(attributes[key], int(rules()["baseline"])) - int(rules()["baseline"])
	return total


## A starting build for an archetype: baseline attributes plus the archetype's bonus points, a typical body for the
## position, no secondary position, and a potential five below the body's cap. A hybrid starts from "custom" or
## from any archetype and then changes attributes.
static func default_spec(archetype_key: String, position: int, defs: FcDefinitionSet) -> Dictionary:
	var bodies := {1: [188, 84, 194], 2: [196, 90, 202], 3: [201, 96, 207], 4: [207, 105, 214], 5: [212, 114, 220]}
	var body: Array = bodies.get(position, bodies[3])
	var attributes := {}
	for key in defs.attributes.keys():
		attributes[key] = int(rules()["baseline"])
	var archetype := FcArchetypes.get_archetype(archetype_key)
	for key in archetype.get("bonus", {}):
		attributes[key] = mini(int(rules()["start_attribute_cap"]), int(attributes.get(key, rules()["baseline"])) + int(archetype["bonus"][key]))
	var spec := {
		"first_name": "", "last_name": "", "position": position, "secondary_position": 0,
		"height_cm": body[0], "weight_kg": body[1], "wingspan_cm": body[2], "handedness": 0, "jersey_number": 0,
		"archetype": archetype_key, "potential": 50, "attributes": attributes, "country": "United States",
		"appearance": {"skin": "tone_3", "hair": "short", "face": "face_1", "facial_hair": "none"}}
	spec["potential"] = potential_cap(spec) - 5
	return spec


## Everything wrong with a build, in plain language (empty = valid). Never throws on bad input.
static func validate(spec: Dictionary, defs: FcDefinitionSet) -> Array[String]:
	var errors: Array[String] = []
	var r := rules()
	var phys: Dictionary = r["physical"]
	for field in ["first_name", "last_name"]:
		var text := str(spec.get(field, "")).strip_edges()
		if text == "":
			errors.append("%s is required" % field.replace("_", " "))
		elif text.length() > int(r["name_max_length"]):
			errors.append("%s can be at most %d letters" % [field.replace("_", " "), int(r["name_max_length"])])
	var country := str(spec.get("country", "")).strip_edges()
	if country.length() < 2 or country.length() > 40:
		errors.append("choose a country (2-40 letters)")
	var position := _int(spec.get("position", 0), 0)
	var secondary := _int(spec.get("secondary_position", 0), 0)
	if not FcPosition.is_valid(position):
		errors.append("choose a position")
	if not FcPosition.is_valid(secondary, true):
		errors.append("the secondary position is not valid")
	elif secondary != 0 and secondary == position:
		errors.append("the secondary position must differ from the position")
	var height := _int(spec.get("height_cm", 0), 0)
	var weight := _int(spec.get("weight_kg", 0), 0)
	var wingspan := _int(spec.get("wingspan_cm", 0), 0)
	if height < int(phys["height_cm"][0]) or height > int(phys["height_cm"][1]):
		errors.append("height must be %d-%d cm" % [int(phys["height_cm"][0]), int(phys["height_cm"][1])])
	if weight < int(phys["weight_kg"][0]) or weight > int(phys["weight_kg"][1]):
		errors.append("weight must be %d-%d kg" % [int(phys["weight_kg"][0]), int(phys["weight_kg"][1])])
	if wingspan < int(phys["wingspan_cm"][0]) or wingspan > int(phys["wingspan_cm"][1]):
		errors.append("wingspan must be %d-%d cm" % [int(phys["wingspan_cm"][0]), int(phys["wingspan_cm"][1])])
	if height > 0 and wingspan > 0:
		var over := wingspan - height
		if over < int(phys["wingspan_over_height_cm"][0]) or over > int(phys["wingspan_over_height_cm"][1]):
			errors.append("wingspan can be %d to +%d cm compared with height" % [int(phys["wingspan_over_height_cm"][0]), int(phys["wingspan_over_height_cm"][1])])
	if height > 0 and weight > 0:
		var bmi := weight / pow(height / 100.0, 2.0)
		if bmi < float(phys["bmi"][0]) or bmi > float(phys["bmi"][1]):
			errors.append("weight does not fit the height (body mass index %.1f, allowed %.0f-%.0f)" % [bmi, float(phys["bmi"][0]), float(phys["bmi"][1])])
	var hand := _int(spec.get("handedness", -1), -1)
	if hand < 0 or hand > 2:
		errors.append("choose a dominant hand")
	var jersey := _int(spec.get("jersey_number", -1), -1)
	if jersey < int(r["jersey_number"][0]) or jersey > int(r["jersey_number"][1]):
		errors.append("jersey number must be %d-%d" % [int(r["jersey_number"][0]), int(r["jersey_number"][1])])
	if FcArchetypes.get_archetype(str(spec.get("archetype", ""))).is_empty():
		errors.append("unknown archetype")
	var potential := _int(spec.get("potential", -1), -1)
	if potential < int(r["potential_min"]) or potential > int(r["potential_max"]):
		errors.append("potential must be %d-%d" % [int(r["potential_min"]), int(r["potential_max"])])
	elif height > 0 and wingspan > 0 and potential > potential_cap(spec):
		errors.append("this body allows a potential of at most %d (you chose %d)" % [potential_cap(spec), potential])
	var attributes = spec.get("attributes", {})
	if not (attributes is Dictionary):
		errors.append("attributes are missing")
	else:
		for key in defs.attributes.keys():
			if not attributes.has(key):
				errors.append("attribute %s is missing" % key)
		for key in attributes:
			if not defs.attributes.has_key(key):
				errors.append("unknown attribute %s" % key)
		for key in defs.attributes.keys():
			if not attributes.has(key):
				continue
			var value := _int(attributes[key], -1)
			if value < int(r["attribute_floor"]) or value > int(r["start_attribute_cap"]):
				errors.append("%s must be %d-%d at the start (it is %d)" % [key, int(r["attribute_floor"]), int(r["start_attribute_cap"]), value])
			elif height > 0 and wingspan > 0 and weight > 0 and value > attribute_ceiling(key, spec):
				errors.append("%s cannot start above %d for this body and potential (it is %d)" % [key, attribute_ceiling(key, spec), value])
		var used := budget_used(attributes)
		if used > int(r["budget_points"]):
			errors.append("you spent %d points above the baseline but only %d are available" % [used, int(r["budget_points"])])
	var look = spec.get("appearance", {})
	if not (look is Dictionary):
		errors.append("appearance is missing")
	else:
		for part in r["appearance"]:
			if not (r["appearance"][part] as Array).has(str(look.get(part, ""))):
				errors.append("choose a %s option" % str(part).replace("_", " "))
	return errors


## Makes the player: validates the build, adds a new FcPlayer to the world (not on any team yet, so he is a free agent
## until Career Mode places him) and returns {"player": FcPlayer, "profile": FcCareerProfile}, or {"errors": [...]}.
## `year` is the first season; the player is 19 years old. The profile id comes from `rng`, so the same seed
## gives the same id.
static func create(world: FcWorld, spec: Dictionary, year: int, rng: FcRng) -> Dictionary:
	var errors := validate(spec, world.definitions)
	if not errors.is_empty():
		return {"errors": errors}
	var p := FcPlayer.new(world.ids.next_id(FcWorld.KIND_PLAYER), world.definitions)
	p.identity.first_name = str(spec["first_name"]).strip_edges()
	p.identity.last_name = str(spec["last_name"]).strip_edges()
	p.identity.birth_date = FcDate.new(year - 19, 3, 15)
	p.identity.country = str(spec["country"]).strip_edges()
	p.primary_position = int(spec["position"])
	p.secondary_position = int(spec["secondary_position"])
	p.physical.height_cm = int(spec["height_cm"])
	p.physical.weight_kg = int(spec["weight_kg"])
	p.physical.wingspan_cm = int(spec["wingspan_cm"])
	p.physical.handedness = int(spec["handedness"])
	p.development.potential = int(spec["potential"])
	p.development.peak_age = 27
	for key in spec["attributes"]:
		p.attributes.set_value(key, int(spec["attributes"][key]))
	var added := world.players.add(p)
	if added != OK:
		return {"errors": ["could not add the player to the world"]}
	var profile := FcCareerProfile.new()
	profile.profile_id = FcCareerProfile.make_profile_id(rng)
	profile.player_id = p.id
	profile.archetype_key = str(spec["archetype"])
	profile.appearance = (spec["appearance"] as Dictionary).duplicate()
	profile.jersey_number = int(spec["jersey_number"])
	profile.build_potential = int(spec["potential"])
	profile.build_version = ruleset_version()
	profile.ruleset_version = ruleset_version()
	return {"player": p, "profile": profile}
