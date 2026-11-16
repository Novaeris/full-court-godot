class_name FcRecords
extends RefCounted
## The league's record book and Hall of Fame, computed from data the world keeps
## forever (career rows, plus each season's champion and awards, which survive
## archiving). Nothing here is stored, so there is no save format to migrate.
##
## Hall of Fame: a retired player becomes eligible EXPERIENCE_WAIT seasons after
## his last season and is inducted when his score reaches INDUCTION_SCORE.
## The score rewards lasting production plus honours (MVPs, titles, first-team
## selections). Weights are constants here so they are easy to tune.

const EXPERIENCE_WAIT := 2
const INDUCTION_SCORE := 60.0
const POINTS_PER_SCORE := 500.0
const REBOUNDS_PER_SCORE := 250.0
const ASSISTS_PER_SCORE := 150.0
const STEALS_PER_SCORE := 120.0
const BLOCKS_PER_SCORE := 100.0
const MVP_SCORE := 12.0
const FINALS_MVP_SCORE := 6.0
const TITLE_SCORE := 3.0
const ALL_LEAGUE_FIRST_SCORE := 5.0
const SCORING_TITLE_SCORE := 3.0

var world: FcWorld
var league_id: int


func _init(game_world: FcWorld, league: int) -> void:
	world = game_world
	league_id = league


## Honours of one player: {"mvp", "finals_mvp", "titles", "all_league_first", "scoring_titles"}.
func honours_of(player_id: int) -> Dictionary:
	var h := {"mvp": 0, "finals_mvp": 0, "titles": 0, "all_league_first": 0, "scoring_titles": 0}
	var years := {}
	for row in world.careers.get(player_id, []):
		years[row[0]] = row[1]
	for s in world.seasons.all():
		if s.league_id != league_id:
			continue
		if s.awards.get("mvp", 0) == player_id:
			h["mvp"] += 1
		if s.awards.get("finals_mvp", 0) == player_id:
			h["finals_mvp"] += 1
		if s.awards.get("scoring_champion", 0) == player_id:
			h["scoring_titles"] += 1
		if player_id in s.awards.get("all_league_first", []):
			h["all_league_first"] += 1
		if s.champion_id > 0 and years.get(s.year, -1) == s.champion_id:
			h["titles"] += 1
	return h


## Hall of Fame score of a player (see the class comment).
func score_of(player_id: int) -> float:
	var t := world.career_totals(player_id)
	var h := honours_of(player_id)
	return t["points"] / POINTS_PER_SCORE + t["rebounds"] / REBOUNDS_PER_SCORE + t["ast"] / ASSISTS_PER_SCORE \
		+ t["stl"] / STEALS_PER_SCORE + t["blk"] / BLOCKS_PER_SCORE \
		+ h["mvp"] * MVP_SCORE + h["finals_mvp"] * FINALS_MVP_SCORE + h["titles"] * TITLE_SCORE \
		+ h["all_league_first"] * ALL_LEAGUE_FIRST_SCORE + h["scoring_titles"] * SCORING_TITLE_SCORE


## Last season a player appeared in (0 if never).
func last_season_of(player_id: int) -> int:
	var rows: Array = world.careers.get(player_id, [])
	return 0 if rows.is_empty() else rows[rows.size() - 1][0]


## Hall of Fame members as of `current_year`: [[score, player id, induction year], ...], best first.
func hall_of_fame(current_year: int) -> Array:
	var out: Array = []
	for pid in world.careers:
		var p: FcPlayer = world.players.get_by_id(pid)
		if p == null or p.status != FcPlayer.Status.RETIRED:
			continue
		var inducted := last_season_of(pid) + EXPERIENCE_WAIT
		if inducted > current_year:
			continue
		var score := score_of(pid)
		if score >= INDUCTION_SCORE:
			out.append([score, pid, inducted])
	out.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	return out


## Best single seasons for a stat ("points", "rebounds", "ast", "stl", "blk"):
## [[total, player id, year], ...] best first.
func single_season_records(stat: String, count: int = 10) -> Array:
	var out: Array = []
	for pid in world.careers:
		for row in world.careers[pid]:
			var value := 0
			match stat:
				"points": value = row[4]
				"rebounds": value = row[11] + row[12]
				"ast": value = row[13]
				"stl": value = row[14]
				"blk": value = row[15]
			out.append([value, pid, row[0]])
	out.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else (a[1] < b[1] if a[1] != b[1] else a[2] < b[2]))
	return out.slice(0, count)
