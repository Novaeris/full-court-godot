class_name FcGenerationConfig
extends RefCounted
## Everything a user can customize about a new league: name, size, where the
## teams are from, team names, how it is divided, the league RULES (schedule,
## playoffs, salary cap) and roster/staff sizes. Defaults come from
## data/generation/config.json; a "new league" screen will edit these fields.
## validate() returns plain-language problems to show next to the option at fault.
##
## CHOOSING TEAMS (two ways):
##   1. Automatic: set `areas` (e.g. ["europe"], or several; empty = anywhere)
##      and `team_count`; cities are picked by `selection_mode` ("weighted" =
##      random, favoring bigger cities; "largest" = the biggest cities).
##   2. Exact: set `city_keys` (team_count is then the length of that list).
##
## TEAM NAMES: by default each team gets a generated nickname. Set
## `team_nicknames` (city key -> nickname) and/or `team_abbreviations`
## (city key -> 2-4 letters) to choose your own; anything not set is generated.
##
## SIZE AND STRUCTURE: 4-64 teams at creation. The team count must divide
## evenly into conferences x divisions with 3-8 teams per division (see
## FcLeagueStructure). Saves can grow later (expansion).
##
## RULES: the schedule (games vs division / conference / other-conference
## opponents), playoff format and series lengths, and salary-cap preset are
## chosen here. With `auto_season` / `auto_playoffs` true they are
## picked to suit the league size; set them false to use your own values.

const MAX_TEAM_NAME_LENGTH := 24
const SELECTION_MODES := ["weighted", "largest"]

var league_name: String = "Full Court League"
var areas: Array[String] = ["north_america"]
var city_keys: Array[String] = []
var selection_mode: String = "weighted"
var team_nicknames: Dictionary = {}
var team_abbreviations: Dictionary = {}
var team_count: int = 30
var conference_count: int = 2
var divisions_per_conference: int = 3

var start_season: int = 2026
var roster_size: int = 15
var roster_min: int = 13
var roster_max: int = 15
var free_agent_count: int = 60
## Unemployed staff per role (general manager, head coach, assistant, scout, medical, business
## executive) who can be hired at the start.
var free_staff_per_role: int = 3
var assistant_coaches: int = 3
var scouts: int = 3
var medical_staff: int = 1
var business_executives: int = 1
## Chance that a player comes from the team's own country; otherwise his
## nationality is drawn from all countries by basketball talent weight.
var home_country_share: float = 0.65
var min_contract_years: int = 1
var max_contract_years: int = 4
## Ability level of the best / worst roster slot on an average team.
var top_player_level: float = 74.0
var bottom_player_level: float = 38.0
## Spread of overall team strength.
var team_strength_sd: float = 4.0
## Spread of individual player quality around his roster slot's level.
var player_level_sd: float = 5.0

## Salary rules: a preset from data/rules/cap_presets.json and the cap size.
## Playing style of the games: "early_2010s", "mid_2010s" or "late_2010s".
var sim_era: String = "mid_2010s"
var cap_preset: String = "soft_cap_with_hard_limit"
var salary_cap: int = 140000000

var auto_season: bool = true
var target_games: int = 80
var games_per_division_opponent: int = 3
var games_per_conference_opponent: int = 2
var games_per_other_conference_opponent: int = 1

var auto_playoffs: bool = true
var playoff_qualification: String = "division_leaders"
var playoff_bracket: String = "conference"
var playoff_team_count: int = 16
var playoff_series: Array[int] = [5, 7, 7, 7]

## Draft lottery: on = FcDraftRules.suggest for the league size; off = worst record picks first.
var draft_lottery: bool = true


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
	c.team_abbreviations = d.get("team_abbreviations", {}).duplicate()
	c.team_count = int(d.get("team_count", c.team_count))
	c.conference_count = int(d.get("conference_count", c.conference_count))
	c.divisions_per_conference = int(d.get("divisions_per_conference", c.divisions_per_conference))
	c.start_season = int(d.get("start_season", c.start_season))
	c.roster_size = int(d.get("roster_size", c.roster_size))
	c.roster_min = int(d.get("roster_min", c.roster_min))
	c.roster_max = int(d.get("roster_max", c.roster_max))
	c.free_agent_count = int(d.get("free_agent_count", c.free_agent_count))
	c.free_staff_per_role = int(d.get("free_staff_per_role", c.free_staff_per_role))
	c.assistant_coaches = int(d.get("assistant_coaches", c.assistant_coaches))
	c.scouts = int(d.get("scouts", c.scouts))
	c.medical_staff = int(d.get("medical_staff", c.medical_staff))
	c.business_executives = int(d.get("business_executives", c.business_executives))
	c.home_country_share = float(d.get("home_country_share", c.home_country_share))
	c.min_contract_years = int(d.get("min_contract_years", c.min_contract_years))
	c.max_contract_years = int(d.get("max_contract_years", c.max_contract_years))
	c.top_player_level = float(d.get("top_player_level", c.top_player_level))
	c.bottom_player_level = float(d.get("bottom_player_level", c.bottom_player_level))
	c.team_strength_sd = float(d.get("team_strength_sd", c.team_strength_sd))
	c.player_level_sd = float(d.get("player_level_sd", c.player_level_sd))
	c.sim_era = str(d.get("sim_era", c.sim_era))
	c.cap_preset = str(d.get("cap_preset", c.cap_preset))
	c.salary_cap = int(d.get("salary_cap", c.salary_cap))
	c.auto_season = bool(d.get("auto_season", c.auto_season))
	c.target_games = int(d.get("target_games", c.target_games))
	c.games_per_division_opponent = int(d.get("games_per_division_opponent", c.games_per_division_opponent))
	c.games_per_conference_opponent = int(d.get("games_per_conference_opponent", c.games_per_conference_opponent))
	c.games_per_other_conference_opponent = int(d.get("games_per_other_conference_opponent", c.games_per_other_conference_opponent))
	c.auto_playoffs = bool(d.get("auto_playoffs", c.auto_playoffs))
	c.playoff_qualification = str(d.get("playoff_qualification", c.playoff_qualification))
	c.playoff_bracket = str(d.get("playoff_bracket", c.playoff_bracket))
	c.playoff_team_count = int(d.get("playoff_team_count", c.playoff_team_count))
	c.draft_lottery = bool(d.get("draft_lottery", c.draft_lottery))
	c.playoff_series = []
	for s in d.get("playoff_series", [5, 7, 7, 7]):
		c.playoff_series.append(int(s))
	return c


static func _strings(source) -> Array[String]:
	var out: Array[String] = []
	for s in source:
		out.append(str(s))
	return out


## The rules this config produces for `league` (the real league when
## generating, or a stand-in of the right shape when validating).
## Returns null if the cap preset does not exist.
func build_rules(league: FcLeague) -> FcLeagueRules:
	var cap := FcCapRules.from_preset(cap_preset, salary_cap, FcCapRules.load_presets())
	if cap == null:
		return null
	var r := FcLeagueRules.new(1)
	r.league_id = league.id
	r.cap = cap
	r.cap.max_contract_years = maxi(r.cap.max_contract_years, max_contract_years)
	r.roster_min = roster_min
	r.roster_max = roster_max
	r.sim_era = sim_era
	if draft_lottery:
		r.draft = FcDraftRules.suggest(league.all_team_ids().size())
	if auto_season:
		r.season = FcSeasonRules.suggest(league, target_games)
	else:
		r.season.games_per_division_opponent = games_per_division_opponent
		r.season.games_per_conference_opponent = games_per_conference_opponent
		r.season.games_per_other_conference_opponent = games_per_other_conference_opponent
	if auto_playoffs:
		r.playoffs = FcPlayoffRules.suggest(league)
	else:
		r.playoffs.qualification = playoff_qualification
		r.playoffs.bracket = playoff_bracket
		r.playoffs.team_count = playoff_team_count
		r.playoffs.series_lengths = playoff_series.duplicate()
	return r


## Problems that would prevent generating this league. Empty = OK.
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

	# --- which cities
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

	# --- size and structure
	var structure_ok := true
	if n < FcLeagueStructure.MIN_TEAMS:
		errors.append("a league needs at least %d teams" % FcLeagueStructure.MIN_TEAMS)
		structure_ok = false
	elif n > FcLeagueStructure.MAX_TEAMS_AT_CREATION:
		errors.append("a new league can have at most %d teams (more can be added later by expansion)" % FcLeagueStructure.MAX_TEAMS_AT_CREATION)
		structure_ok = false
	elif n > nickname_count:
		errors.append("team count %d exceeds the %d available team nicknames" % [n, nickname_count])
		structure_ok = false
	elif conference_count < 1 or divisions_per_conference < 1:
		errors.append("conference and division counts must be at least 1")
		structure_ok = false
	elif FcLeagueStructure.valid_structures(n).is_empty():
		errors.append("%d teams cannot be split into even divisions of %d-%d teams. Nearby team counts that work: %s" % [
			n, FcLeagueStructure.MIN_DIVISION_SIZE, FcLeagueStructure.MAX_DIVISION_SIZE,
			", ".join(FcLeagueStructure.nearest_valid_counts(n).map(func(x): return str(x)))])
		structure_ok = false
	elif not FcLeagueStructure.is_valid(n, conference_count, divisions_per_conference):
		errors.append("%d teams cannot be split into %d conferences x %d divisions with even divisions of %d-%d teams. Options: %s" % [
			n, conference_count, divisions_per_conference,
			FcLeagueStructure.MIN_DIVISION_SIZE, FcLeagueStructure.MAX_DIVISION_SIZE,
			FcLeagueStructure.describe_options(n)])
		structure_ok = false

	# --- team names
	var used_names := {}
	for key in team_nicknames:
		var nick := str(team_nicknames[key]).strip_edges()
		if nick.is_empty():
			errors.append("the nickname for '%s' is empty" % key)
		elif nick.length() > MAX_TEAM_NAME_LENGTH:
			errors.append("the nickname '%s' is longer than %d characters" % [nick, MAX_TEAM_NAME_LENGTH])
		elif used_names.has(nick.to_lower()):
			errors.append("the nickname '%s' is used by two teams" % nick)
		used_names[nick.to_lower()] = true
	var used_abbreviations := {}
	for key in team_abbreviations:
		var abbr := str(team_abbreviations[key])
		if not FcChecks.is_abbreviation(abbr):
			errors.append("the abbreviation '%s' must be 2-4 capital letters" % abbr)
		elif used_abbreviations.has(abbr):
			errors.append("the abbreviation '%s' is used by two teams" % abbr)
		used_abbreviations[abbr] = true

	# --- rules, checked against a stand-in league of the right shape
	if cap_preset != "" and FcCapRules.from_preset(cap_preset, salary_cap, FcCapRules.load_presets()) == null:
		errors.append("unknown salary cap preset '%s'" % cap_preset)
	elif structure_ok:
		var stand_in := FcLeague.make_even(1, league_name, conference_count, divisions_per_conference, n)
		var rules := build_rules(stand_in)
		errors.append_array(rules.validate(stand_in))
		if roster_size < rules.roster_min or roster_size > rules.roster_max:
			errors.append("roster_size must be between the league roster limits (%d-%d)" % [rules.roster_min, rules.roster_max])
		if max_contract_years > rules.cap.max_contract_years or min_contract_years < 1 or min_contract_years > max_contract_years:
			errors.append("contract lengths must be within 1-%d years" % rules.cap.max_contract_years)

	if free_agent_count < 0:
		errors.append("free_agent_count cannot be negative")
	if assistant_coaches < 0 or scouts < 0 or medical_staff < 0 or business_executives < 0:
		errors.append("staff counts cannot be negative")
	if home_country_share < 0.0 or home_country_share > 1.0:
		errors.append("home_country_share must be 0-1")
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
