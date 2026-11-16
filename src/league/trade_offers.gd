class_name FcTradeOffers
extends RefCounted
## Trade offers that AI teams make to the human owner. An AI team picks a player of the
## owner's it likes and offers one of its own players in return, choosing the deal that
## is only just good enough for itself (so the owner gets the most it will give). Every offer
## passes the same rules as a trade the owner proposes (cap, roster limits, no-trade
## clauses) and is checked again when accepted, because rosters change.
## The offers are derived from the situation (the year and a time bucket), so the same list
## appears every time it is asked for and nothing needs saving.

const MAX_OFFERS := 3
const TEAMS_CONSIDERED := 5
const OWN_PLAYERS_CONSIDERED := 6
## An offer is dropped if the AI would win by more than this factor (too good to be a fair offer).
const MAX_LOPSIDED := 1.7

var world: FcWorld
var desk: FcTradeDesk
var ratings := FcPlayerRatings.load_default()


func _init(game_world: FcWorld) -> void:
	world = game_world
	desk = FcTradeDesk.new(game_world)


## `contending_of(team_id) -> bool` says whether an AI team is in a win-now mood.
## Returns [{"team", "name", "give" (the owner's player id), "get" (the AI player id)}].
func generate(league_id: int, year: int, user_team_id: int, contending_of: Callable, bucket: int, first_pick_year: int) -> Array:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var rng := FcRng.new(hash("offers:%d:%d:%d" % [user_team_id, year, bucket]))
	var others: Array = []
	for tid in league.all_team_ids():
		if tid != user_team_id:
			others.append(tid)
	others.sort()
	var chosen: Array = []
	while chosen.size() < TEAMS_CONSIDERED and not others.is_empty():
		var i := rng.range_int(0, others.size() - 1)
		chosen.append(others[i])
		others.remove_at(i)
	var mine: Array = []
	for pid in world.teams.get_by_id(user_team_id).roster.player_ids:
		mine.append([ratings.overall(world.players.get_by_id(pid)), pid])
	mine.sort_custom(func(a, b): return a[0] > b[0])
	var wanted: Array = mine.slice(0, OWN_PLAYERS_CONSIDERED)
	var out: Array = []
	for ai_id in chosen:
		if out.size() >= MAX_OFFERS:
			break
		var contending: bool = contending_of.call(ai_id)
		var best := {}
		var best_ratio := INF
		for entry in wanted:
			var income := desk._package_value([entry[1]], year, contending)
			if income <= 0.0:
				continue
			for ai_pid in world.teams.get_by_id(ai_id).roster.player_ids:
				var outgoing := desk._package_value([ai_pid], year, contending)
				if income < outgoing * (1.0 + FcTradeDesk.AI_PROFIT) + 1.0:
					continue
				var ratio := income / maxf(outgoing, 1.0)
				if ratio < best_ratio and ratio <= MAX_LOPSIDED:
					best_ratio = ratio
					best = {"give": entry[1], "get": ai_pid}
		if best.is_empty():
			continue
		var verdict := desk.propose(league_id, year, user_team_id, ai_id, [best["give"]], [best["get"]], contending, false, [], [], first_pick_year)
		if verdict["accepted"]:
			out.append({"team": ai_id, "name": world.team_display_name(ai_id), "give": best["give"], "get": best["get"]})
	return out
