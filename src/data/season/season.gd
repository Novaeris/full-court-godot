class_name FcSeason
extends RefCounted
## One season of one league: its calendar, results so far, statistics, and
## (once played) playoffs, awards and the champion. A season is identified by
## the calendar year in which it starts (2026 = the 2026-27 season).
##
## Status: PENDING (created, nothing played) -> REGULAR (games being played)
## -> PLAYOFFS -> COMPLETE. Box scores are not stored (too large); results
## and accumulated player statistics are.

const SCHEMA_VERSION := 1

enum Status { PENDING = 0, REGULAR = 1, PLAYOFFS = 2, COMPLETE = 3 }

var id: int
var league_id: int = 0
var year: int = 2026
## Date of day 0 of the regular season.
var start_date := FcDate.new(2026, 10, 20)
var status: int = Status.PENDING
var games: Array[FcScheduledGame] = []
## The next regular-season day that has not been played yet.
var next_day: int = 0
var stats := FcSeasonStats.new()
var playoff_stats := FcSeasonStats.new()
var champion_id: int = 0
var runner_up_id: int = 0
## Final standings, kept when the season completes: [[team id, wins, losses], ...] best first.
var final_standings: Array = []
## Awards by name, e.g. {"mvp": player id, "scoring_champion": player id, ...}.
var awards: Dictionary = {}
## The playoff bracket and series (see FcPlayoffs); null until the playoffs start.
var playoffs: FcPlayoffs = null


func _init(season_id: int = 0) -> void:
	id = season_id


func date_of_day(day: int) -> FcDate:
	return start_date.add_days(day)


func total_days() -> int:
	return FcScheduleBuilder.length_in_days(games) if not games.is_empty() else 0


func games_on_day(day: int) -> Array[FcScheduledGame]:
	var out: Array[FcScheduledGame] = []
	for g in games:
		if g.day == day:
			out.append(g)
		elif g.day > day:
			break
	return out


func games_played_count() -> int:
	var n := 0
	for g in games:
		if g.played:
			n += 1
	return n


func regular_season_complete() -> bool:
	return not games.is_empty() and games_played_count() == games.size()


func team_games(team_id: int) -> Array[FcScheduledGame]:
	var out: Array[FcScheduledGame] = []
	for g in games:
		if g.involves(team_id):
			out.append(g)
	return out


func validate(league: FcLeague) -> Array[String]:
	var errors: Array[String] = []
	if id <= 0:
		errors.append("season id must be positive")
	if league_id <= 0:
		errors.append("season needs a league")
	if not start_date.is_valid():
		errors.append("season start date is invalid")
	if status < Status.PENDING or status > Status.COMPLETE:
		errors.append("invalid season status")
	var previous_day := 0
	var played := 0
	for g in games:
		if g.day < previous_day:
			errors.append("games are not in date order")
			break
		previous_day = g.day
	for g in games:
		if league != null and (not league.contains_team(g.home_id) or not league.contains_team(g.away_id)):
			errors.append("a game involves a team outside the league")
			break
		if g.home_id == g.away_id:
			errors.append("a team plays itself")
			break
	for g in games:
		if g.played:
			played += 1
			if g.home_score == g.away_score:
				errors.append("a played game ended in a tie")
				break
	if status >= Status.PLAYOFFS and played != games.size() and not games.is_empty():
		errors.append("the playoffs started before the regular season finished")
	if status == Status.PENDING and played > 0:
		errors.append("a pending season already has results")
	if status == Status.COMPLETE and champion_id <= 0:
		errors.append("a completed season needs a champion")
	return errors


func to_dict() -> Dictionary:
	var game_dicts: Array = []
	for g in games:
		game_dicts.append(g.to_dict())
	return {
		"schema": SCHEMA_VERSION, "id": id, "league_id": league_id, "year": year,
		"start_date": start_date.to_iso(), "status": status, "next_day": next_day,
		"games": game_dicts, "stats": stats.to_dict(), "playoff_stats": playoff_stats.to_dict(),
		"champion_id": champion_id, "runner_up_id": runner_up_id,
		"final_standings": final_standings.duplicate(true), "awards": awards.duplicate(true),
		"playoffs": playoffs.to_dict() if playoffs != null else {},
	}


static func from_dict(d: Dictionary) -> FcSeason:
	var s := FcSeason.new(int(d.get("id", 0)))
	s.league_id = int(d.get("league_id", 0))
	s.year = int(d.get("year", 2026))
	var date := FcDate.from_iso(str(d.get("start_date", "")))
	s.start_date = date if date != null else FcDate.new(0, 0, 0)
	s.status = int(d.get("status", Status.PENDING))
	s.next_day = int(d.get("next_day", 0))
	for g in d.get("games", []):
		s.games.append(FcScheduledGame.from_dict(g))
	s.stats = FcSeasonStats.from_dict(d.get("stats", {}))
	s.playoff_stats = FcSeasonStats.from_dict(d.get("playoff_stats", {}))
	s.champion_id = int(d.get("champion_id", 0))
	s.runner_up_id = int(d.get("runner_up_id", 0))
	for row in d.get("final_standings", []):
		s.final_standings.append([int(row[0]), int(row[1]), int(row[2])])
	var raw_awards: Dictionary = d.get("awards", {})
	for key in raw_awards:
		# JSON turns integers into floats; award values are player ids (or lists of ids).
		var value = raw_awards[key]
		if value is Array:
			var ids: Array = []
			for v in value:
				ids.append(int(v))
			s.awards[str(key)] = ids
		else:
			s.awards[str(key)] = int(value)
	var po: Dictionary = d.get("playoffs", {})
	if not po.is_empty():
		s.playoffs = FcPlayoffs.from_dict(po)
	return s
