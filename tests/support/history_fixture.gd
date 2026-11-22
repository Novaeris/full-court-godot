class_name FcHistoryFixture
extends RefCounted
## TEST FIXTURE ONLY: finished seasons built by hand (standings, a bracket, a champion, an MVP) and career rows built by hand, so the
## history rules (franchise records, retired numbers, rivalries, storylines) can be tested with exact, known answers.

const SEASON_ID_BASE := 5000

static var _next_id: int = SEASON_ID_BASE


## A small league from the generator (8 teams, 2 conferences). Returns {"world", "league_id", "teams": [team ids]}.
static func league(seed_value: int = 77) -> Dictionary:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.roster_min = 13
	cfg.free_agent_count = 0
	cfg.assistant_coaches = 0
	cfg.scouts = 0
	var world := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(seed_value)
	var league_id: int = world.leagues.ids()[0]
	var teams: Array[int] = []
	for t in world.teams.ids():
		teams.append(t)
	return {"world": world, "league_id": league_id, "teams": teams}


## A finished season. `order` lists team ids best record first (every team of the league); the top `field` of them make the playoffs
## and are paired best against worst each round; `champion` (one of the field) wins every series it plays, every other series goes to the
## better seed. Winners take a series 4-2. `mvp` is a player id or 0. Returns the season (already added to the world).
static func season(world: FcWorld, league_id: int, year: int, order: Array, champion: int, field: int = 8, mvp: int = 0) -> FcSeason:
	var s := FcSeason.new(_next_id)
	_next_id += 1
	s.league_id = league_id
	s.year = year
	s.status = FcSeason.Status.COMPLETE
	for i in order.size():
		s.final_standings.append([order[i], 60 - i * 4, 22 + i * 4])
	var playoffs := FcPlayoffs.new()
	var alive: Array = order.slice(0, field)
	for i in alive.size():
		playoffs.qualifiers.append({"team": alive[i], "bracket": -1, "seed": i + 1, "leader": false, "rank": i + 1})
	var number := 1
	var round_number := 0
	while alive.size() > 1:
		round_number += 1
		var winners: Array = []
		for i in floori(alive.size() / 2.0):
			var a: int = alive[i]
			var b: int = alive[alive.size() - 1 - i]
			var winner: int = champion if (a == champion or b == champion) else a
			winners.append(winner)
			playoffs.series.append(_series(number, round_number, a, b, winner))
			number += 1
		winners.sort_custom(func(x, y) -> bool: return order.find(x) < order.find(y))
		alive = winners
	playoffs.rounds = round_number
	s.playoffs = playoffs
	s.champion_id = playoffs.champion_id()
	s.runner_up_id = playoffs.runner_up_id()
	if mvp > 0:
		s.awards["mvp"] = mvp
	world.seasons.add(s)
	return s


## A finished season with exactly these series: [[team a, team b, wins a, wins b, round], ...], the last one being the final.
static func series_season(world: FcWorld, league_id: int, year: int, defs: Array) -> FcSeason:
	var s := FcSeason.new(_next_id)
	_next_id += 1
	s.league_id = league_id
	s.year = year
	s.status = FcSeason.Status.COMPLETE
	var playoffs := FcPlayoffs.new()
	var number := 1
	var top_round := 1
	for d in defs:
		var winner: int = d[0] if d[2] > d[3] else d[1]
		var series := _series(number, d[4], d[0], d[1], winner)
		series.wins_a = d[2]
		series.wins_b = d[3]
		playoffs.series.append(series)
		top_round = maxi(top_round, d[4])
		number += 1
	playoffs.rounds = top_round
	s.playoffs = playoffs
	s.champion_id = playoffs.champion_id()
	s.runner_up_id = playoffs.runner_up_id()
	world.seasons.add(s)
	return s


static func _series(number: int, round_number: int, a: int, b: int, winner: int) -> FcPlayoffSeries:
	var series := FcPlayoffSeries.new()
	series.number = number
	series.round = round_number
	series.best_of = 7
	series.team_a = a
	series.team_b = b
	series.wins_a = 4 if winner == a else 2
	series.wins_b = 4 if winner == b else 2
	series.winner_id = winner
	return series


## A career row (the layout FcWorld.record_career writes): year, team, games, seconds, points, then zeros, rebounds, assists.
static func row(year: int, team_id: int, games: int, points: int, rebounds: int = 0, assists: int = 0) -> Array:
	var r: Array = [year, team_id, games, games * 1800, points, 0, 0, 0, 0, 0, 0, rebounds, 0, assists, 0, 0, 0, 0]
	return r


## A retired player with career rows with `team_id` for `years`, `points_per_year` each, retired in the last year.
static func retired_player(world: FcWorld, team_id: int, first_year: int, years: int, points_per_year: int, id_hint: int) -> FcPlayer:
	var defs := FcDefinitionSet.load_default()
	var p := FcPlayer.new(id_hint, defs)
	p.identity.first_name = "Legend"
	p.identity.last_name = "Number%d" % id_hint
	p.identity.country = "Testland"
	p.identity.birth_date = FcDate.new(1980, 1, 1)
	p.primary_position = FcPosition.Id.SG
	p.status = FcPlayer.Status.RETIRED
	p.retired_season = first_year + years - 1
	world.players.add(p)
	var rows: Array = []
	for i in years:
		rows.append(row(first_year + i, team_id, 70, points_per_year, 300, 200))
	world.careers[id_hint] = rows
	return p
