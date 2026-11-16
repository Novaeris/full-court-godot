class_name FcTradeDesk
extends RefCounted
## Trades proposed by a human owner. The AI team accepts only when the deal is
## clearly good for it by its own valuation (contenders value ability now,
## rebuilding teams value potential and youth, as in FcTrades), and the deal
## must pass every league rule: both rosters stay within limits, both payrolls
## pass the cap trade check, nobody with a no-trade clause is moved.
## Stars are worth more than several role players (values are weighted
## non-linearly) so the user cannot fleece the AI by trading quantity for quality.

## The AI wants to come out this much ahead (a fraction of what it gives up).
const AI_PROFIT := 0.10

var world: FcWorld
var trades: FcTrades


func _init(game_world: FcWorld) -> void:
	world = game_world
	trades = FcTrades.new(game_world)


## Result: {"accepted": bool, "reason": String}. Nothing changes unless accepted
## and `execute` is true.
func propose(league_id: int, year: int, user_team_id: int, ai_team_id: int, give_ids: Array, get_ids: Array, ai_contending: bool, execute: bool = true) -> Dictionary:
	var rules := world.rules_of_league(league_id)
	var user_team: FcTeam = world.teams.get_by_id(user_team_id)
	var ai_team: FcTeam = world.teams.get_by_id(ai_team_id)
	if user_team == null or ai_team == null or user_team_id == ai_team_id:
		return _no("Choose another team in your league.")
	var league: FcLeague = world.leagues.get_by_id(league_id)
	if not league.contains_team(ai_team_id):
		return _no("That team is not in your league.")
	if give_ids.is_empty() and get_ids.is_empty():
		return _no("Pick at least one player.")
	var give_salary := 0
	var get_salary := 0
	for pid in give_ids:
		if not user_team.roster.contains(pid):
			return _no("A player you offered is not on your roster.")
		var c := world.active_contract_of(pid)
		if c == null or rules.cap.trade_requires_consent(c):
			return _no("%s cannot be traded (no-trade clause)." % world.players.get_by_id(pid).identity.full_name())
		give_salary += c.cap_hit_for(year)
	for pid in get_ids:
		if not ai_team.roster.contains(pid):
			return _no("A player you asked for is not on that team.")
		var c2 := world.active_contract_of(pid)
		if c2 == null or rules.cap.trade_requires_consent(c2):
			return _no("%s cannot be traded (no-trade clause)." % world.players.get_by_id(pid).identity.full_name())
		get_salary += c2.cap_hit_for(year)
	var user_size := user_team.roster.size() - give_ids.size() + get_ids.size()
	var ai_size := ai_team.roster.size() - get_ids.size() + give_ids.size()
	if user_size > rules.roster_max or ai_size > rules.roster_max:
		return _no("A roster would go over the maximum of %d players." % rules.roster_max)
	if user_size < rules.roster_min or ai_size < rules.roster_min:
		return _no("A roster would fall under the minimum of %d players." % rules.roster_min)
	var user_check := rules.cap.check_trade(world.payroll_of_team(user_team_id, year), get_salary, give_salary)
	if not user_check.allowed:
		return _no("Your team: %s." % user_check.reason)
	var ai_check := rules.cap.check_trade(world.payroll_of_team(ai_team_id, year), give_salary, get_salary)
	if not ai_check.allowed:
		return _no("%s: %s." % [world.team_display_name(ai_team_id), ai_check.reason])
	var received := _package_value(give_ids, year, ai_contending)
	var given := _package_value(get_ids, year, ai_contending)
	if received < given * (1.0 + AI_PROFIT) + 1.0:
		return _no("%s turned the offer down: it does not think it gets enough back." % world.team_display_name(ai_team_id))
	if execute:
		_move(give_ids, user_team, ai_team, ai_team_id)
		_move(get_ids, ai_team, user_team, user_team_id)
		world.add_news(FcDate.new(year, 7, 3), "signing", "%s and %s completed a trade" % [world.team_display_name(user_team_id), world.team_display_name(ai_team_id)], user_team_id)
	return {"accepted": true, "reason": "Deal accepted."}


## How much the AI team values a group of players: stars count for much more than depth.
func _package_value(ids: Array, year: int, contending: bool) -> float:
	var total := 0.0
	for pid in ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		var v := trades.value_of(p, year, contending) - 40.0
		total += pow(maxf(v, 0.0), 1.6)
	return total


func _move(ids: Array, from: FcTeam, to: FcTeam, to_id: int) -> void:
	for pid in ids:
		from.roster.remove(pid)
		to.roster.add(pid)
		world.active_contract_of(pid).team_id = to_id


func _no(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
