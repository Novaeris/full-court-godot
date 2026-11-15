class_name FcGenerationConfig
extends RefCounted
## Everything a user can customize about a generated league: its name, size,
## where its teams are from, how it is divided into conferences and divisions,
## roster and staff sizes. Defaults come from data/generation/config.json;
## a "new league" screen will edit these fields.
##
## CHOOSING TEAMS (two ways):
##   1. Automatic: set `areas` (e.g. ["europe"], or ["north_america","europe"];
##      empty = anywhere) and `team_count`; cities are picked from those areas
##      by `selection_mode` ("weighted" = random, favoring bigger cities;
##      "largest" = the biggest cities).
##   2. Exact: set `city_keys` to the cities you want (team_count is then the
##      length of that list and `areas` is ignored).
## Salary limits are generation guides, not league rules (the salary cap will
## be a league-rules system).

const SELECTION_MODES := ["weighted", "largest"]
## Smallest allowed division, so every team has division rivals.
const MIN_TEAMS_PER_DIVISION := 2

var league_name: String = "Full Court League"
var areas: Array[String] = ["north_america"]
var city_keys: Array[String] = []
var selection_mode: String = "weighted"
## Optional custom nicknames: city key -> nickname.
var team_nicknames: Dictionary = {}
var team_count: int = 30
var conference_count: int = 2
var divisions_per_conference: int = 3

var start_season: int = 2026
var roster_size: int = 15
var free_agent_count: int = 60
var assistant_coaches: int = 3
var scouts: int = 3
var medical_staff: int = 1
var business_executives: int = 1
## Chance that a player comes from the team's own country; otherwise his
## nationality is drawn from all countries by basketball talent weight.
var home_country_share: float = 0.55
var min_salary: int = 1100000
var max_salary: int = 50000000
var min_contract_years: int = 1
var max_contract_years: int = 4
## Ability level of the best / worst roster slot on an average team.
var top_player_level: float = 74.0
var bottom_player_level: float = 38.0
## Spread of overall team strength.
var team_strength_sd: float = 4.0


## Number of teams the league will have.
func effective_team_count() -> int:
	return city_keys.size() if not city_keys.is_empty() else team_count


static func load_default(data: FcGenerationData) -> FcGenerationConfig:
	var c := FcGenerationConfig.new()
	var d := data.config
	c.league_name = str(d.get("league_name", c.league_name))
	c.areas = _strings(d.get("areas", c.areas))
	c.city_keys = _strings(d.get("city_keys", []))
	c.selection_mode = str(d.get("selection_mode", c.selection_mode))
	c.team_nicknames = d.get("team_nicknames", {}).duplicate()
	c.team_count = int(d.get("team_count", c.team_count))
	c.conference_count = int(d.get("conference_count", c.conference_count))
	c.divisions_per_conference = int(d.get("divisions_per_conference", c.divisions_per_conference))
	c.start_season = int(d.get("start_season", c.start_season))
	c.roster_size = int(d.get("roster_size", c.roster_size))
	c.free_agent_count = int(d.get("free_agent_count", c.free_agent_count))
	c.assistant_coaches = int(d.get("assistant_coaches", c.assistant_coaches))
	c.scouts = int(d.get("scouts", c.scouts))
	c.medical_staff = int(d.get("medical_staff", c.medical_staff))
	c.business_executives = int(d.get("business_executives", c.business_executives))
	c.home_country_share = float(d.get("home_country_share", c.home_country_share))
	c.min_salary = int(d.get("min_salary", c.min_salary))
	c.max_salary = int(d.get("max_salary", c.max_salary))
	c.min_contract_years = int(d.get("min_contract_years", c.min_contract_years))
	c.max_contract_years = int(d.get("max_contract_years", c.max_contract_years))
	c.top_player_level = float(d.get("top_player_level", c.top_player_level))
	c.bottom_player_level = float(d.get("bottom_player_level", c.bottom_player_level))
	c.team_strength_sd = float(d.get("team_strength_sd", c.team_strength_sd))
	return c


static func _strings(source) -> Array[String]:
	var out: Array[String] = []
	for s in source:
		out.append(str(s))
	return out


## Problems that would prevent generating this league. Empty = OK.
## A UI should call this and show the messages next to the option at fault.
func validate(data: FcGenerationData) -> Array[String]:
	var errors: Array[String] = []
	var catalog := _city_index(data)
	var area_names: Dictionary = data.world.get("areas", {})
	var nickname_count: int = data.world.get("nicknames", []).size()
	var n := effective_team_count()

	if FcChecks.is_blank(league_name):
		errors.append("league needs a name")
	if not SELECTION_MODES.has(selection_mode):
		errors.append("selection_mode must be one of %s" % str(SELECTION_MODES))

	if city_keys.is_empty():
		for a in areas:
			if not area_names.has(a):
				errors.append("unknown area '%s'" % a)
		var available := 0
		for key in catalog:
			if areas.is_empty() or areas.has(catalog[key].get("area", "")):
				available += 1
		if team_count > available:
			errors.append("team_count %d exceeds the %d cities available in the chosen areas" % [team_count, available])
	else:
		var seen := {}
		for key in city_keys:
			if not catalog.has(key):
				errors.append("unknown city '%s'" % key)
			if seen.has(key):
				errors.append("city '%s' is listed twice" % key)
			seen[key] = true

	if n < 2:
		errors.append("a league needs at least 2 teams")
	if n > nickname_count:
		errors.append("team count %d exceeds the %d available team nicknames" % [n, nickname_count])
	if conference_count < 1 or divisions_per_conference < 1:
		errors.append("conference and division counts must be at least 1")
	elif n < conference_count * divisions_per_conference * MIN_TEAMS_PER_DIVISION:
		errors.append("%d teams cannot fill %d conferences x %d divisions with at least %d teams each" % [
			n, conference_count, divisions_per_conference, MIN_TEAMS_PER_DIVISION])

	if roster_size < 5 or roster_size > 30:
		errors.append("roster_size must be 5-30")
	if free_agent_count < 0:
		errors.append("free_agent_count cannot be negative")
	if assistant_coaches < 0 or scouts < 0 or medical_staff < 0 or business_executives < 0:
		errors.append("staff counts cannot be negative")
	if home_country_share < 0.0 or home_country_share > 1.0:
		errors.append("home_country_share must be 0-1")
	if min_salary < 0 or max_salary < min_salary:
		errors.append("salary range is invalid")
	if min_contract_years < 1 or max_contract_years < min_contract_years:
		errors.append("contract year range is invalid")
	if bottom_player_level < 0.0 or top_player_level > 100.0 or bottom_player_level > top_player_level:
		errors.append("player level range is invalid")
	if team_strength_sd < 0.0:
		errors.append("team_strength_sd cannot be negative")
	return errors


## City dictionaries from the data, by key.
static func _city_index(data: FcGenerationData) -> Dictionary:
	var index := {}
	for c in data.world.get("cities", []):
		index[str(c.get("key", ""))] = c
	return index
