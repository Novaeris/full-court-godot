class_name FcLeagueRules
extends RefCounted
## All the rules of one league, as a saved entity linked to it by league_id:
##   season   (FcSeasonRules)   games per opponent by distance
##   playoffs (FcPlayoffRules)  qualification, bracket, series lengths
##   cap      (FcCapRules)      salary cap, tax, hard limit, contract limits
##   draft    (FcDraftRules)    draft lottery
##   roster_min / roster_max    players a team must / may carry
## Different leagues can have different rules. The structure (conferences,
## divisions) stays in FcLeague.

const SCHEMA_VERSION := 1

var id: int
var league_id: int = 0
var season := FcSeasonRules.new()
var playoffs := FcPlayoffRules.new()
var cap := FcCapRules.new()
var draft := FcDraftRules.new()
var roster_min: int = 13
var roster_max: int = 15
## Revenue sharing between markets as a percent of the standard amount (100 = the standard,
## 0 = none; see FcFinanceEngine). Voted on at the owners' meeting. Older saves have 100.
var revenue_sharing_percent: int = 100
## Playing style of the games (see data/simulation/eras.json).
var sim_era: String = "mid_2010s"


func _init(rules_id: int = 0) -> void:
	id = rules_id


## Everything wrong with these rules for this league (empty = fine).
func validate(league: FcLeague) -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("rules id must be positive")
	if league_id <= 0:
		errors.append("rules need a league")
	if roster_min < 5 or roster_max > 30 or roster_min > roster_max:
		errors.append("roster limits must satisfy 5 <= min <= max <= 30")
	if revenue_sharing_percent < 0 or revenue_sharing_percent > 300:
		errors.append("revenue sharing must be 0-300 percent of the standard")
	if not FcGameSimulator.era_keys().has(sim_era):
		errors.append("unknown game era '%s'" % sim_era)
	errors.append_array(cap.validate())
	errors.append_array(draft.validate())
	errors.append_array(season.validate(league))
	errors.append_array(playoffs.validate(league))
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION, "id": id, "league_id": league_id,
		"season": season.to_dict(), "playoffs": playoffs.to_dict(), "cap": cap.to_dict(), "draft": draft.to_dict(),
		"roster_min": roster_min, "roster_max": roster_max, "sim_era": sim_era,
		"revenue_sharing_percent": revenue_sharing_percent,
	}


static func from_dict(data: Dictionary) -> FcLeagueRules:
	var r := FcLeagueRules.new(int(data.get("id", 0)))
	r.league_id = int(data.get("league_id", 0))
	r.season = FcSeasonRules.from_dict(data.get("season", {}))
	r.playoffs = FcPlayoffRules.from_dict(data.get("playoffs", {}))
	r.cap = FcCapRules.from_dict(data.get("cap", {}))
	r.draft = FcDraftRules.from_dict(data.get("draft", {}))   # missing in old saves = no lottery
	r.roster_min = int(data.get("roster_min", r.roster_min))
	r.roster_max = int(data.get("roster_max", r.roster_max))
	r.sim_era = str(data.get("sim_era", r.sim_era))
	r.revenue_sharing_percent = int(data.get("revenue_sharing_percent", 100))
	return r
