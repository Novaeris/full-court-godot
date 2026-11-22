class_name FcBroadcastTimeline
extends RefCounted
## The broadcast timeline (master plan B2): everything a TV-style graphic needs to say about the game at event `i`, worked out ONCE from
## the recorded events (through FcReplayModel) and nothing else. Pure and read-only: no nodes, no random numbers, no clock, and it never
## writes to the event log, the box score or a save, so showing a graphic can never change a game (the rows and box score are
## byte-identical before and after; tests/unit/test_broadcast_timeline.gd proves it and checks the totals against the box score).
##
## Why it exists: the replay model knows the picture at an event (possession, lineups, score, points and fouls). A scorebug, lower third
## or halftime panel also needs the running state around it: team fouls and the bonus, the current scoring run, lead changes, game
## leaders, milestones, clutch time and the time at which an event is shown. Keeping that here means every screen (the 2D replay today,
## a 3D viewer later) reads one source instead of recomputing it.
##
## What is NOT here, because the simulation has no such thing: a shot clock, timeouts, jump balls, technical fouls.

## Fouls in a period after which the OTHER team shoots free throws (data/simulation/tuning.json "bonus_fouls" is the rule the simulation uses).
const DEFAULT_BONUS_FOULS := 5
## A scoring run is worth a graphic from this many unanswered points (a presentation choice, not a basketball rule).
const RUN_DISPLAY_MIN := 8
## Clutch time is a presentation label only (decision D-069): the fourth quarter or overtime, this many seconds or fewer left, and the
## margin at most CLUTCH_MARGIN. It changes no rule and no result.
const CLUTCH_SECONDS := 300.0
const CLUTCH_MARGIN := 5
## Points totals a player is congratulated for.
const MILESTONE_POINTS := [10, 20, 30, 40, 50]

var model: FcReplayModel
var bonus_fouls: int = DEFAULT_BONUS_FOULS

var _snapshots: Array[Dictionary] = []
var _start_seconds: Array[float] = []
var _total_seconds: float = 0.0


## Builds the timeline for a replay model. `bonus_fouls` below 1 reads the simulation's own rule from its tuning file.
static func build(replay: FcReplayModel, bonus_threshold: int = 0) -> FcBroadcastTimeline:
	var t := FcBroadcastTimeline.new()
	t.model = replay
	t.bonus_fouls = bonus_threshold if bonus_threshold > 0 else int(FcGameSimulator.load_tuning().get("bonus_fouls", DEFAULT_BONUS_FOULS))
	if replay != null and not replay.is_empty():
		t._derive()
	return t


func is_empty() -> bool:
	return _snapshots.is_empty()


func size() -> int:
	return _snapshots.size()


## The state at event `i` (clamped into range), or {} for an empty game. Keys:
##   index, period, period_name, status ("Q2 4:31"), clock_text, home, away, lead (home minus away), offense_side,
##   team_fouls [home, away] in the current period, bonus_for [home, away] (that side shoots free throws on a foul),
##   run {side (-1 none), points}, lead_changes, ties, largest_lead [home, away],
##   leaders [{points, rebounds, assists} per side, each {player_id (0 none), value}],
##   milestone ({} or {player_id, side, points}), clutch (bool), seconds (when the event is shown at normal speed).
func snapshot(i: int) -> Dictionary:
	if _snapshots.is_empty():
		return {}
	return _snapshots[clampi(i, 0, _snapshots.size() - 1)]


## Seconds from the start of the replay at which event `i` is shown at normal speed (hidden events take no time).
func seconds_at(i: int) -> float:
	if _start_seconds.is_empty():
		return 0.0
	return _start_seconds[clampi(i, 0, _start_seconds.size() - 1)]


func total_seconds() -> float:
	return _total_seconds


## The event shown at `seconds` from the start (the last one that has started by then).
func index_at_seconds(seconds: float) -> int:
	if _start_seconds.is_empty():
		return 0
	var found := 0
	for i in _start_seconds.size():
		if _start_seconds[i] <= seconds:
			found = i
		else:
			break
	return found


## The first event inside clutch time, or -1 when the game never was.
func clutch_start_index() -> int:
	for i in _snapshots.size():
		if bool(_snapshots[i]["clutch"]):
			return i
	return -1


## One player's line from the start of the game through event `upto`: {points, fgm, fga, tpm, tpa, ftm, fta, oreb, dreb, reb, ast, stl,
## blk, tov, pf, team_reb}. Counted from the same rows as the box score (the test compares every player at the final event).
func player_line(upto: int, player_id: int) -> Dictionary:
	var line := _blank_line()
	for e in _entries_through(upto):
		_add_to_line(line, e, player_id, -1)
	line["reb"] = int(line["oreb"]) + int(line["dreb"])
	return line


## One team's line through event `upto` (the same fields, counted for every player of that side).
func team_line(upto: int, side: int) -> Dictionary:
	var line := _blank_line()
	for e in _entries_through(upto):
		_add_to_line(line, e, 0, side)
	line["reb"] = int(line["oreb"]) + int(line["dreb"])
	return line


# --- derivation ------------------------------------------------------------------------------------------------------------

func _entries_through(upto: int) -> Array:
	var entries := model.entries
	return entries.slice(0, clampi(upto, -1, entries.size() - 1) + 1)


static func _blank_line() -> Dictionary:
	return {"points": 0, "fgm": 0, "fga": 0, "tpm": 0, "tpa": 0, "ftm": 0, "fta": 0, "oreb": 0, "dreb": 0, "reb": 0, "team_reb": 0, "ast": 0, "stl": 0, "blk": 0, "tov": 0, "pf": 0}


## Adds one event to a line. With `side` >= 0 every player of that side counts (a team line); otherwise only `player_id`.
## A team rebound (player 0) counts for the team's rebounds only, as in the box score's team totals.
func _add_to_line(line: Dictionary, e: Dictionary, player_id: int, side: int) -> void:
	var event_side: int = e["side"]
	var a: int = e["a"]
	var b: int = e["b"]
	var mine_a := (event_side == side) if side >= 0 else (a == player_id and a != 0)
	match int(e["type"]):
		FcGameEventLog.EV_SHOT_MADE:
			if mine_a:
				line["fgm"] += 1
				line["fga"] += 1
				line["points"] += FcGameEventLog.points_of(int(e["x"]))
				if int(e["x"]) == FcGameEventLog.SHOT_THREE:
					line["tpm"] += 1
					line["tpa"] += 1
			if b != 0 and ((event_side == side) if side >= 0 else b == player_id):
				line["ast"] += 1
		FcGameEventLog.EV_SHOT_MISSED:
			if mine_a:
				line["fga"] += 1
				if int(e["x"]) == FcGameEventLog.SHOT_THREE:
					line["tpa"] += 1
		FcGameEventLog.EV_SHOT_BLOCKED:
			if mine_a:
				line["fga"] += 1
				if int(e["x"]) == FcGameEventLog.SHOT_THREE:
					line["tpa"] += 1
			if b != 0 and ((1 - event_side == side) if side >= 0 else b == player_id):
				line["blk"] += 1
		FcGameEventLog.EV_REBOUND:
			if side >= 0 and event_side == side and a == 0:
				line["team_reb"] += 1   # a team rebound belongs to no player, so the box score's team totals leave it out
			elif (event_side == side) if side >= 0 else (a == player_id and a != 0):
				line["oreb" if int(e["x"]) == 1 else "dreb"] += 1
		FcGameEventLog.EV_TURNOVER:
			if mine_a:
				line["tov"] += 1
			if b != 0 and ((1 - event_side == side) if side >= 0 else b == player_id):
				line["stl"] += 1
		FcGameEventLog.EV_FOUL:
			if mine_a:
				line["pf"] += 1
		FcGameEventLog.EV_FREE_THROW:
			if mine_a:
				line["fta"] += 1
				if int(e["x"]) == 1:
					line["ftm"] += 1
					line["points"] += 1


func _derive() -> void:
	var entries := model.entries
	var side_of := {}          # player id -> side, learned from the starters, substitutions and every event naming a player
	var points := {}
	var rebounds := {}
	var assists := {}
	var team_fouls := [0, 0]
	var run_side := -1
	var run_points := 0
	var leader := -1
	var lead_changes := 0
	var ties := 0
	var largest := [0, 0]
	var crossed := {}          # "player:threshold" -> true, so a milestone is announced once
	var clock := 0.0
	for e in entries:
		var type: int = e["type"]
		var side: int = e["side"]
		match type:
			FcGameEventLog.EV_STARTER, FcGameEventLog.EV_SUBSTITUTION:
				side_of[int(e["a"])] = side
			FcGameEventLog.EV_PERIOD_START:
				team_fouls = [0, 0]
			FcGameEventLog.EV_FOUL:
				team_fouls[side] += 1
				side_of[int(e["a"])] = side
		# running totals for the leaders
		var scorer := 0
		var scored := int(e["points"])
		if type == FcGameEventLog.EV_SHOT_MADE:
			scorer = int(e["a"])
			side_of[scorer] = side
			if int(e["b"]) != 0:
				assists[int(e["b"])] = int(assists.get(int(e["b"]), 0)) + 1
				side_of[int(e["b"])] = side
		elif type == FcGameEventLog.EV_FREE_THROW and int(e["x"]) == 1:
			scorer = int(e["a"])
			side_of[scorer] = side
		elif type == FcGameEventLog.EV_REBOUND and int(e["a"]) != 0:
			rebounds[int(e["a"])] = int(rebounds.get(int(e["a"]), 0)) + 1
			side_of[int(e["a"])] = side
		var milestone := {}
		if scorer != 0:
			var before := int(points.get(scorer, 0))
			points[scorer] = before + scored
			for threshold in MILESTONE_POINTS:
				if before < threshold and int(points[scorer]) >= threshold and not crossed.has("%d:%d" % [scorer, threshold]):
					crossed["%d:%d" % [scorer, threshold]] = true
					milestone = {"player_id": scorer, "side": side, "points": threshold}
		# the scoring run: unanswered points by one side
		if scored > 0:
			if run_side == side:
				run_points += scored
			else:
				run_side = side
				run_points = scored
		var home: int = e["home"]
		var away: int = e["away"]
		if scored > 0:
			var now_leader := 0 if home > away else (1 if away > home else -1)
			if now_leader == -1:
				ties += 1
			elif leader != -1 and now_leader != leader:
				lead_changes += 1
			if now_leader != -1:
				leader = now_leader
		largest[0] = maxi(largest[0], home - away)
		largest[1] = maxi(largest[1], away - home)
		var period: int = e["period"]
		var seconds_left: float = e["clock"]
		var clutch := period >= model.quarters and seconds_left <= CLUTCH_SECONDS and absi(home - away) <= CLUTCH_MARGIN and type != FcGameEventLog.EV_GAME_END
		_start_seconds.append(clock)
		if bool(e["visible"]):
			clock += model.dwell(int(e["index"]))
		_snapshots.append({
			"index": int(e["index"]), "period": period, "period_name": FcPlayByPlay.period_name(period, model.quarters),
			"status": model.status_at(int(e["index"])), "clock_text": str(e["clock_text"]), "home": home, "away": away, "lead": home - away,
			"offense_side": model.state_at(int(e["index"]))["offense_side"],
			"team_fouls": team_fouls.duplicate(), "bonus_for": [team_fouls[1] >= bonus_fouls, team_fouls[0] >= bonus_fouls],
			"run": {"side": run_side, "points": run_points}, "lead_changes": lead_changes, "ties": ties, "largest_lead": largest.duplicate(),
			"leaders": [_leaders(0, side_of, points, rebounds, assists), _leaders(1, side_of, points, rebounds, assists)],
			"milestone": milestone, "clutch": clutch, "seconds": _start_seconds[_start_seconds.size() - 1]})
	_total_seconds = clock


## The leader of each category for one side (ties go to the lower player id, so the answer never depends on iteration order).
static func _leaders(side: int, side_of: Dictionary, points: Dictionary, rebounds: Dictionary, assists: Dictionary) -> Dictionary:
	return {"points": _best(side, side_of, points), "rebounds": _best(side, side_of, rebounds), "assists": _best(side, side_of, assists)}


static func _best(side: int, side_of: Dictionary, totals: Dictionary) -> Dictionary:
	var best_id := 0
	var best := 0
	for pid in totals:
		if int(side_of.get(pid, -1)) != side:
			continue
		var v := int(totals[pid])
		if v > best or (v == best and best_id != 0 and int(pid) < best_id):
			best = v
			best_id = int(pid)
	return {"player_id": best_id, "value": best}
