class_name FcLeagueStructure
extends RefCounted
## Which league layouts "make sense" for a given number of teams.
## When a league is CREATED, every division must have the same number of
## teams and every conference the same number of divisions, so schedules and
## playoffs are fair. (Inside a saved game, expansion can temporarily make
## divisions uneven; that is allowed there.)
##
## A layout is valid when: conferences 1-4, divisions per conference 1-8,
## teams per division 3-8, and conferences x divisions x teams-per-division
## equals the team count. Small leagues (4-8 teams) may be one division. So some team counts (e.g. 11, 13, 17, 19, 22, 23, 26, 29, 31) have
## no valid layout and cannot be created.

const MAX_TEAMS_AT_CREATION := 64
## A saved league can grow (expansion) up to this many teams.
const MAX_TEAMS_IN_SAVE := 100
## Smaller leagues cannot play a season of at least 10 games (a team can meet
## each opponent at most 4 times).
const MIN_TEAMS := 4
const MAX_CONFERENCES := 4
const MAX_DIVISIONS_PER_CONFERENCE := 8
const MIN_DIVISION_SIZE := 3
const MAX_DIVISION_SIZE := 8


## Every valid layout for this team count, most natural first.
static func valid_structures(team_count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if team_count < MIN_TEAMS or team_count > MAX_TEAMS_AT_CREATION:
		return out
	for c in range(1, MAX_CONFERENCES + 1):
		for d in range(1, MAX_DIVISIONS_PER_CONFERENCE + 1):
			var cells := c * d
			if team_count % cells != 0:
				continue
			var size := floori(float(team_count) / cells)
			var small_league := c == 1 and d == 1 and size >= MIN_TEAMS and size <= MAX_DIVISION_SIZE
			if small_league or (size >= MIN_DIVISION_SIZE and size <= MAX_DIVISION_SIZE):
				out.append({"conferences": c, "divisions_per_conference": d, "teams_per_division": size})
	# Most natural first: two conferences, divisions of about 5.
	out.sort_custom(func(a, b): return _naturalness(a) < _naturalness(b))
	return out


static func is_valid(team_count: int, conferences: int, divisions_per_conference: int) -> bool:
	for s in valid_structures(team_count):
		if s["conferences"] == conferences and s["divisions_per_conference"] == divisions_per_conference:
			return true
	return false


## The most natural layout for a team count, or an empty Dictionary if none exists.
static func suggest(team_count: int) -> Dictionary:
	var all := valid_structures(team_count)
	return all[0] if not all.is_empty() else {}


## All team counts (4-64) that can form a valid league.
static func valid_team_counts() -> Array[int]:
	var out: Array[int] = []
	for n in range(MIN_TEAMS, MAX_TEAMS_AT_CREATION + 1):
		if not valid_structures(n).is_empty():
			out.append(n)
	return out


## Human-readable layout list for an error message, e.g. "2 conferences x 3 divisions of 5 teams".
static func describe_options(team_count: int, limit: int = 4) -> String:
	var parts: Array[String] = []
	for s in valid_structures(team_count):
		if parts.size() >= limit:
			break
		parts.append("%d conference%s x %d division%s of %d teams" % [
			s["conferences"], "" if s["conferences"] == 1 else "s",
			s["divisions_per_conference"], "" if s["divisions_per_conference"] == 1 else "s",
			s["teams_per_division"]])
	return "; ".join(parts)


## The valid team counts nearest to `team_count` (for "did you mean..." messages).
static func nearest_valid_counts(team_count: int, how_many: int = 3) -> Array[int]:
	var counts := valid_team_counts()
	counts.sort_custom(func(a, b): return abs(a - team_count) < abs(b - team_count) or (abs(a - team_count) == abs(b - team_count) and a < b))
	var out: Array[int] = []
	for c in counts.slice(0, how_many):
		out.append(c)
	out.sort()
	return out


static func _naturalness(s: Dictionary) -> float:
	# Prefer 2 conferences, 3 divisions each, divisions of 5.
	return abs(s["conferences"] - 2) * 3.0 + abs(s["teams_per_division"] - 5) * 2.0 + abs(s["divisions_per_conference"] - 3) * 0.5
