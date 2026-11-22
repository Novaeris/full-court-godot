class_name FcReplayModel
extends RefCounted
## The view-model of a game replay: the play-by-play entries (FcPlayByPlay) plus, for every event, who has the ball side, which way
## they attack, who is on court and every player's points and fouls so far. Pure and read-only: the replay screen asks it "what is the
## picture at event i?" and steps through it. No nodes, no random numbers.

const FILTER_ALL := "all"
const FILTER_KEY := "key"
const FILTER_SCORING := "scoring"

## Seconds each kind of event stays on screen at normal speed.
const DWELL := {
	FcGameEventLog.EV_SHOT_MADE: 1.5, FcGameEventLog.EV_SHOT_MISSED: 1.2, FcGameEventLog.EV_SHOT_BLOCKED: 1.3,
	FcGameEventLog.EV_REBOUND: 0.8, FcGameEventLog.EV_TURNOVER: 1.1, FcGameEventLog.EV_FOUL: 1.0,
	FcGameEventLog.EV_FREE_THROW: 1.0, FcGameEventLog.EV_SUBSTITUTION: 0.6, FcGameEventLog.EV_INJURY: 1.6,
	FcGameEventLog.EV_PERIOD_START: 1.2, FcGameEventLog.EV_PERIOD_END: 1.2, FcGameEventLog.EV_GAME_END: 1.5,
}

var box: FcBoxScore
var entries: Array[Dictionary] = []
var quarters: int = 4
var _offense: Array[int] = []
var _points: Array = []     # per event: {player id: points so far}
var _fouls: Array = []      # per event: {player id: personal fouls so far}
var _team_fouls: Array = [] # per event: [home, away] fouls in the current period
var _positions: Dictionary = {}


## Builds the model for one game. An empty or missing log gives an empty model (`is_empty()`), never an error.
static func build(log: FcGameEventLog, game_box: FcBoxScore, quarter_count: int = 4) -> FcReplayModel:
	var m := FcReplayModel.new()
	m.box = game_box
	m.quarters = quarter_count
	if log == null or game_box == null:
		return m
	m.entries = FcPlayByPlay.entries(log, game_box, quarter_count)
	for p in game_box.players:
		m._positions[p.player_id] = p.position
	m._derive()
	return m


func is_empty() -> bool:
	return entries.is_empty()


func size() -> int:
	return entries.size()


## The first event worth showing: the tip-off (the starters are announced before it).
func start_index() -> int:
	for e in entries:
		if e["type"] == FcGameEventLog.EV_PERIOD_START:
			return e["index"]
	return 0


func final_index() -> int:
	return maxi(0, entries.size() - 1)


## Everything the screen needs at event `i` (clamped into range).
func state_at(i: int) -> Dictionary:
	if entries.is_empty():
		return {}
	i = clampi(i, 0, entries.size() - 1)
	var e: Dictionary = entries[i]
	var side := _offense[i]
	return {
		"index": i, "entry": e, "text": e["text"], "home": e["home"], "away": e["away"], "period": e["period"],
		"period_name": FcPlayByPlay.period_name(e["period"], quarters), "clock_text": e["clock_text"],
		"on_court": FcPlayByPlay.on_court(entries, i), "offense_side": side,
		"attacks_right": FcCourtLayout.attacks_right(side, e["period"]),
		"points": _points[i], "fouls": _fouls[i], "team_fouls": _team_fouls[i], "positions": _positions,
	}


## The score line and clock as a scoreboard shows it: "Q2 4:31".
func status_at(i: int) -> String:
	if entries.is_empty():
		return ""
	var e: Dictionary = entries[clampi(i, 0, entries.size() - 1)]
	if e["type"] == FcGameEventLog.EV_GAME_END:
		return "FINAL" if box.overtimes == 0 else "FINAL/OT"
	var p: int = e["period"]
	var label := "Q%d" % p if p <= quarters else ("OT" if p == quarters + 1 else "OT%d" % (p - quarters))
	return "%s %s" % [label, e["clock_text"]]


## Whether event `i` is shown when the feed is filtered ("all", "key" plays or only "scoring").
func shown_in(i: int, filter: String) -> bool:
	var e: Dictionary = entries[i]
	if not e["visible"]:
		return false
	if filter == FILTER_ALL:
		return true
	var type: int = e["type"]
	if type == FcGameEventLog.EV_SHOT_MADE or (type == FcGameEventLog.EV_FREE_THROW and e["x"] == 1):
		return true
	if filter == FILTER_SCORING:
		return type == FcGameEventLog.EV_PERIOD_START or type == FcGameEventLog.EV_GAME_END
	return [FcGameEventLog.EV_SHOT_BLOCKED, FcGameEventLog.EV_INJURY, FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_PERIOD_END,
		FcGameEventLog.EV_GAME_END].has(type) or (type == FcGameEventLog.EV_TURNOVER and e["b"] != 0) \
		or (type == FcGameEventLog.EV_FOUL and e["x"] != FcGameEventLog.FOUL_PERSONAL)


## The indices a filtered feed shows, in order.
func indices_for(filter: String) -> Array[int]:
	var out: Array[int] = []
	for i in entries.size():
		if shown_in(i, filter):
			out.append(i)
	return out


## The next shown event after (direction 1) or before (-1) `from`, or `from` itself when there is none.
func step(from: int, direction: int, filter: String) -> int:
	var i := from + direction
	while i >= 0 and i < entries.size():
		if shown_in(i, filter):
			return i
		i += direction
	return from


func period_start_index(period: int) -> int:
	return FcPlayByPlay.period_start_index(entries, period)


## The periods that were played (1..4, then overtimes).
func periods() -> Array[int]:
	var out: Array[int] = []
	for e in entries:
		if e["type"] == FcGameEventLog.EV_PERIOD_START:
			out.append(e["x"])
	return out


## Seconds an event stays up at normal speed (the screen divides by the chosen speed).
func dwell(i: int) -> float:
	return float(DWELL.get(entries[clampi(i, 0, entries.size() - 1)]["type"], 0.6))


# --- derivation ----------------------------------------------------------------------------------------------------------

func _derive() -> void:
	var known: Array[int] = []
	for e in entries:
		var side := -1
		match e["type"]:
			FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED, FcGameEventLog.EV_TURNOVER, FcGameEventLog.EV_FREE_THROW, FcGameEventLog.EV_REBOUND:
				side = e["side"]
			FcGameEventLog.EV_FOUL:
				side = 1 - int(e["side"])
		known.append(side)
	# events with no side of their own (substitutions, period markers) take the side of the next possession-defining event,
	# or the last one when there is none after them
	var next_known := -1
	for i in range(known.size() - 1, -1, -1):
		if known[i] >= 0:
			next_known = known[i]
		elif next_known >= 0:
			known[i] = next_known
	var last := 0
	for i in known.size():
		if known[i] >= 0:
			last = known[i]
		else:
			known[i] = last
	_offense.assign(known)
	var pts := {}
	var pf := {}
	var team_pf := [0, 0]
	for e in entries:
		match e["type"]:
			FcGameEventLog.EV_PERIOD_START:
				team_pf = [0, 0]
			FcGameEventLog.EV_SHOT_MADE:
				pts[e["a"]] = int(pts.get(e["a"], 0)) + FcGameEventLog.points_of(e["x"])
			FcGameEventLog.EV_FREE_THROW:
				if e["x"] == 1:
					pts[e["a"]] = int(pts.get(e["a"], 0)) + 1
			FcGameEventLog.EV_FOUL:
				pf[e["a"]] = int(pf.get(e["a"], 0)) + 1
				team_pf[e["side"]] += 1
		_points.append(pts.duplicate())
		_fouls.append(pf.duplicate())
		_team_fouls.append(team_pf.duplicate())
