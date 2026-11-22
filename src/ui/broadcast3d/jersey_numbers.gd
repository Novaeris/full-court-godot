class_name FcJerseyNumbers
extends RefCounted
## DISPLAY jersey numbers for a game (decision D-070). League players have no stored number (docs/audits S2-JER-1), and a stored franchise-tenure
## model would need a save migration that has not been undertaken. So the broadcast gives every player of a game a number by a pure,
## deterministic rule and stores nothing: a player's preferred number is the steady hashed choice FcFranchiseHistory.jersey_for(id); players are
## served in ascending id order; a number already taken (or retired for that team) moves on to the next free one (wrapping 99 to 1). The same
## roster always gets the same numbers, whatever order it is listed in, and no two teammates share a number.
##
## Limits, stated plainly: these are DISPLAY numbers, not records. They can differ from the History tab's retired-number display, and if a
## teammate who held a number leaves, the player whose preferred number collided with it may be shown a different one in a later game.

const MIN_NUMBER := 1
const MAX_NUMBER := 99


## {player id: number} for one roster. `retired` numbers are never given out. More than 99 players: the extra ones get 0 (cannot happen in a
## real game, but the loop must always end).
static func assign(player_ids: Array, retired: Array = []) -> Dictionary:
	var ids: Array = player_ids.duplicate()
	ids.sort()
	var taken := {}
	for n in retired:
		taken[int(n)] = true
	var out := {}
	for id in ids:
		var number := FcFranchiseHistory.jersey_for(int(id))
		var tries := 0
		while taken.has(number) and tries < MAX_NUMBER:
			number = number % MAX_NUMBER + 1
			tries += 1
		if taken.has(number):
			out[int(id)] = 0
			continue
		taken[number] = true
		out[int(id)] = number
	return out


## {player id: number} for every player of both teams of a box score (each team numbered separately).
static func for_box(box: FcBoxScore, retired_by_team: Dictionary = {}) -> Dictionary:
	var by_team := {}
	for p in box.players:
		if not by_team.has(p.team_id):
			by_team[p.team_id] = []
		(by_team[p.team_id] as Array).append(p.player_id)
	var out := {}
	for team_id in by_team:
		out.merge(assign(by_team[team_id], retired_by_team.get(team_id, [])))
	return out
