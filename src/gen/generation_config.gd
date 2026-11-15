class_name FcGenerationConfig
extends RefCounted
## Size and shape of a generated league. Defaults come from
## data/generation/config.json; tests and future "new game" options can
## override individual fields. Salary limits here are generation guides, not
## league rules (the salary cap will be a league-rules system).

var start_season: int = 2026
var team_count: int = 30
var roster_size: int = 15
var free_agent_count: int = 60
var assistant_coaches: int = 3
var scouts: int = 3
var medical_staff: int = 1
var business_executives: int = 1
## Share of players born outside the home country.
var international_share: float = 0.2
var min_salary: int = 1100000
var max_salary: int = 50000000
var min_contract_years: int = 1
var max_contract_years: int = 4
## Ability level of the best / worst roster slot on an average team.
var top_player_level: float = 74.0
var bottom_player_level: float = 38.0
## Spread of overall team strength.
var team_strength_sd: float = 4.0


static func load_default(data: FcGenerationData) -> FcGenerationConfig:
	var c := FcGenerationConfig.new()
	var d := data.config
	c.start_season = int(d.get("start_season", c.start_season))
	c.team_count = int(d.get("team_count", c.team_count))
	c.roster_size = int(d.get("roster_size", c.roster_size))
	c.free_agent_count = int(d.get("free_agent_count", c.free_agent_count))
	c.assistant_coaches = int(d.get("assistant_coaches", c.assistant_coaches))
	c.scouts = int(d.get("scouts", c.scouts))
	c.medical_staff = int(d.get("medical_staff", c.medical_staff))
	c.business_executives = int(d.get("business_executives", c.business_executives))
	c.international_share = float(d.get("international_share", c.international_share))
	c.min_salary = int(d.get("min_salary", c.min_salary))
	c.max_salary = int(d.get("max_salary", c.max_salary))
	c.min_contract_years = int(d.get("min_contract_years", c.min_contract_years))
	c.max_contract_years = int(d.get("max_contract_years", c.max_contract_years))
	c.top_player_level = float(d.get("top_player_level", c.top_player_level))
	c.bottom_player_level = float(d.get("bottom_player_level", c.bottom_player_level))
	c.team_strength_sd = float(d.get("team_strength_sd", c.team_strength_sd))
	return c


func validate(data: FcGenerationData) -> Array[String]:
	var errors: Array[String] = []
	var city_count: int = data.world.get("cities", []).size()
	var nickname_count: int = data.world.get("nicknames", []).size()
	if team_count < 2:
		errors.append("team_count must be at least 2")
	if team_count > city_count:
		errors.append("team_count %d exceeds the %d available cities" % [team_count, city_count])
	if team_count > nickname_count:
		errors.append("team_count %d exceeds the %d available nicknames" % [team_count, nickname_count])
	if roster_size < 5 or roster_size > 30:
		errors.append("roster_size must be 5-30")
	if free_agent_count < 0:
		errors.append("free_agent_count cannot be negative")
	if assistant_coaches < 0 or scouts < 0 or medical_staff < 0 or business_executives < 0:
		errors.append("staff counts cannot be negative")
	if international_share < 0.0 or international_share > 1.0:
		errors.append("international_share must be 0-1")
	if min_salary < 0 or max_salary < min_salary:
		errors.append("salary range is invalid")
	if min_contract_years < 1 or max_contract_years < min_contract_years:
		errors.append("contract year range is invalid")
	if bottom_player_level < 0.0 or top_player_level > 100.0 or bottom_player_level > top_player_level:
		errors.append("player level range is invalid")
	if team_strength_sd < 0.0:
		errors.append("team_strength_sd cannot be negative")
	return errors
