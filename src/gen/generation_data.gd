class_name FcGenerationData
extends RefCounted
## The raw content used by procedural generation, loaded from
## data/generation/*.json: name pools, fictional cities/nicknames/colors,
## position profiles, staff profiles. Edit those files to change what the
## generators produce. validate() checks the files are complete and consistent.

const DIR := "res://data/generation/"
const POSITION_KEYS := ["PG", "SG", "SF", "PF", "C"]
const STAFF_ROLE_KEYS := ["general_manager", "head_coach", "assistant_coach", "scout", "medical", "business_executive"]

var names: Dictionary = {}
var world: Dictionary = {}
var positions: Dictionary = {}
var staff: Dictionary = {}
var config: Dictionary = {}
var load_errors: Array[String] = []


static func load_default() -> FcGenerationData:
	var d := FcGenerationData.new()
	d.names = d._load("names.json")
	d.world = d._load("world.json")
	d.positions = d._load("position_profiles.json")
	d.staff = d._load("staff_profiles.json")
	d.config = d._load("config.json")
	return d


func _load(file_name: String) -> Dictionary:
	var file := FileAccess.open(DIR + file_name, FileAccess.READ)
	if file == null:
		load_errors.append("cannot open %s%s" % [DIR, file_name])
		return {}
	var parsed = FcChecks.parse_json(file.get_as_text())
	if not (parsed is Dictionary):
		load_errors.append("%s is not a valid JSON object" % file_name)
		return {}
	return parsed


func validate() -> Array[String]:
	var errors: Array[String] = load_errors.duplicate()
	_check_names(errors)
	_check_world(errors)
	_check_positions(errors)
	_check_staff(errors)
	return errors


func _check_names(errors: Array[String]) -> void:
	var pools: Dictionary = names.get("pools", {})
	var countries: Dictionary = names.get("countries", {})
	if pools.is_empty():
		errors.append("names: no pools")
	for key in pools:
		for part in ["first", "last"]:
			var list = pools[key].get(part, [])
			if not (list is Array) or list.size() < 5:
				errors.append("names: pool '%s' needs at least 5 '%s' names" % [key, part])
	if countries.is_empty():
		errors.append("names: no countries")
	for ckey in countries:
		var weights: Dictionary = countries[ckey].get("pools", {})
		if weights.is_empty():
			errors.append("names: country '%s' has no pools" % ckey)
		for pkey in weights:
			if not pools.has(pkey):
				errors.append("names: country '%s' uses unknown pool '%s'" % [ckey, pkey])
			if float(weights[pkey]) <= 0.0:
				errors.append("names: country '%s' pool '%s' needs a positive weight" % [ckey, pkey])
	var areas: Dictionary = world.get("areas", {})
	for ckey in countries:
		if not areas.has(str(countries[ckey].get("area", ""))):
			errors.append("names: country '%s' has an unknown area" % ckey)
		if float(countries[ckey].get("talent_weight", 0.0)) <= 0.0:
			errors.append("names: country '%s' needs a positive talent_weight" % ckey)
		if FcChecks.is_blank(str(countries[ckey].get("name", ""))):
			errors.append("names: country '%s' needs a name" % ckey)
	if not countries.has(str(names.get("fallback_country", ""))):
		errors.append("names: fallback_country is not a listed country")


func _check_world(errors: Array[String]) -> void:
	var cities: Array = world.get("cities", [])
	if cities.is_empty():
		errors.append("world: no cities")
	var areas: Dictionary = world.get("areas", {})
	if areas.is_empty():
		errors.append("world: no areas")
	var countries: Dictionary = names.get("countries", {})
	var seen := {}
	var seen_keys := {}
	for c in cities:
		var n := str(c.get("name", ""))
		var key := str(c.get("key", ""))
		if FcChecks.is_blank(n):
			errors.append("world: a city has no name")
		if not FcChecks.is_snake_key(key):
			errors.append("world: city '%s' needs a snake_case key" % n)
		if seen_keys.has(key):
			errors.append("world: duplicate city key '%s'" % key)
		seen_keys[key] = true
		if seen.has(n):
			errors.append("world: duplicate city '%s'" % n)
		seen[n] = true
		if FcChecks.is_blank(str(c.get("region", ""))):
			errors.append("world: city '%s' has no region" % n)
		if not areas.has(str(c.get("area", ""))):
			errors.append("world: city '%s' has an unknown area" % n)
		if not countries.has(str(c.get("country", ""))):
			errors.append("world: city '%s' has an unknown country" % n)
		elif areas.has(str(c.get("area", ""))) and countries[str(c["country"])].get("area", "") != c.get("area", ""):
			errors.append("world: city '%s' area differs from its country's area" % n)
		var lat := float(c.get("lat", 999.0))
		var lon := float(c.get("lon", 999.0))
		if lat < -90.0 or lat > 90.0 or lon < -180.0 or lon > 180.0:
			errors.append("world: city '%s' has bad coordinates" % n)
		if int(c.get("population", 0)) < 1000:
			errors.append("world: city '%s' population too small" % n)
		var econ := int(c.get("economy", -1))
		if econ < 0 or econ > 100:
			errors.append("world: city '%s' economy must be 0-100" % n)
	var nick_seen := {}
	for nick in world.get("nicknames", []):
		if nick_seen.has(nick):
			errors.append("world: duplicate nickname '%s'" % nick)
		nick_seen[nick] = true
	if nick_seen.is_empty():
		errors.append("world: no nicknames")
	var schemes: Array = world.get("color_schemes", [])
	if schemes.is_empty():
		errors.append("world: no color schemes")
	for s in schemes:
		if not (s is Array) or s.size() != 3:
			errors.append("world: a color scheme needs 3 colors")
			continue
		for col in s:
			if not FcChecks.is_hex_color(str(col)):
				errors.append("world: bad color '%s'" % str(col))
	if world.get("arena_patterns", []).is_empty():
		errors.append("world: no arena patterns")
	if world.get("landmarks", []).is_empty():
		errors.append("world: no landmarks")


func _check_positions(errors: Array[String]) -> void:
	var p: Dictionary = positions.get("positions", {})
	for key in POSITION_KEYS:
		if not p.has(key):
			errors.append("positions: missing '%s'" % key)
			continue
		for field in ["height_mean", "height_sd", "bmi_mean"]:
			if not p[key].has(field):
				errors.append("positions: '%s' missing %s" % [key, field])
		if not (p[key].get("offsets", null) is Dictionary):
			errors.append("positions: '%s' needs offsets" % key)
		if not (p[key].get("tendency_offsets", null) is Dictionary):
			errors.append("positions: '%s' needs tendency_offsets" % key)


func _check_staff(errors: Array[String]) -> void:
	var roles: Dictionary = staff.get("roles", {})
	for key in STAFF_ROLE_KEYS:
		if not roles.has(key):
			errors.append("staff: missing role '%s'" % key)
			continue
		var r: Dictionary = roles[key]
		if int(r.get("age_min", 0)) >= int(r.get("age_max", 0)):
			errors.append("staff: role '%s' age_min must be below age_max" % key)
		if int(r.get("salary_min", 0)) > int(r.get("salary_max", 0)) or int(r.get("salary_min", -1)) < 0:
			errors.append("staff: role '%s' has bad salary range" % key)
