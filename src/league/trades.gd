class_name FcTrades
extends RefCounted
## AI-to-AI trades during the offseason. Teams are sorted by last season's
## record: contenders (the top third) value proven veterans, rebuilding teams
## (the bottom third) value youth and potential. A trade is a one-for-one
## swap of players: a rebuilding team gives a good veteran to a contender for a
## younger player the contender can spare, and both teams must believe they win
## the deal by their own valuation. The contender can add draft picks as a sweetener,
## or pay with picks alone (then the rosters change size by one, within the league's
## limits). Picks are valued by their original team's expected strength (rebuilding
## teams like picks more than contenders do). The most even deal is chosen.
##
## Every trade must pass the salary rules (FcCapRules.check_trade for both
## teams, so the hard limit and salary matching hold), must not involve a player
## with a no-trade clause, and keeps both rosters the same size. Contracts move
## with the players unchanged. Each team makes at most MAX_PER_TEAM trades.

const MAX_PER_TEAM := 2
const ATTEMPTS_PER_TEAM := 6
## How much better (value points) a team must believe it does to agree.
const MARGIN := 2.0
## Picks are only added when they help: this much of an uneven split is accepted instead.
const PICK_RELUCTANCE := 3.0

## The date written on the trades this object makes (null = the offseason default, 2 July). The season clock sets it for in-season trades.
var trade_date: FcDate = null
var world: FcWorld
var market: FcPlayerMarket


func _init(game_world: FcWorld) -> void:
	world = game_world
	market = FcPlayerMarket.new(FcPlayerRatings.load_default())


## Runs the trade market for `new_year`; returns the number of trades made.
func run(league_id: int, finished: FcSeason, new_year: int, rng: FcRng) -> int:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var strengths := strength_fractions(league)
	var rules := world.rules_of_league(league_id)
	var ranking := FcStandings.compute(league, finished.games).league_ranking()
	var third := maxi(1, floori(ranking.size() / 3.0))
	var contenders: Array[int] = ranking.slice(0, third)
	var rebuilders: Array[int] = ranking.slice(ranking.size() - third)
	var made := 0
	var counts := {}
	for attempt in rebuilders.size() * ATTEMPTS_PER_TEAM:
		var seller_id: int = rebuilders[rng.range_int(0, rebuilders.size() - 1)]
		var buyer_id: int = contenders[rng.range_int(0, contenders.size() - 1)]
		if seller_id == buyer_id or counts.get(seller_id, 0) >= MAX_PER_TEAM or counts.get(buyer_id, 0) >= MAX_PER_TEAM:
			continue
		if _try_trade(rules, seller_id, buyer_id, new_year, rng, strengths, new_year + 1):
			counts[seller_id] = counts.get(seller_id, 0) + 1
			counts[buyer_id] = counts.get(buyer_id, 0) + 1
			made += 1
	return made


## Public valuation (also used when a human proposes a trade).
func value_of(player: FcPlayer, year: int, contending: bool) -> float:
	return _value(player, year, contending)


func _age(player: FcPlayer, new_year: int) -> int:
	return player.age_on(FcDate.new(new_year, 7, 1))


## How a team values a player: contenders want ability now, rebuilders want potential.
func _value(player: FcPlayer, new_year: int, contending: bool) -> float:
	var age := _age(player, new_year)
	var overall := market.ratings.overall(player)
	if contending:
		return overall - maxf(0.0, age - 31) * 1.2
	return overall * 0.6 + player.development.potential * 0.4 - maxf(0.0, age - 26) * 1.6


## One trade attempt between a seller (rebuilding side, gives a veteran) and a buyer (gives
## a young player and/or picks); used by the general manager for the owner's team.
## Returns true if a deal was made.
func attempt(league_id: int, seller_id: int, buyer_id: int, new_year: int, rng: FcRng) -> bool:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	return _try_trade(world.rules_of_league(league_id), seller_id, buyer_id, new_year, rng, strength_fractions(league), new_year + 1)


## Team id -> 0 (weakest team) .. 1 (strongest), by the average rating of its best eight players.
func strength_fractions(league: FcLeague) -> Dictionary:
	var scored: Array = []
	for tid in league.all_team_ids():
		var values: Array = []
		for pid in world.teams.get_by_id(tid).roster.player_ids:
			values.append(market.ratings.overall(world.players.get_by_id(pid)))
		values.sort()
		values.reverse()
		var top := values.slice(0, 8)
		var total := 0.0
		for v in top:
			total += v
		scored.append([total / maxf(1.0, top.size()), tid])
	scored.sort()
	var out := {}
	for i in scored.size():
		out[scored[i][1]] = float(i) / maxf(1.0, scored.size() - 1.0)
	return out


## What a draft pick is worth to a team in player-value points (the units of _value):
## a first-round pick of a bad team is a few points, a second-rounder about one.
## `pick` is [year, round, original team id].
func pick_points(pick: Array, first_pick_year: int, strengths: Dictionary, contending: bool) -> float:
	var ahead: int = pick[0] - first_pick_year
	var f: float = lerpf(float(strengths.get(pick[2], 0.5)), 0.5, minf(0.6, 0.25 * ahead))
	var base := 3.0 + 9.0 * (1.0 - f) if pick[1] == 1 else 0.5 + 1.5 * (1.0 - f)
	return base * pow(0.92, ahead) * (0.85 if contending else 1.15)


## The draft picks a team owns in the tradable years: [[year, round, original team id], ...].
func picks_owned_by(team_id: int, league: FcLeague, first_pick_year: int) -> Array:
	var out: Array = []
	for year in range(first_pick_year, first_pick_year + FcTradeDesk.PICK_YEARS):
		for round_number in range(1, FcOffseason.DRAFT_ROUNDS + 1):
			for tid in league.all_team_ids():
				if world.pick_owner(year, round_number, tid) == team_id:
					out.append([year, round_number, tid])
	return out


## `first_pick_year` 0 means picks are not part of the deal (the older, player-only trade).
func _try_trade(rules: FcLeagueRules, seller_id: int, buyer_id: int, new_year: int, rng: FcRng, strengths: Dictionary = {}, first_pick_year: int = 0) -> bool:
	var seller: FcTeam = world.teams.get_by_id(seller_id)
	var buyer: FcTeam = world.teams.get_by_id(buyer_id)
	var league: FcLeague = world.leagues.get_by_id(rules.league_id)
	if first_pick_year > 0 and strengths.is_empty():
		strengths = strength_fractions(league)
	# the seller offers its best veteran; the buyer offers something in return
	var veteran: FcPlayer = null
	var best := -INF
	for pid in seller.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		var c := world.active_contract_of(pid)
		if c == null or rules.cap.trade_requires_consent(c) or _age(p, new_year) < 27:
			continue
		var v := _value(p, new_year, true)
		if v > best:
			best = v
			veteran = p
	if veteran == null:
		return false
	# candidate returns: a young player (or nobody) plus none or one of the buyer's picks
	var young_options: Array = []
	for pid in buyer.roster.player_ids:
		var q: FcPlayer = world.players.get_by_id(pid)
		var c2 := world.active_contract_of(pid)
		if c2 == null or rules.cap.trade_requires_consent(c2) or _age(q, new_year) > 25:
			continue
		young_options.append(q)
	if first_pick_year > 0:
		young_options.append(null)   # picks only
	var pick_options: Array = [null]
	if first_pick_year > 0:
		pick_options.append_array(picks_owned_by(buyer_id, league, first_pick_year))
	var vet_contract := world.active_contract_of(veteran.id)
	var vet_salary := vet_contract.cap_hit_for(new_year)
	var chosen_young: FcPlayer = null
	var chosen_pick = null
	var found := false
	var smallest_gap := INF
	for q in young_options:
		for pick in pick_options:
			if q == null and pick == null:
				continue
			var seller_gain := _value(veteran, new_year, false) * -1.0
			var buyer_gain := _value(veteran, new_year, true)
			if q != null:
				seller_gain += _value(q, new_year, false)
				buyer_gain -= _value(q, new_year, true)
			if pick != null:
				seller_gain += pick_points(pick, first_pick_year, strengths, false)
				buyer_gain -= pick_points(pick, first_pick_year, strengths, true)
			if seller_gain <= MARGIN or buyer_gain <= MARGIN:
				continue
			# prefer the most even split, and fewer sweeteners when equal
			var gap := absf(seller_gain - buyer_gain) + (PICK_RELUCTANCE if pick != null else 0.0)
			if gap < smallest_gap:
				smallest_gap = gap
				chosen_young = q
				chosen_pick = pick
				found = true
	if not found:
		return false
	var young_salary := 0
	var young_contract: FcContract = null
	if chosen_young != null:
		young_contract = world.active_contract_of(chosen_young.id)
		young_salary = young_contract.cap_hit_for(new_year)
	else:
		# no player comes back, so the rosters change size: stay inside the league limits
		if buyer.roster.size() >= rules.roster_max or seller.roster.size() <= rules.roster_min:
			return false
	var buyer_check := rules.cap.check_trade(world.payroll_of_team(buyer_id, new_year), vet_salary, young_salary)
	var seller_check := rules.cap.check_trade(world.payroll_of_team(seller_id, new_year), young_salary, vet_salary)
	if not buyer_check.allowed or not seller_check.allowed:
		return false
	# execute the deal
	# remove first, then add: a roster that is full only has room after its outgoing player leaves
	seller.roster.remove(veteran.id)
	if chosen_young != null:
		buyer.roster.remove(chosen_young.id)
	buyer.roster.add(veteran.id)
	vet_contract.team_id = buyer_id
	var back: Array[String] = []
	if chosen_young != null:
		seller.roster.add(chosen_young.id)
		young_contract.team_id = seller_id
		back.append(chosen_young.identity.full_name())
	if chosen_pick != null:
		world.set_pick_owner(chosen_pick[0], chosen_pick[1], chosen_pick[2], seller_id)
		back.append("a %d %s-round pick" % [chosen_pick[0], "first" if chosen_pick[1] == 1 else "second"])
	var moved: Array = [veteran.id]
	if chosen_young != null:
		moved.append(chosen_young.id)
	world.add_transaction(trade_date if trade_date != null else FcDate.new(new_year, 7, 2), "trade", "%s trade %s to %s for %s" % [world.team_display_name(seller_id), veteran.identity.full_name(), world.team_display_name(buyer_id), " and ".join(back)], buyer_id, moved, seller_id)
	return true
