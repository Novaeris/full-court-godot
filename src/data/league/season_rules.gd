class_name FcSeasonRules
extends RefCounted
## How many times teams play each other in the regular season, by how close
## the opponent is:
##   division opponents          (same division)
##   conference opponents        (same conference, other division)
##   other-conference opponents  (the opposite conference(s))
## Games per team follows from the league structure, e.g. a 30-team league of
## 2 conferences x 3 divisions of 5 has 4 division, 10 conference and 15
## other-conference opponents per team.
##
## RECOMMENDED ranges (the founder's guideline) are 2-3 / 1-2 / 1-2. Wider
## values are allowed (1-4 / 1-3 / 1-3) because small leagues need more games
## per opponent to get a long enough season.
## Whether a schedule can actually be built is shown by FcMatchupPlanner.

const MIN_GAMES_PER_TEAM := 10
const MAX_GAMES_PER_TEAM := 120
const RECOMMENDED_DIVISION := [2, 3]
const RECOMMENDED_CONFERENCE := [1, 2]
const RECOMMENDED_OTHER := [1, 2]
const ALLOWED_DIVISION := [1, 4]
const ALLOWED_CONFERENCE := [1, 3]
const ALLOWED_OTHER := [1, 3]

var games_per_division_opponent: int = 3
var games_per_conference_opponent: int = 2
var games_per_other_conference_opponent: int = 1


## Number of games a team plays under these rules, for any (even uneven) league.
func games_for_team(league: FcLeague, team_id: int) -> int:
	var division := league.division_of_team(team_id)
	var conference := league.conference_of_team(team_id)
	if division == null or conference == null:
		return 0
	var in_conference := 0
	for d in conference.divisions:
		in_conference += d.team_ids.size()
	var division_opponents := division.team_ids.size() - 1
	var conference_opponents := in_conference - division.team_ids.size()
	var other_opponents := league.team_count() - in_conference
	return division_opponents * games_per_division_opponent \
		+ conference_opponents * games_per_conference_opponent \
		+ other_opponents * games_per_other_conference_opponent


## Games for the typical team (the most common count; equal for all teams in
## an evenly built league).
func games_per_team(league: FcLeague) -> int:
	var counts := {}
	for tid in league.all_team_ids():
		var g := games_for_team(league, tid)
		counts[g] = int(counts.get(g, 0)) + 1
	var best := 0
	var best_count := -1
	for g in counts:
		if counts[g] > best_count:
			best = g
			best_count = counts[g]
	return best


func validate(league: FcLeague) -> Array[String]:
	var errors: Array[String] = []
	_check_range(errors, "games per division opponent", games_per_division_opponent, ALLOWED_DIVISION)
	_check_range(errors, "games per conference opponent", games_per_conference_opponent, ALLOWED_CONFERENCE)
	if league.conferences.size() > 1:
		_check_range(errors, "games per other-conference opponent", games_per_other_conference_opponent, ALLOWED_OTHER)
	elif games_per_other_conference_opponent != 0:
		errors.append("a league with one conference has no other-conference opponents; set games per other-conference opponent to 0")
	if not errors.is_empty() or league.team_count() < 2:
		return errors
	for tid in league.all_team_ids():
		var g := games_for_team(league, tid)
		if g < MIN_GAMES_PER_TEAM or g > MAX_GAMES_PER_TEAM:
			errors.append("team %d would play %d games; a season must be %d-%d games" % [tid, g, MIN_GAMES_PER_TEAM, MAX_GAMES_PER_TEAM])
			break
	return errors


## Non-fatal notes: values outside the recommended ranges, unusual season length.
func advice(league: FcLeague) -> Array[String]:
	var notes: Array[String] = []
	_note_range(notes, "division opponent", games_per_division_opponent, RECOMMENDED_DIVISION)
	_note_range(notes, "conference opponent", games_per_conference_opponent, RECOMMENDED_CONFERENCE)
	_note_range(notes, "other-conference opponent", games_per_other_conference_opponent, RECOMMENDED_OTHER)
	var g := games_per_team(league)
	if g > 0 and g < 30:
		notes.append("only %d games per team is a short season" % g)
	if g > 100:
		notes.append("%d games per team is a very long season" % g)
	return notes


func to_dict() -> Dictionary:
	return {
		"games_per_division_opponent": games_per_division_opponent,
		"games_per_conference_opponent": games_per_conference_opponent,
		"games_per_other_conference_opponent": games_per_other_conference_opponent,
	}


static func from_dict(data: Dictionary) -> FcSeasonRules:
	var r := FcSeasonRules.new()
	r.games_per_division_opponent = int(data.get("games_per_division_opponent", r.games_per_division_opponent))
	r.games_per_conference_opponent = int(data.get("games_per_conference_opponent", r.games_per_conference_opponent))
	r.games_per_other_conference_opponent = int(data.get("games_per_other_conference_opponent", r.games_per_other_conference_opponent))
	return r


## Picks games-per-opponent values that give a season length close to
## `target_games`. Values inside the recommended ranges are strongly
## preferred; wider values are used only when the recommended ones cannot get
## near the target (small leagues). A league with one conference gets 0 for
## the other-conference tier (it has no such opponents).
static func suggest(league: FcLeague, target_games: int = 82) -> FcSeasonRules:
	var best := FcSeasonRules.new()
	var best_score := INF
	var multi_conference := league.conferences.size() > 1
	var other_values: Array = range(ALLOWED_OTHER[0], ALLOWED_OTHER[1] + 1) if multi_conference else [0]
	for gd in range(ALLOWED_DIVISION[0], ALLOWED_DIVISION[1] + 1):
		for gc in range(ALLOWED_CONFERENCE[0], ALLOWED_CONFERENCE[1] + 1):
			for go in other_values:
				var r := FcSeasonRules.new()
				r.games_per_division_opponent = gd
				r.games_per_conference_opponent = gc
				r.games_per_other_conference_opponent = go
				var games := r.games_per_team(league)
				if games < MIN_GAMES_PER_TEAM or games > MAX_GAMES_PER_TEAM:
					continue
				var score := absf(games - target_games)
				score += 6.0 * _outside(gd, RECOMMENDED_DIVISION)
				score += 6.0 * _outside(gc, RECOMMENDED_CONFERENCE)
				if multi_conference:
					score += 6.0 * _outside(go, RECOMMENDED_OTHER)
				if score < best_score:
					best_score = score
					best = r
	return best


static func _outside(value: int, recommended: Array) -> int:
	return 0 if value >= recommended[0] and value <= recommended[1] else 1


static func _check_range(errors: Array[String], label: String, value: int, bounds: Array) -> void:
	if value < bounds[0] or value > bounds[1]:
		errors.append("%s must be %d-%d" % [label, bounds[0], bounds[1]])


static func _note_range(notes: Array[String], label: String, value: int, recommended: Array) -> void:
	if value != 0 and (value < recommended[0] or value > recommended[1]):
		notes.append("%d games per %s is outside the recommended %d-%d" % [value, label, recommended[0], recommended[1]])
