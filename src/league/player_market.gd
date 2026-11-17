class_name FcPlayerMarket
extends RefCounted
## How teams value players and what a player asks for: used by re-signing,
## free agency and the draft. Pure functions of a player and a salary scale.
##
## value(): current ability, plus part of the room to grow for young players,
## minus a penalty for age over 30.
## asking_salary(): follows value on a curve from the league minimum to the
## league maximum, like the contracts of a generated league.

var ratings: FcPlayerRatings


func _init(rating_calculator: FcPlayerRatings) -> void:
	ratings = rating_calculator


func value(player: FcPlayer, age: int) -> float:
	var overall := ratings.overall(player)
	var v := overall
	if age <= 26:
		v += 0.45 * maxf(0.0, player.development.potential - overall)
	if age > 30:
		v -= (age - 30) * 1.6
	return v


## Yearly salary (whole dollars, rounded to $10,000) a player of this value asks for.
static func salary_for_value(value: float, cap: FcCapRules) -> int:
	var t := pow(clampf((value - 35.0) / 55.0, 0.0, 1.0), 2.2)
	var raw := lerpf(float(cap.min_player_salary), float(cap.max_player_salary), t)
	return clampi(roundi(raw / 10000.0) * 10000, cap.min_player_salary, cap.max_player_salary)


func asking_salary(player: FcPlayer, age: int, cap: FcCapRules) -> int:
	return salary_for_value(value(player, age), cap)


## Contract length (years) a player wants: long for young talents, short for veterans.
func desired_years(age: int, cap: FcCapRules) -> int:
	return clampi(roundi(5.0 - (age - 26) * 0.5), 1, cap.max_contract_years)


## Players are a little flexible: they accept a salary somewhat below their asking
## price (BASE_FLEXIBILITY), more so when re-signing with a team they are loyal to,
## and they like longer security (SECURITY_PER_YEAR less per year above the length
## they want, more per year below it).
const BASE_FLEXIBILITY := 0.06
const SECURITY_PER_YEAR := 0.025
## A general manager's negotiation skill (0-100, 50 is average) moves the salary a player accepts by up to
## this much of his asking price either way (a great negotiator gets a 5% discount, a poor one pays 5% more).
const NEGOTIATION_EFFECT := 0.05


## The least first-year salary this player accepts for a contract of `years`.
## `own_team` is true when he is re-signing with his current team.
func minimum_acceptable(player: FcPlayer, age: int, cap: FcCapRules, years: int, own_team: bool, negotiation: float = 50.0) -> int:
	var ask := asking_salary(player, age, cap)
	var flex := BASE_FLEXIBILITY + NEGOTIATION_EFFECT * (negotiation - 50.0) / 50.0
	if own_team:
		flex += 0.03 + (player.personality.get_value("loyalty") - 50.0) / 1000.0
	var year_factor := 1.0 - SECURITY_PER_YEAR * clampi(years - desired_years(age, cap), -2, 3)
	return maxi(cap.min_player_salary, int(ceil(ask * (1.0 - flex) * year_factor / 10000.0)) * 10000)


## Would he accept this offer? {"accepted": bool, "required": int}. A near-minimum
## player also accepts the minimum salary (the minimum-contract exception).
func evaluate_offer(player: FcPlayer, age: int, cap: FcCapRules, salary: int, years: int, own_team: bool, negotiation: float = 50.0) -> Dictionary:
	var required := minimum_acceptable(player, age, cap, years, own_team, negotiation)
	var ask := asking_salary(player, age, cap)
	var accepted := salary >= required or (salary == cap.min_player_salary and ask <= int(cap.min_player_salary * 1.35))
	return {"accepted": accepted, "required": required}


## A new contract: `years` seasons from `first_season`, 4% raises, no options.
static func make_contract(contract_id: int, player_id: int, team_id: int, first_season: int,
		years: int, first_salary: int, cap: FcCapRules, signed_on: FcDate) -> FcContract:
	var c := FcContract.new(contract_id)
	c.player_id = player_id
	c.team_id = team_id
	c.signed_on = signed_on
	for i in years:
		var salary := clampi(roundi(first_salary * pow(1.04, i) / 10000.0) * 10000, cap.min_player_salary, cap.max_player_salary)
		c.years.append(FcContractYear.new(first_season + i, salary))
	return c
