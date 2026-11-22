class_name FcDynastyMatch
extends RefCounted
## Turns Dynasty rosters into the existing simulation's input and the simulation's box score into a plain summary.
## The simulator knows nothing about Dynasty: it receives two FcGameTeam and returns an FcBoxScore.
##
## How the roster maps: the 13 slots become the team's players in slot order; the five starters get a large `role_bonus` so
## the simulator's own starting-five choice picks exactly them; each slot's rotation setting becomes the simulation's
## `minutes_pref`; a card's badges become the (capped) composite bonuses the Career rules already define.

const STARTER_BONUS := 1000.0
const USER_TEAM_ID := 1
const OPPONENT_TEAM_ID := 2
## Simulated players get ids base + slot + 1; the user's base is 0, the opponent's 100.
const OPPONENT_ID_BASE := 100


## Returns {"team": FcGameTeam, "cards": {sim player id: card_id}}.
static func build_team(slots: Array, minutes: Array, catalog: FcDynastyCatalog, team_id: int, team_name: String,
		abbreviation: String, id_base: int) -> Dictionary:
	var g := FcGameTeam.new()
	g.team_id = team_id
	g.name = team_name
	g.abbreviation = abbreviation
	var cards := {}
	for slot in slots.size():
		var card_id := str(slots[slot])
		if card_id == "" or not catalog.has_card(card_id):
			continue
		var pid := id_base + slot + 1
		var player := catalog.make_player(card_id, pid)
		var role := {"role_bonus": STARTER_BONUS if slot < FcDynastyRoster.STARTERS else 0.0,
			"minutes_pref": float(minutes[slot]) if slot < minutes.size() else 0.0}
		g.players.append(FcSimPlayer.new(player, catalog.ratings, team_id, catalog.composite_bonus(card_id), role))
		cards[pid] = card_id
	return {"team": g, "cards": cards}


## Plays one game with the existing simulator. `seed_value` makes it reproducible. Returns the FcBoxScore
## (side 0 = home) wrapped with the card map: {"box", "user_side", "cards"}.
static func simulate(user: Dictionary, opponent: Dictionary, seed_value: int, user_home: bool = true) -> Dictionary:
	var home: Dictionary = user if user_home else opponent
	var away: Dictionary = opponent if user_home else user
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()   # the play-by-play of the game (read-only; the box score is the same with or without it)
	var box := sim.simulate(home["team"], away["team"], FcRng.new(seed_value))
	var cards: Dictionary = user["cards"].duplicate()
	cards.merge(opponent["cards"])
	return {"box": box, "user_side": 0 if user_home else 1, "cards": cards, "events": sim.recorder.to_dict()}


## The plain facts of a finished game from the user's point of view (see FcDynastyChallenges for what is counted).
static func summarize(played: Dictionary) -> Dictionary:
	var box: FcBoxScore = played["box"]
	var us: int = played["user_side"]
	var them := 1 - us
	var totals := box.team_totals(us)
	var lines: Array = []
	for p in box.players_of(us):
		lines.append({
			"card_id": str(played["cards"].get(p.player_id, "")), "name": p.name, "started": p.started,
			"seconds": p.seconds, "points": p.points, "rebounds": p.rebounds(), "assists": p.ast, "steals": p.stl,
			"blocks": p.blk, "threes": p.tpm, "free_throws": p.ftm,
		})
	return {
		"won": box.scores[us] > box.scores[them], "score_for": box.scores[us], "score_against": box.scores[them],
		"margin": box.scores[us] - box.scores[them], "overtimes": box.overtimes,
		"opponent": box.team_names[them], "home": us == 0,
		"team": {"points": totals["points"], "rebounds": totals["oreb"] + totals["dreb"], "assists": totals["ast"],
			"steals": totals["stl"], "blocks": totals["blk"], "threes": totals["tpm"], "free_throws": totals["ftm"]},
		"players": lines,
	}
