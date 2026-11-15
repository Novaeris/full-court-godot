class_name FcGameTeam
extends RefCounted
## Everything the simulator needs to know about one team for one game: its
## players (as FcSimPlayer, best first) and its coach's style and skill.
## Build one from the world with FcGameTeam.from_world(), or by hand in tests.

var team_id: int = 0
var name: String = ""
var abbreviation: String = ""
var players: Array[FcSimPlayer] = []
## Coach style 0-100 (50 = neutral): pace_preference, three_point_emphasis,
## defensive_aggression, ball_movement; plus coaching skills used by the game:
## offensive_strategy, defensive_strategy, game_management.
var tactics: Dictionary = {
	"pace": 50.0, "three": 50.0, "aggression": 50.0, "ball_movement": 50.0,
	"offense": 50.0, "defense": 50.0, "game_management": 50.0,
}


## Players available to play, best overall first.
func sort_by_overall() -> void:
	players.sort_custom(func(a: FcSimPlayer, b: FcSimPlayer): return a.overall > b.overall)


static func from_world(world: FcWorld, team_id: int, ratings: FcPlayerRatings) -> FcGameTeam:
	var team: FcTeam = world.teams.get_by_id(team_id)
	var g := FcGameTeam.new()
	g.team_id = team_id
	var city: FcCity = world.cities.get_by_id(team.city_id)
	g.name = team.identity.display_name(city.name if city != null else "")
	g.abbreviation = team.identity.abbreviation
	var injured: Array[FcPlayer] = []
	for pid in team.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		if p == null:
			continue
		if p.games_out > 0:
			injured.append(p)
		else:
			g.players.append(FcSimPlayer.new(p, ratings, team_id))
	# a team always has at least 8 players: the least hurt return early if needed
	injured.sort_custom(func(a: FcPlayer, b: FcPlayer): return a.games_out < b.games_out)
	while g.players.size() < 8 and not injured.is_empty():
		g.players.append(FcSimPlayer.new(injured.pop_front(), ratings, team_id))
	g.sort_by_overall()
	var coach := world.staff_in_role(team_id, FcStaffRole.Id.HEAD_COACH)
	if coach != null:
		g.tactics["pace"] = float(coach.philosophy.get_value("pace_preference"))
		g.tactics["three"] = float(coach.philosophy.get_value("three_point_emphasis"))
		g.tactics["aggression"] = float(coach.philosophy.get_value("defensive_aggression"))
		g.tactics["ball_movement"] = float(coach.philosophy.get_value("ball_movement"))
		g.tactics["offense"] = float(coach.skills.get_value("offensive_strategy"))
		g.tactics["defense"] = float(coach.skills.get_value("defensive_strategy"))
		g.tactics["game_management"] = float(coach.skills.get_value("game_management"))
	return g
