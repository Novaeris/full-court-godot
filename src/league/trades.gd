class_name FcTrades
extends RefCounted
## AI-to-AI trades during the offseason. Teams are sorted by last season's
## record: contenders (the top third) value proven veterans, rebuilding teams
## (the bottom third) value youth and potential. A trade is a one-for-one
## swap of players: a rebuilding team gives a good veteran to a contender for a
## younger player the contender can spare, and both teams must believe they win
## the deal by their own valuation.
##
## Every trade must pass the salary rules (FcCapRules.check_trade for both
## teams, so the hard limit and salary matching hold), must not involve a player
## with a no-trade clause, and keeps both rosters the same size. Contracts move
## with the players unchanged. Each team makes at most MAX_PER_TEAM trades.

const MAX_PER_TEAM := 2
const ATTEMPTS_PER_TEAM := 6
## How much better (value points) a team must believe it does to agree.
const MARGIN := 2.0

var world: FcWorld
var market: FcPlayerMarket


func _init(game_world: FcWorld) -> void:
	world = game_world
	market = FcPlayerMarket.new(FcPlayerRatings.load_default())


## Runs the trade market for `new_year`; returns the number of trades made.
func run(league_id: int, finished: FcSeason, new_year: int, rng: FcRng) -> int:
	var league: FcLeague = world.leagues.get_by_id(league_id)
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
		if _try_trade(rules, seller_id, buyer_id, new_year, rng):
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


func _try_trade(rules: FcLeagueRules, seller_id: int, buyer_id: int, new_year: int, rng: FcRng) -> bool:
	var seller: FcTeam = world.teams.get_by_id(seller_id)
	var buyer: FcTeam = world.teams.get_by_id(buyer_id)
	# the seller offers its best veteran; the buyer offers a younger player in return
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
	var young: FcPlayer = null
	var young_gain := -INF
	for pid in buyer.roster.player_ids:
		var q: FcPlayer = world.players.get_by_id(pid)
		var c2 := world.active_contract_of(pid)
		if c2 == null or rules.cap.trade_requires_consent(c2) or _age(q, new_year) > 25:
			continue
		# the seller must like the youngster more than the veteran; the buyer the veteran more
		var seller_gain := _value(q, new_year, false) - _value(veteran, new_year, false)
		var buyer_gain := _value(veteran, new_year, true) - _value(q, new_year, true)
		if seller_gain > MARGIN and buyer_gain > MARGIN and seller_gain + buyer_gain > young_gain:
			young_gain = seller_gain + buyer_gain
			young = q
	if young == null:
		return false
	var vet_contract := world.active_contract_of(veteran.id)
	var young_contract := world.active_contract_of(young.id)
	var vet_salary := vet_contract.cap_hit_for(new_year)
	var young_salary := young_contract.cap_hit_for(new_year)
	var buyer_check := rules.cap.check_trade(world.payroll_of_team(buyer_id, new_year), vet_salary, young_salary)
	var seller_check := rules.cap.check_trade(world.payroll_of_team(seller_id, new_year), young_salary, vet_salary)
	if not buyer_check.allowed or not seller_check.allowed:
		return false
	# execute the swap
	seller.roster.remove(veteran.id)
	buyer.roster.remove(young.id)
	seller.roster.add(young.id)
	buyer.roster.add(veteran.id)
	vet_contract.team_id = buyer_id
	young_contract.team_id = seller_id
	world.add_news(FcDate.new(new_year, 7, 2), "signing", "%s trade %s to %s for %s" % [world.team_display_name(seller_id), veteran.identity.full_name(), world.team_display_name(buyer_id), young.identity.full_name()], buyer_id)
	return true
