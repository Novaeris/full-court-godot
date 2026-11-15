class_name FcSeasonEngine
extends RefCounted
## Plays a season: builds the calendar, simulates days of the regular season,
## builds the playoff bracket from the standings, plays the series, and
## records the champion, final standings and awards.
##
## The engine never changes players or teams; it only fills in the FcSeason.
## Game style comes from the league rules' `sim_era`. Rosters are read when the
## engine is created (or after refresh_teams()), so change rosters between
## seasons, not during one.

const PLAYOFF_GAP_DAYS := 5

var _world: FcWorld
var _ratings := FcPlayerRatings.load_default()
var _sim: FcGameSimulator
var _teams: Dictionary = {}


func _init(world: FcWorld, era: String = "") -> void:
	_world = world
	_sim = FcGameSimulator.new({}, era)


## Engine whose game style follows the league's rules.
static func for_league(world: FcWorld, league_id: int) -> FcSeasonEngine:
	var rules := world.rules_of_league(league_id)
	return FcSeasonEngine.new(world, rules.sim_era if rules != null else "")


func refresh_teams() -> void:
	_teams.clear()


## Creates a season with its full calendar and stores it in the world.
func start_season(league_id: int, year: int, start_date: FcDate, rng: FcRng) -> FcSeason:
	var league: FcLeague = _world.leagues.get_by_id(league_id)
	var rules := _world.rules_of_league(league_id)
	var season := FcSeason.new(_world.ids.next_id(FcWorld.KIND_SEASON))
	season.league_id = league_id
	season.year = year
	season.start_date = start_date
	season.games = FcScheduleBuilder.build(league, rules.season, rng.fork("calendar"))
	_world.seasons.add(season)
	return season


func standings_of(season: FcSeason) -> FcStandings:
	return FcStandings.compute(_world.leagues.get_by_id(season.league_id), season.games)


# --- regular season ------------------------------------------------------------

## Plays every game of the next day on the calendar (possibly none: a rest day).
## Returns the number of games played.
func play_day(season: FcSeason, rng: FcRng) -> int:
	if season.status == FcSeason.Status.PENDING:
		season.status = FcSeason.Status.REGULAR
	if season.status != FcSeason.Status.REGULAR or season.regular_season_complete():
		return 0
	var played := 0
	for g in season.games_on_day(season.next_day):
		if not g.played:
			_play_game(season, g, rng, false)
			played += 1
	season.next_day += 1
	return played


func play_days(season: FcSeason, days: int, rng: FcRng) -> int:
	var total := 0
	for i in days:
		if season.regular_season_complete():
			break
		total += play_day(season, rng)
	return total


func play_regular_season(season: FcSeason, rng: FcRng) -> void:
	while not season.regular_season_complete():
		play_day(season, rng)


# --- playoffs --------------------------------------------------------------------

## Builds the bracket from the final standings. Requires a finished regular season.
func start_playoffs(season: FcSeason) -> FcPlayoffs:
	var league: FcLeague = _world.leagues.get_by_id(season.league_id)
	var rules := _world.rules_of_league(season.league_id)
	season.playoffs = FcPlayoffBuilder.build(league, standings_of(season), rules.playoffs)
	season.status = FcSeason.Status.PLAYOFFS
	return season.playoffs


## Plays the next game of every series that is ready. Returns how many games were played.
func play_playoff_day(season: FcSeason, rng: FcRng) -> int:
	var po := season.playoffs
	if season.status != FcSeason.Status.PLAYOFFS or po == null:
		return 0
	var day := season.total_days() + PLAYOFF_GAP_DAYS + po.day
	var played := 0
	var any_finished := false
	for s in po.ready_series():
		var home := s.next_home_team()
		var away := s.team_b if home == s.team_a else s.team_a
		var g := FcScheduledGame.new(day, home, away)
		g.series = s.number
		_play_game(season, g, rng, true)
		season.games.append(g)
		if s.record_game(g.winner_id()):
			any_finished = true
		played += 1
	if any_finished:
		FcPlayoffBuilder.advance(po)
	po.day += 1
	if po.is_complete():
		finish_season(season)
	return played


func play_playoffs(season: FcSeason, rng: FcRng) -> void:
	if season.status == FcSeason.Status.REGULAR and season.regular_season_complete():
		start_playoffs(season)
	var guard := 400
	while season.status == FcSeason.Status.PLAYOFFS and guard > 0:
		play_playoff_day(season, rng)
		guard -= 1


## Plays everything that remains and returns the champion's team id.
func play_full_season(season: FcSeason, rng: FcRng) -> int:
	play_regular_season(season, rng)
	play_playoffs(season, rng)
	return season.champion_id


func finish_season(season: FcSeason) -> void:
	var standings := standings_of(season)
	season.final_standings = []
	for t in standings.league_ranking():
		season.final_standings.append([t, standings.records[t]["w"], standings.records[t]["l"]])
	if season.playoffs != null:
		season.champion_id = season.playoffs.champion_id()
		season.runner_up_id = season.playoffs.runner_up_id()
	season.awards = compute_awards(season, standings)
	season.status = FcSeason.Status.COMPLETE


# --- awards ------------------------------------------------------------------------

## A simple all-around value score: per-game production, scaled by team success.
static func value_score(stats: FcSeasonStats, player_id: int) -> float:
	return stats.per_game(player_id, "points") + 1.2 * stats.per_game(player_id, "rebounds") \
		+ 1.5 * stats.per_game(player_id, "ast") + 2.0 * stats.per_game(player_id, "stl") \
		+ 2.0 * stats.per_game(player_id, "blk") - 0.8 * stats.per_game(player_id, "tov")


func compute_awards(season: FcSeason, standings: FcStandings) -> Dictionary:
	var awards := {}
	var stats := season.stats
	var min_games := maxi(1, floori(standings.games_played(standings.league_ranking()[0]) * 0.6))
	var scoring := stats.leaders("points", min_games, 1)
	if not scoring.is_empty():
		awards["scoring_champion"] = scoring[0]
	for pair in [["rebounds", "rebounding_champion"], ["ast", "assists_leader"], ["stl", "steals_leader"], ["blk", "blocks_leader"]]:
		var best := stats.leaders(pair[0], min_games, 1)
		if not best.is_empty():
			awards[pair[1]] = best[0]
	var candidates: Array[int] = []
	for pid in stats.lines:
		if stats.lines[pid]["gp"] >= min_games:
			candidates.append(int(pid))
	var scored := {}
	for pid in candidates:
		scored[pid] = value_score(stats, pid) * (0.5 + standings.win_pct(int(stats.lines[pid]["team"])))
	candidates.sort_custom(func(a: int, b: int): return scored[a] > scored[b] if scored[a] != scored[b] else a < b)
	if not candidates.is_empty():
		awards["mvp"] = candidates[0]
		awards["all_league_first"] = candidates.slice(0, 5)
		awards["all_league_second"] = candidates.slice(5, 10)
		awards["all_league_third"] = candidates.slice(10, 15)
	# Finals MVP: best producer on the champion's roster in the playoffs
	if season.playoffs != null and season.playoffs.champion_id() > 0:
		var champion := season.playoffs.champion_id()
		var best_id := 0
		var best_value := -INF
		for pid in season.playoff_stats.lines:
			if season.playoff_stats.lines[pid]["team"] == champion:
				var v := value_score(season.playoff_stats, int(pid))
				if v > best_value:
					best_value = v
					best_id = int(pid)
		if best_id > 0:
			awards["finals_mvp"] = best_id
	return awards


# --- one game -----------------------------------------------------------------------

func _team(team_id: int) -> FcGameTeam:
	if not _teams.has(team_id):
		_teams[team_id] = FcGameTeam.from_world(_world, team_id, _ratings)
	return _teams[team_id]


func _play_game(season: FcSeason, g: FcScheduledGame, rng: FcRng, playoff: bool) -> void:
	var box := _sim.simulate(_team(g.home_id), _team(g.away_id), rng)
	g.played = true
	g.home_score = box.scores[0]
	g.away_score = box.scores[1]
	g.overtimes = box.overtimes
	if playoff:
		season.playoff_stats.add_box_score(box)
	else:
		season.stats.add_box_score(box)
