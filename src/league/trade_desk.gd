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
## The owner's general manager negotiates: a skill of 100 lowers the AI's required profit by this much, a skill of 0 raises it.
const NEGOTIATION_EFFECT := 0.08
## Each point of the AI club's wariness (it remembers the owner's recent trades) raises the profit it demands by this much.
const WARINESS_COST := 0.02
## How many drafts ahead picks can be traded.
const PICK_YEARS := 3

var world: FcWorld
var trades: FcTrades


func _init(game_world: FcWorld) -> void:
	world = game_world
	trades = FcTrades.new(game_world)


## Result: {"accepted": bool, "reason": String}. Nothing changes unless accepted
## and `execute` is true.
func propose(league_id: int, year: int, user_team_id: int, ai_team_id: int, give_ids: Array, get_ids: Array, ai_contending: bool, execute: bool = true, give_picks: Array = [], get_picks: Array = [], first_pick_year: int = 0, negotiation: float = 50.0, wariness: int = 0) -> Dictionary:
	var rules := world.rules_of_league(league_id)
	var user_team: FcTeam = world.teams.get_by_id(user_team_id)
	var ai_team: FcTeam = world.teams.get_by_id(ai_team_id)
	if user_team == null or ai_team == null or user_team_id == ai_team_id:
		return _no("Choose another team in your league.")
	var league: FcLeague = world.leagues.get_by_id(league_id)
	if not league.contains_team(ai_team_id):
		return _no("That team is not in your league.")
	if give_ids.is_empty() and get_ids.is_empty() and give_picks.is_empty() and get_picks.is_empty():
		return _no("Pick at least one player or draft pick.")
	for pick in give_picks:
		if not _pick_ok(pick, user_team_id, first_pick_year):
			return _no("A pick you offered is not yours to trade.")
	for pick in get_picks:
		if not _pick_ok(pick, ai_team_id, first_pick_year):
			return _no("A pick you asked for does not belong to that team.")
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
	var strengths := _strength_fractions(league)
	var received := _package_value(give_ids, year, ai_contending) + _picks_value(give_picks, first_pick_year, strengths, ai_contending)
	var given := _package_value(get_ids, year, ai_contending) + _picks_value(get_picks, first_pick_year, strengths, ai_contending)
	if received < given * (1.0 + AI_PROFIT - NEGOTIATION_EFFECT * (negotiation - 50.0) / 50.0 + WARINESS_COST * wariness) + 1.0:
		var wary_note := " It remembers your recent trades and drives a harder bargain." if wariness > 0 else ""
		return _no("%s turned the offer down: it does not think it gets enough back.%s" % [world.team_display_name(ai_team_id), wary_note])
	if execute:
		# everybody leaves first, then everybody arrives: a full roster only has room after its outgoing players go
		for pid in give_ids:
			user_team.roster.remove(pid)
		for pid in get_ids:
			ai_team.roster.remove(pid)
		_arrive(give_ids, ai_team, ai_team_id)
		_arrive(get_ids, user_team, user_team_id)
		for pick in give_picks:
			world.set_pick_owner(pick[0], pick[1], pick[2], ai_team_id)
		for pick in get_picks:
			world.set_pick_owner(pick[0], pick[1], pick[2], user_team_id)
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


## A pick is [year, round, original team id].
func _pick_ok(pick: Array, owner_id: int, first_pick_year: int) -> bool:
	if pick.size() != 3 or first_pick_year <= 0:
		return false
	return pick[0] >= first_pick_year and pick[0] < first_pick_year + PICK_YEARS \
		and pick[1] >= 1 and pick[1] <= FcOffseason.DRAFT_ROUNDS \
		and world.pick_owner(pick[0], pick[1], pick[2]) == owner_id


## Team id -> 0 (weakest team) .. 1 (strongest); see FcTrades.strength_fractions.
func _strength_fractions(league: FcLeague) -> Dictionary:
	return trades.strength_fractions(league)


## What the AI thinks a set of picks is worth, in the same units as _package_value. A pick is
## worth more the weaker its original team is expected to be, and a first-round pick of
## a bad team is worth about as much as a good young player. Picks further away are
## less certain (pulled toward the middle of the order) and slightly discounted.
## Contenders value picks less, rebuilding teams more.
func _picks_value(picks: Array, first_pick_year: int, strengths: Dictionary, contending: bool) -> float:
	var total := 0.0
	for pick in picks:
		var ahead: int = pick[0] - first_pick_year
		var f: float = lerpf(float(strengths.get(pick[2], 0.5)), 0.5, minf(0.6, 0.25 * ahead))
		var base := 40.0 + 140.0 * (1.0 - f) if pick[1] == 1 else 4.0 + 14.0 * (1.0 - f)
		total += base * pow(0.92, ahead) * (0.85 if contending else 1.15)
	return total


func _arrive(ids: Array, to: FcTeam, to_id: int) -> void:
	for pid in ids:
		to.roster.add(pid)
		world.active_contract_of(pid).team_id = to_id


func _no(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
