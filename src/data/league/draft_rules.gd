class_name FcDraftRules
extends RefCounted
## How the draft order is decided.
##   lottery_teams  how many of the worst non-playoff teams enter the lottery (0 = no lottery:
##                  the worst record always picks first)
##   lottery_picks  how many of the first picks are drawn by lottery; everyone else
##                  keeps their record order after those
##   odds_power     how strongly the odds favor bad teams (weight = places_from_best ^ power;
##                  higher = the worst teams are more likely to win)
## The leagues' "no lottery" setting (lottery_teams = 0) is also what saves made before
## this rule existed use, so old saves play out as before.

const MAX_LOTTERY_TEAMS := 20
var lottery_teams: int = 0
var lottery_picks: int = 4
var odds_power: float = 1.3


## A sensible lottery for a league of this many teams: about 45% of teams enter
## (at least 3), up to 4 picks drawn.
static func suggest(team_count: int) -> FcDraftRules:
	var r := FcDraftRules.new()
	r.lottery_teams = clampi(roundi(team_count * 0.45), 3, MAX_LOTTERY_TEAMS)
	r.lottery_picks = clampi(roundi(team_count / 8.0), 1, 4)
	return r


func validate() -> Array[String]:
	var errors: Array[String] = []
	if lottery_teams < 0 or lottery_teams > MAX_LOTTERY_TEAMS:
		errors.append("lottery teams must be 0-%d" % MAX_LOTTERY_TEAMS)
	if lottery_teams > 0 and (lottery_picks < 1 or lottery_picks > lottery_teams):
		errors.append("lottery picks must be between 1 and the number of lottery teams")
	if odds_power < 0.0 or odds_power > 4.0:
		errors.append("odds power must be 0-4")
	return errors


func to_dict() -> Dictionary:
	return {"lottery_teams": lottery_teams, "lottery_picks": lottery_picks, "odds_power": FcChecks.quantize(odds_power)}


static func from_dict(data: Dictionary) -> FcDraftRules:
	var r := FcDraftRules.new()
	r.lottery_teams = int(data.get("lottery_teams", 0))
	r.lottery_picks = int(data.get("lottery_picks", r.lottery_picks))
	r.odds_power = float(data.get("odds_power", r.odds_power))
	return r
