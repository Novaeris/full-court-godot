class_name FcRosterNumbers
extends RefCounted
## Stored jersey numbers (D-077 C7). Every rostered player keeps `FcPlayer.jersey_number` (1-99); within a team no two players share one,
## and nobody wears a number the franchise has retired. The rule is deterministic and stores nothing else:
##   - a player keeps the number he has when it is still free on his (new) team;
##   - otherwise he takes his preferred number (FcFranchiseHistory.jersey_for, the same steady choice the broadcast used before numbers were
##     stored), moving on to the next free one (99 wraps to 1);
##   - players are served in order: those keeping their number first, then by id, so the same roster always gets the same numbers;
##   - a Career player keeps the number chosen in the creator (`pinned`), and a teammate wearing it moves.
## Called after anything that changes rosters (generation, a signing, a trade, the draft, the offseason) and once after loading an older
## save. Free agents keep their last number (it is only a preference until they join a team).

const MIN_NUMBER := 1
const MAX_NUMBER := 99


## Gives every rostered player of every team in `world` a valid number. `pinned` is {player id: number} for numbers that must not move.
## Returns how many players got a new number.
static func ensure_all(world: FcWorld, current_year: int, pinned: Dictionary = {}) -> int:
	var retired_by_team := _retired(world, current_year)
	var changed := 0
	for t in world.teams.all():
		changed += ensure_team(world, t.id, retired_by_team.get(t.id, []), pinned)
	return changed


## One team. `retired` is the list of the team's retired numbers.
static func ensure_team(world: FcWorld, team_id: int, retired: Array = [], pinned: Dictionary = {}) -> int:
	var team: FcTeam = world.teams.get_by_id(team_id)
	if team == null:
		return 0
	var taken := {}
	for n in retired:
		taken[int(n)] = true
	var players: Array[FcPlayer] = []
	for pid in team.roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		if p != null:
			players.append(p)
	var changed := 0
	# pinned numbers first (a Career player's own choice), then players who already have a free number, then the rest by id
	for p in players:
		if pinned.has(p.id):
			var n := int(pinned[p.id])
			if n >= MIN_NUMBER and n <= MAX_NUMBER:
				if p.jersey_number != n:
					changed += 1
				p.jersey_number = n
				taken[n] = true
	var rest: Array[FcPlayer] = []
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: FcPlayer, b: FcPlayer) -> bool: return a.id < b.id)
	for p in sorted:
		if pinned.has(p.id):
			continue
		if p.jersey_number >= MIN_NUMBER and p.jersey_number <= MAX_NUMBER and not taken.has(p.jersey_number):
			taken[p.jersey_number] = true
		else:
			rest.append(p)
	for p in rest:
		var n := FcFranchiseHistory.jersey_for(p.id)
		var tries := 0
		while taken.has(n) and tries < MAX_NUMBER:
			n = n % MAX_NUMBER + 1
			tries += 1
		if taken.has(n):
			continue   # more than 99 players on one roster: cannot happen in a real league
		taken[n] = true
		if p.jersey_number != n:
			changed += 1
		p.jersey_number = n
	return changed


## Problems with the numbers of every team: duplicates, retired numbers worn, missing numbers. Empty when all is well (tests, integrity).
static func problems(world: FcWorld, current_year: int, pinned: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var retired_by_team := _retired(world, current_year)
	for t in world.teams.all():
		var seen := {}
		var retired: Array = retired_by_team.get(t.id, [])
		for pid in t.roster.player_ids:
			var p: FcPlayer = world.players.get_by_id(pid)
			if p == null:
				continue
			if p.jersey_number < MIN_NUMBER or p.jersey_number > MAX_NUMBER:
				out.append("%s (%s) has no number" % [p.identity.full_name(), t.identity.abbreviation])
				continue
			if seen.has(p.jersey_number):
				out.append("%s: #%d is worn twice" % [t.identity.abbreviation, p.jersey_number])
			seen[p.jersey_number] = true
			if retired.has(p.jersey_number) and not pinned.has(p.id):
				out.append("%s: #%d is retired but worn by %s" % [t.identity.abbreviation, p.jersey_number, p.identity.full_name()])
	return out


## {team id: [retired numbers]} for every league in the world.
static func _retired(world: FcWorld, current_year: int) -> Dictionary:
	var out := {}
	for league in world.leagues.all():
		var history := FcFranchiseHistory.new(world, league.id)
		var all := history.retired_numbers_all(current_year)
		for team_id in all:
			var numbers: Array = []
			for h in all[team_id]:
				numbers.append(int(h["number"]))
			out[int(team_id)] = numbers
	return out
