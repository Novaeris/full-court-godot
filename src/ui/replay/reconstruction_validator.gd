class_name FcReconstructionValidator
extends RefCounted
## Checks a reconstruction (FcReconstructor) against the recorded game and against the plan's own rules (master plan B1). It does NOT trust
## the reconstructor: lineups are recomputed from the play-by-play (FcPlayByPlay.on_court), and every other rule is a fresh measurement of
## the keyframes. Pure; returns readable problems, empty = valid.
##
## Rules: labelled reconstructed; every event from the tip-off has a keyframe, in order, with time strictly forward; exactly the five players
## the play-by-play puts on court per side, at every keyframe; everyone and the ball inside the court; no two players closer than
## MIN_SPACING; no player or ball faster than the limits between keyframes (so no unexplained jump); a ball with a holder is in his hands, a
## ball in flight has no holder; a change of holder only at a defined interaction; each recorded event has the interaction it calls for.

const EPSILON := 0.0001


static func validate(timeline: FcBroadcastTimeline, result: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if timeline == null or timeline.is_empty():
		if not (result.get("keyframes", []) as Array).is_empty():
			problems.append("an empty game has keyframes")
		return problems
	if result.get("reconstructed", false) != true:
		problems.append("the result is not labelled reconstructed")
	var keyframes: Array = result.get("keyframes", [])
	if keyframes.is_empty():
		problems.append("no keyframes")
		return problems
	var entries := timeline.model.entries
	var tip_off := timeline.model.start_index()
	var next_event := tip_off
	var previous: Dictionary = {}
	for k in keyframes.size():
		var f: Dictionary = keyframes[k]
		var event := int(f["event"])
		var where := "keyframe %d (event %d, %s)" % [k, event, str(f["kind"])]
		if event < next_event - 1 or event > next_event:
			problems.append("%s: events are not visited in order (expected %d)" % [where, next_event])
		next_event = maxi(next_event, event + 1)
		if not previous.is_empty() and float(f["t"]) <= float(previous["t"]):
			problems.append("%s: time does not move forward" % where)
		_check_lineup(f, entries, event, where, problems)
		_check_bounds(f, where, problems)
		_check_spacing(f, where, problems)
		_check_ball_and_holder(f, where, problems)
		if not previous.is_empty():
			_check_motion(previous, f, where, problems)
		previous = f
	if next_event != entries.size():
		problems.append("the last event reached was %d of %d" % [next_event - 1, entries.size() - 1])
	_check_interactions(entries, keyframes, tip_off, problems)
	return problems


static func _check_lineup(f: Dictionary, entries: Array[Dictionary], event: int, where: String, problems: Array[String]) -> void:
	var court := FcPlayByPlay.on_court(entries, event)
	var players: Dictionary = f["players"]
	var expected := {}
	for side in 2:
		if (court[side] as Array).size() != 5:
			problems.append("%s: the play-by-play has %d on court for side %d" % [where, (court[side] as Array).size(), side])
		for pid in court[side]:
			expected[int(pid)] = true
	if players.size() != expected.size():
		problems.append("%s: %d players placed, %d on court" % [where, players.size(), expected.size()])
	for pid in expected:
		if not players.has(pid):
			problems.append("%s: player %d is on court but not placed" % [where, pid])
	for pid in players:
		if not expected.has(int(pid)):
			problems.append("%s: player %d is placed but not on court" % [where, int(pid)])


static func _check_bounds(f: Dictionary, where: String, problems: Array[String]) -> void:
	for pid in f["players"]:
		var p: Vector2 = f["players"][pid]
		if p.x < -EPSILON or p.y < -EPSILON or p.x > FcCourtLayout.COURT_LENGTH + EPSILON or p.y > FcCourtLayout.COURT_WIDTH + EPSILON:
			problems.append("%s: player %d is off the court at %s" % [where, int(pid), str(p)])
	var ball: Vector3 = f["ball"]
	if ball.x < -EPSILON or ball.y < -EPSILON or ball.x > FcCourtLayout.COURT_LENGTH + EPSILON or ball.y > FcCourtLayout.COURT_WIDTH + EPSILON or ball.z < -EPSILON or ball.z > 12.0:
		problems.append("%s: the ball is outside the court or the air above it at %s" % [where, str(ball)])


static func _check_spacing(f: Dictionary, where: String, problems: Array[String]) -> void:
	var ids: Array = (f["players"] as Dictionary).keys()
	ids.sort()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := (f["players"][ids[i]] as Vector2).distance_to(f["players"][ids[j]])
			if d < FcReconstructor.MIN_SPACING - 0.01:
				problems.append("%s: players %d and %d overlap (%.2f ft apart)" % [where, int(ids[i]), int(ids[j]), d])


static func _check_ball_and_holder(f: Dictionary, where: String, problems: Array[String]) -> void:
	var holder := int(f["holder"])
	var ball: Vector3 = f["ball"]
	var kind := str(f["kind"])
	if holder != 0:
		if not (f["players"] as Dictionary).has(holder):
			problems.append("%s: the holder %d is not on court" % [where, holder])
		else:
			var hands: Vector2 = f["players"][holder]
			if Vector2(ball.x, ball.y).distance_to(hands) > 0.001 or absf(ball.z - FcReconstructor.HELD_HEIGHT) > 0.001:
				problems.append("%s: the ball is not in the holder's hands" % where)
	elif [FcReconstructor.KIND_HOLD, FcReconstructor.KIND_PASS, FcReconstructor.KIND_REBOUND].has(kind):
		problems.append("%s: a %s has no holder" % [where, kind])
	if holder != 0 and [FcReconstructor.KIND_SHOT_MADE, FcReconstructor.KIND_SHOT_MISSED, FcReconstructor.KIND_SHOT_BLOCKED, FcReconstructor.KIND_FT_SHOT].has(kind):
		problems.append("%s: a ball in flight has a holder" % where)


static func _check_motion(previous: Dictionary, f: Dictionary, where: String, problems: Array[String]) -> void:
	var dt := float(f["t"]) - float(previous["t"])
	if dt <= 0.0:
		return
	for pid in f["players"]:
		if previous["players"].has(pid):
			var speed := (previous["players"][pid] as Vector2).distance_to(f["players"][pid]) / dt
			if speed > FcReconstructor.PLAYER_SPEED_LIMIT + 0.01:
				problems.append("%s: player %d moves at %.1f ft/s (limit %.0f)" % [where, int(pid), speed, FcReconstructor.PLAYER_SPEED_LIMIT])
	var ball_speed := (previous["ball"] as Vector3).distance_to(f["ball"]) / dt
	if ball_speed > FcReconstructor.BALL_SPEED_LIMIT + 0.01:
		problems.append("%s: the ball jumps at %.1f ft/s (limit %.0f)" % [where, ball_speed, FcReconstructor.BALL_SPEED_LIMIT])
	if int(f["holder"]) != int(previous["holder"]) and not [FcReconstructor.KIND_HOLD, FcReconstructor.KIND_PASS, FcReconstructor.KIND_REBOUND, FcReconstructor.KIND_LOOSE].has(str(f["kind"])):
		if not (int(f["holder"]) == 0 and str(f["kind"]).begins_with("shot")) and not (int(f["holder"]) == 0 and str(f["kind"]) == FcReconstructor.KIND_FT_SHOT) and not (int(f["holder"]) == 0 and str(f["kind"]) == FcReconstructor.KIND_DEAD):
			problems.append("%s: the ball changed hands without a pass, rebound or steal" % where)


## Each recorded event ends in the interaction it calls for (a made basket in a made shot, an assist in a pass from the assister, ...).
static func _check_interactions(entries: Array[Dictionary], keyframes: Array, tip_off: int, problems: Array[String]) -> void:
	var by_event := {}
	for f in keyframes:
		if not by_event.has(int(f["event"])):
			by_event[int(f["event"])] = []
		(by_event[int(f["event"])] as Array).append(f)
	for i in range(tip_off, entries.size()):
		if not by_event.has(i):
			problems.append("event %d has no keyframe" % i)
			continue
		var list: Array = by_event[i]
		var e := entries[i]
		var last: Dictionary = list[list.size() - 1]
		var kinds: Array = list.map(func(f: Dictionary) -> String: return str(f["kind"]))
		match int(e["type"]):
			FcGameEventLog.EV_SHOT_MADE:
				if str(last["kind"]) != FcReconstructor.KIND_SHOT_MADE:
					problems.append("event %d: a made shot does not end in a made shot" % i)
				if int(e["b"]) != 0:
					if not kinds.has(FcReconstructor.KIND_PASS):
						problems.append("event %d: an assisted basket has no pass" % i)
					elif int(list[kinds.find(FcReconstructor.KIND_PASS)]["holder"]) != int(e["a"]) or int(list[0]["holder"]) != int(e["b"]):
						problems.append("event %d: the pass does not go from the assister to the shooter" % i)
				elif kinds.has(FcReconstructor.KIND_PASS):
					problems.append("event %d: an unassisted basket has a pass" % i)
			FcGameEventLog.EV_SHOT_MISSED:
				if str(last["kind"]) != FcReconstructor.KIND_SHOT_MISSED:
					problems.append("event %d: a miss does not end in a missed shot" % i)
			FcGameEventLog.EV_SHOT_BLOCKED:
				if str(last["kind"]) != FcReconstructor.KIND_SHOT_BLOCKED:
					problems.append("event %d: a block does not end in a blocked shot" % i)
			FcGameEventLog.EV_FREE_THROW:
				if str(last["kind"]) != FcReconstructor.KIND_FT_SHOT:
					problems.append("event %d: a free throw is not a free-throw shot" % i)
			FcGameEventLog.EV_REBOUND:
				if int(e["a"]) != 0 and (str(last["kind"]) != FcReconstructor.KIND_REBOUND or int(last["holder"]) != int(e["a"])):
					problems.append("event %d: the rebound is not taken by the recorded player" % i)
			FcGameEventLog.EV_TURNOVER:
				if int(e["b"]) != 0 and int(last["holder"]) != int(e["b"]):
					problems.append("event %d: the steal does not end with the thief holding the ball" % i)
			FcGameEventLog.EV_FOUL, FcGameEventLog.EV_SUBSTITUTION, FcGameEventLog.EV_INJURY, FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_PERIOD_END, FcGameEventLog.EV_GAME_END:
				if str(last["kind"]) != FcReconstructor.KIND_DEAD:
					problems.append("event %d: a stoppage is not a dead ball" % i)
