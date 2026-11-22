class_name FcReconstructor
extends RefCounted
## Reconstructs plausible movement from the recorded events (master plan B1, the feasibility spike). The simulation has NO spatial model, so
## everything this produces is PRESENTATION: a deterministic reconstruction that explains the recorded events, never a record of where
## anyone really was, and every result is labelled `reconstructed = true`. It reads the timeline only and writes nothing back, and it uses no
## random numbers and no clock: the same events always give the same keyframes (jitter comes from a hash of the events themselves).
##
## One or more KEYFRAMES per event: {event (row index), kind, t (seconds on the reconstruction's own time axis), players {id: Vector2 feet},
## ball (Vector3: x, y along the court, z up), holder (player id, 0 while the ball is in flight)}. The ball interactions are the plan's model:
##   hold (carried by a named player), pass (reconstruction-level: it exists only to explain an assisted basket, it is not a recorded pass),
##   shot_made / shot_missed / shot_blocked / ft_shot (in flight), rebound (taken by a player), loose (a steal or a team rebound), dead (a
##   whistle, a substitution, a period boundary: the ball stays where it is).
## Time axis: each step lasts as long as the fastest player or the ball needs at the speed limits below (at least MIN_DT), so no one ever
## exceeds them. That is stretched relative to the game clock when the recorded clock leaves too little time (a steal and a layup at the
## other end two seconds later): the spike measures how often (tools/reconstruct_spike.ps1) because that is what decides if the idea is credible.
##
## Limits (decision D-069, chosen from physics and the sampled gaps): a sprinting player about 22 ft/s, a pass or shot about 45 ft/s.

const PLAYER_SPEED_LIMIT := 22.0
const BALL_SPEED_LIMIT := 45.0
const MIN_DT := 0.4
const MIN_SPACING := 1.5
const HELD_HEIGHT := 3.0
const RIM_HEIGHT := 10.0
const COURT_MARGIN := 0.5
const JITTER_FEET := 3.0

const KIND_HOLD := "hold"
const KIND_PASS := "pass"
const KIND_SHOT_MADE := "shot_made"
const KIND_SHOT_MISSED := "shot_missed"
const KIND_SHOT_BLOCKED := "shot_blocked"
const KIND_FT_SHOT := "ft_shot"
const KIND_REBOUND := "rebound"
const KIND_LOOSE := "loose"
const KIND_DEAD := "dead"


## {"reconstructed": true, "seed", "keyframes": [...]} for a timeline (empty keyframes for an empty game). Starts at the tip-off.
static func build(timeline: FcBroadcastTimeline) -> Dictionary:
	var out := {"reconstructed": true, "seed": 0, "keyframes": []}
	if timeline == null or timeline.is_empty():
		return out
	var model := timeline.model
	var seed_value := _seed(model)
	out["seed"] = seed_value
	var keyframes: Array = out["keyframes"]
	var court: Array = [[], []]
	var positions := {}
	var ball := Vector3(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0, HELD_HEIGHT)
	var holder := 0
	var t := 0.0
	var tip_off := model.start_index()
	for i in model.size():
		var e: Dictionary = model.entries[i]
		match int(e["type"]):
			FcGameEventLog.EV_STARTER:
				court[int(e["side"])].append(int(e["a"]))
			FcGameEventLog.EV_SUBSTITUTION:
				var list: Array = court[int(e["side"])]
				var at := list.find(int(e["b"]))
				if at >= 0:
					list[at] = int(e["a"])
				else:
					list.append(int(e["a"]))
		if i < tip_off:
			continue
		var state := model.state_at(i)
		var targets := _targets(e, i, court, state, model.box, positions, seed_value)
		var specs := _specs(e, state, court, targets, ball, holder, model.box)
		var first := true
		for spec in specs:
			var spec_ball: Vector3 = spec["ball"]
			var steps := 0.0
			if first:
				for pid in targets:
					steps = maxf(steps, (positions.get(pid, targets[pid]) as Vector2).distance_to(targets[pid]))
				positions = targets.duplicate()   # only the ten on court now: a player who went to the bench is no longer placed
			var dt := maxf(MIN_DT, maxf(steps / PLAYER_SPEED_LIMIT, (ball - spec_ball).length() / BALL_SPEED_LIMIT))
			t += dt
			ball = spec_ball
			holder = int(spec["holder"])
			keyframes.append({"event": i, "kind": str(spec["kind"]), "t": t, "players": positions.duplicate(), "ball": ball, "holder": holder})
			first = false
	return out


# --- where everyone stands at an event -----------------------------------------------------------------------------------------

static func _targets(e: Dictionary, index: int, court: Array, state: Dictionary, box: FcBoxScore, previous: Dictionary, seed_value: int) -> Dictionary:
	var offense: int = state["offense_side"]
	var right: bool = state["attacks_right"]
	var shape := FcCourtLayout.formation(right)
	var out := {}
	var ordered: Array = []
	for side in 2:
		ordered.append(FcCourtLayout.order_by_position(court[side], state["positions"]))
	for slot in 5:
		for side in 2:
			if slot < ordered[side].size():
				var base: Vector2 = shape["offense"][slot] if side == offense else shape["defense"][slot]
				var pid: int = ordered[side][slot]
				out[pid] = _clamp(base + Vector2((FcCourtLayout.unit(pid + seed_value % 997, index) - 0.5) * JITTER_FEET, (FcCourtLayout.unit(pid + seed_value % 991, index + 7) - 0.5) * JITTER_FEET))
	var hoop := FcCourtLayout.basket(right)
	var a := int(e["a"])
	var b := int(e["b"])
	match int(e["type"]):
		FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED:
			var spot := FcCourtLayout.shot_spot(int(e["x"]), index, right)
			if out.has(a):
				out[a] = spot
			if int(e["type"]) == FcGameEventLog.EV_SHOT_BLOCKED and out.has(b):
				out[b] = _clamp(spot.lerp(hoop, 0.2))
		FcGameEventLog.EV_FREE_THROW:
			if out.has(a):
				out[a] = Vector2(hoop.x + (-FcCameraDirector.FREE_THROW_LINE_FROM_BASKET if right else FcCameraDirector.FREE_THROW_LINE_FROM_BASKET), FcCourtLayout.COURT_WIDTH / 2.0)
		FcGameEventLog.EV_REBOUND:
			if a != 0 and out.has(a):
				out[a] = _clamp(hoop + Vector2(-3.0 if right else 3.0, (FcCourtLayout.unit(index, 5) - 0.5) * 8.0))
		FcGameEventLog.EV_TURNOVER:
			if b != 0 and out.has(b) and previous.has(a):
				out[b] = _clamp((previous[a] as Vector2) + Vector2(1.6, 1.6))   # the thief takes the ball from the handler's spot
	_separate(out)
	return out


## Pushes players apart until no two are closer than MIN_SPACING (deterministic: pairs in id order, a fixed number of passes).
static func _separate(positions: Dictionary) -> void:
	var ids: Array = positions.keys()
	ids.sort()
	for pass_number in 6:
		var moved := false
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var p: Vector2 = positions[ids[i]]
				var q: Vector2 = positions[ids[j]]
				var d := p.distance_to(q)
				if d >= MIN_SPACING:
					continue
				var away := (p - q).normalized() if d > 0.0001 else Vector2.from_angle(float((int(ids[i]) + int(ids[j])) % 8) * PI / 4.0)
				var push := (MIN_SPACING - d) / 2.0 + 0.02
				positions[ids[i]] = _clamp(p + away * push)
				positions[ids[j]] = _clamp(q - away * push)
				moved = true
		if not moved:
			return


static func _clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, COURT_MARGIN, FcCourtLayout.COURT_LENGTH - COURT_MARGIN), clampf(p.y, COURT_MARGIN, FcCourtLayout.COURT_WIDTH - COURT_MARGIN))


# --- what the ball does at an event --------------------------------------------------------------------------------------------

static func _specs(e: Dictionary, state: Dictionary, court: Array, targets: Dictionary, ball: Vector3, holder: int, box: FcBoxScore) -> Array:
	var right: bool = state["attacks_right"]
	var hoop := FcCourtLayout.basket(right)
	var hoop_ball := Vector3(hoop.x, hoop.y, RIM_HEIGHT)
	var a := int(e["a"])
	var b := int(e["b"])
	var in_hand := func(pid: int) -> Vector3:
		var at: Vector2 = targets[pid]
		return Vector3(at.x, at.y, HELD_HEIGHT)
	match int(e["type"]):
		FcGameEventLog.EV_SHOT_MADE:
			if not targets.has(a):
				return [_dead(ball, holder, targets)]
			var made: Array = []
			if b != 0 and targets.has(b):
				made.append({"kind": KIND_HOLD, "holder": b, "ball": in_hand.call(b)})
				made.append({"kind": KIND_PASS, "holder": a, "ball": in_hand.call(a)})
			else:
				made.append({"kind": KIND_HOLD, "holder": a, "ball": in_hand.call(a)})
			made.append({"kind": KIND_SHOT_MADE, "holder": 0, "ball": hoop_ball})
			return made
		FcGameEventLog.EV_SHOT_MISSED:
			if not targets.has(a):
				return [_dead(ball, holder, targets)]
			var away := Vector2(-2.5 if right else 2.5, 1.5)
			return [{"kind": KIND_HOLD, "holder": a, "ball": in_hand.call(a)}, {"kind": KIND_SHOT_MISSED, "holder": 0, "ball": Vector3(hoop.x + away.x, hoop.y + away.y, 7.0)}]
		FcGameEventLog.EV_SHOT_BLOCKED:
			if not targets.has(a) or not targets.has(b):
				return [_dead(ball, holder, targets)]
			var blocker: Vector2 = targets[b]
			return [{"kind": KIND_HOLD, "holder": a, "ball": in_hand.call(a)}, {"kind": KIND_SHOT_BLOCKED, "holder": 0, "ball": Vector3(blocker.x, blocker.y, 8.0)}]
		FcGameEventLog.EV_REBOUND:
			if a != 0 and targets.has(a):
				return [{"kind": KIND_REBOUND, "holder": a, "ball": in_hand.call(a)}]
			return [{"kind": KIND_LOOSE, "holder": 0, "ball": Vector3(hoop.x + (-3.0 if right else 3.0), hoop.y, 1.0)}]
		FcGameEventLog.EV_TURNOVER:
			if a != 0 and targets.has(a) and b != 0 and targets.has(b):
				return [{"kind": KIND_HOLD, "holder": a, "ball": in_hand.call(a)}, {"kind": KIND_LOOSE, "holder": b, "ball": in_hand.call(b)}]
			if a != 0 and targets.has(a):
				var at: Vector2 = targets[a]
				return [{"kind": KIND_HOLD, "holder": a, "ball": in_hand.call(a)}, {"kind": KIND_LOOSE, "holder": 0, "ball": Vector3(at.x, at.y, 1.0)}]
			return [_dead(ball, holder, targets)]
		FcGameEventLog.EV_FREE_THROW:
			if not targets.has(a):
				return [_dead(ball, holder, targets)]
			return [{"kind": KIND_HOLD, "holder": a, "ball": in_hand.call(a)}, {"kind": KIND_FT_SHOT, "holder": 0, "ball": hoop_ball}]
	return [_dead(ball, holder, targets)]


## The ball stays where it is: with its holder if he is still on court (it moves with him), otherwise where it lay.
static func _dead(ball: Vector3, holder: int, targets: Dictionary) -> Dictionary:
	if holder != 0 and targets.has(holder):
		var at: Vector2 = targets[holder]
		return {"kind": KIND_DEAD, "holder": holder, "ball": Vector3(at.x, at.y, HELD_HEIGHT)}
	return {"kind": KIND_DEAD, "holder": 0, "ball": ball}


## The presentation seed: made only from facts the game already holds (the scores and teams), so no new data is saved.
static func _seed(model: FcReplayModel) -> int:
	return absi(hash("%s|%s|%d" % [str(model.box.team_ids), str(model.box.scores), model.size()])) % 2147483647
