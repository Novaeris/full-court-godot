class_name FcPlayoffRules
extends RefCounted
## The post-season format. Three independent choices:
##
## QUALIFICATION (who gets in) -- `qualification`
##   "division_leaders": every division winner qualifies automatically and
##       takes the top seeds; the remaining places go to the best records.
##   "seeding": like college seeding -- the best records get in, regardless
##       of division. No division guarantee.
##
## BRACKET (how teams are drawn) -- `bracket`
##   "conference": each conference has its own bracket (its share of the
##       qualifiers), and the conference champions then meet.
##   "league": one bracket for the whole league, seeded 1..N by record.
##
## SERIES LENGTH -- `series_lengths`: best-of-1/3/5/7 for each round, first
## round first. The number of rounds follows from the bracket size.
## If a bracket is not a power of two (e.g. 6 teams), the top seeds get byes
## in the first round.
##
## `team_count` is the TOTAL number of qualifying teams.

const QUALIFICATIONS := ["division_leaders", "seeding"]
const BRACKETS := ["conference", "league"]
const SERIES_OPTIONS := [1, 3, 5, 7]

var qualification: String = "division_leaders"
var bracket: String = "conference"
var team_count: int = 16
var series_lengths: Array[int] = [5, 7, 7, 7]


## Number of rounds for this league's structure.
func round_count(league: FcLeague) -> int:
	var conferences := maxi(1, league.conferences.size())
	if bracket == "conference":
		return _ceil_log2(floori(float(team_count) / conferences)) + _ceil_log2(conferences)
	return _ceil_log2(team_count)


## Teams per bracket: per conference for a conference bracket, else the whole league.
func bracket_size(league: FcLeague) -> int:
	if bracket == "conference":
		return floori(float(team_count) / maxi(1, league.conferences.size()))
	return team_count


## First-round byes per bracket (top seeds skip round 1 when the size is not a power of two).
func byes_per_bracket(league: FcLeague) -> int:
	var size := bracket_size(league)
	return _next_power_of_two(size) - size


func validate(league: FcLeague) -> Array[String]:
	var errors: Array[String] = []
	if not QUALIFICATIONS.has(qualification):
		errors.append("playoff qualification must be one of %s" % str(QUALIFICATIONS))
	if not BRACKETS.has(bracket):
		errors.append("playoff bracket must be one of %s" % str(BRACKETS))
	if not errors.is_empty():
		return errors
	var teams := league.team_count()
	var conferences := league.conferences.size()
	if team_count < 2:
		errors.append("the playoffs need at least 2 teams")
	if team_count > teams:
		errors.append("%d playoff teams is more than the league's %d teams" % [team_count, teams])
	if not errors.is_empty():
		return errors

	var per_bracket := bracket_size(league)
	if bracket == "conference":
		if team_count % conferences != 0:
			errors.append("%d playoff teams cannot be split evenly across %d conferences" % [team_count, conferences])
			return errors
		if per_bracket < 2:
			errors.append("each conference needs at least 2 playoff teams")
		for c in league.conferences:
			var conference_teams := 0
			for d in c.divisions:
				conference_teams += d.team_ids.size()
			if per_bracket > conference_teams:
				errors.append("conference '%s' has only %d teams but %d playoff spots" % [c.name, conference_teams, per_bracket])
			if qualification == "division_leaders" and per_bracket < c.divisions.size():
				errors.append("conference '%s' has %d divisions, so at least %d playoff spots per conference are needed for every division leader to qualify" % [c.name, c.divisions.size(), c.divisions.size()])
	elif qualification == "division_leaders" and team_count < league.all_divisions().size():
		errors.append("%d divisions need at least %d playoff spots so every division leader qualifies" % [league.all_divisions().size(), league.all_divisions().size()])

	var rounds := round_count(league)
	if series_lengths.size() != rounds:
		errors.append("this format has %d rounds but %d series lengths were given" % [rounds, series_lengths.size()])
	for s in series_lengths:
		if not SERIES_OPTIONS.has(s):
			errors.append("series length %d is not allowed (use best of 1, 3, 5 or 7)" % s)
	return errors


## Plain-language description, one line per round.
func describe(league: FcLeague) -> Array[String]:
	var lines: Array[String] = []
	var qual := "division leaders qualify automatically and take the top seeds" if qualification == "division_leaders" else "the best records qualify (pure seeding)"
	lines.append("%d teams qualify: %s" % [team_count, qual])
	lines.append("%s; %d round%s" % [
		("each conference has its own bracket of %d, then the conference champions meet" % bracket_size(league)) if bracket == "conference" and league.conferences.size() > 1
		else "one bracket seeded 1-%d by record" % bracket_size(league),
		round_count(league), "" if round_count(league) == 1 else "s"])
	if byes_per_bracket(league) > 0:
		lines.append("%d top seed%s per bracket get a first-round bye" % [byes_per_bracket(league), "" if byes_per_bracket(league) == 1 else "s"])
	for i in series_lengths.size():
		lines.append("Round %d: best of %d" % [i + 1, series_lengths[i]])
	return lines


func to_dict() -> Dictionary:
	return {
		"qualification": qualification, "bracket": bracket,
		"team_count": team_count, "series_lengths": series_lengths.duplicate(),
	}


static func from_dict(data: Dictionary) -> FcPlayoffRules:
	var r := FcPlayoffRules.new()
	r.qualification = str(data.get("qualification", r.qualification))
	r.bracket = str(data.get("bracket", r.bracket))
	r.team_count = int(data.get("team_count", r.team_count))
	r.series_lengths = []
	for s in data.get("series_lengths", [5, 7, 7, 7]):
		r.series_lengths.append(int(s))
	return r


## A sensible format for this league: about half the teams qualify (a power
## of two), division leaders get in, conference brackets when the numbers
## split evenly, short early rounds and best-of-7 later.
static func suggest(league: FcLeague) -> FcPlayoffRules:
	var r := FcPlayoffRules.new()
	var teams := league.team_count()
	var divisions := league.all_divisions().size()
	var conferences := maxi(1, league.conferences.size())
	var target := _prev_power_of_two(maxi(2, ceili(teams * 0.55)))
	target = maxi(target, _next_power_of_two(divisions))
	target = mini(target, _prev_power_of_two(teams))
	r.team_count = maxi(2, target)
	r.qualification = "division_leaders"
	if conferences > 1 and r.team_count % conferences == 0 and floori(float(r.team_count) / conferences) >= 2:
		r.bracket = "conference"
	else:
		r.bracket = "league"
	var rounds := r.round_count(league)
	r.series_lengths = []
	for i in rounds:
		if rounds == 1:
			r.series_lengths.append(7)
		elif i == 0 and rounds >= 3:
			r.series_lengths.append(5)
		elif i == 0:
			r.series_lengths.append(5)
		else:
			r.series_lengths.append(7)
	return r


static func _ceil_log2(n: int) -> int:
	var rounds := 0
	var v := 1
	while v < n:
		v *= 2
		rounds += 1
	return rounds


static func _next_power_of_two(n: int) -> int:
	var v := 1
	while v < n:
		v *= 2
	return v


static func _prev_power_of_two(n: int) -> int:
	var v := 1
	while v * 2 <= n:
		v *= 2
	return v
