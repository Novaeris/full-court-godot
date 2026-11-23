class_name FcCommentaryEvents
extends RefCounted
## The structured commentary events of a game (Broadcast pass 2, M6, D-071): what each commentary ROLE could say at an event, as data, built only
## from the recorded game. Nothing here is audio or a screen; recorded voice, text to speech, captions and any future AI commentary all consume
## these same events (see FcCommentarySink), and FcCommentaryArbiter decides which one is spoken. External services are never needed.
##
## Roles: PLAY_BY_PLAY (what just happened: FcCommentary's sentences), COLOR (the analyst: a player's shooting, fouls, rebounds, a team's
## turnovers), NARRATIVE (the story: lead changes, runs, comebacks, milestones, clutch time) and ANNOUNCER (the stadium PA: baskets, fouls,
## period ends and the final score, with display jersey numbers).
##
## An event is {index, role, kind, text, priority (0 to 100), key (for repetition control), cooldown (seconds before the same key may repeat), source
## (FcPresentationEvent.SIM_RECORDED, DERIVED_FROM_RECORDED or PRESENTATION), facts (the numbers behind the text, for tests), cue (a sound to play
## first, or "")}. Every number in a line is a recorded or exactly derived fact; no line talks about speed, distance or where anyone stood.

const ROLE_PBP := "play_by_play"
const ROLE_COLOR := "color"
const ROLE_NARRATIVE := "narrative"
const ROLE_ANNOUNCER := "announcer"
const ROLES := [ROLE_PBP, ROLE_COLOR, ROLE_NARRATIVE, ROLE_ANNOUNCER]

## Who wins when two roles want the voice at once.
const ROLE_RANK := {ROLE_PBP: 4, ROLE_ANNOUNCER: 3, ROLE_NARRATIVE: 2, ROLE_COLOR: 1}

const PBP_PRIORITY := {FcGameEventLog.EV_GAME_END: 100, FcGameEventLog.EV_SHOT_MADE: 80, FcGameEventLog.EV_SHOT_BLOCKED: 75, FcGameEventLog.EV_TURNOVER: 50,
	FcGameEventLog.EV_FREE_THROW: 55, FcGameEventLog.EV_FOUL: 60, FcGameEventLog.EV_SHOT_MISSED: 40, FcGameEventLog.EV_REBOUND: 30}
const THREE_PBP_PRIORITY := 85
const LEAD_CHANGES := [3, 5, 8, 12]
const RUN_POINTS := [12, 16, 20]
const COMEBACK_DEFICIT := 10
const REBOUND_MARKS := [8, 10, 12, 15]
const FOUL_TROUBLE := 3
const FG_EVERY := 5
const TURNOVER_EVERY := 6


## Every event the roles could voice at event `index`, in no particular order (the arbiter ranks them).
static func at(timeline: FcBroadcastTimeline, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if timeline == null or timeline.is_empty():
		return out
	index = clampi(index, 0, timeline.size() - 1)
	var ctx := _context(timeline)
	_play_by_play(timeline, index, out)
	_color(timeline, index, ctx, out)
	_narrative(timeline, index, ctx, out)
	_announcer(timeline, index, ctx, out)
	return out


static func _event(index: int, role: String, kind: String, text: String, priority: int, key: String, cooldown: float, source: String, facts: Dictionary, cue: String = "") -> Dictionary:
	return {"index": index, "role": role, "kind": kind, "text": text, "priority": priority, "key": key, "cooldown": cooldown, "source": source, "facts": facts, "cue": cue}


static func _context(timeline: FcBroadcastTimeline) -> Dictionary:
	if timeline.cache.has("commentary_context"):
		return timeline.cache["commentary_context"]
	var names := {}
	for p in timeline.model.box.players:
		names[p.player_id] = FcPlayByPlay.short_name(p.name)
	var ctx := {"names": names, "numbers": FcJerseyNumbers.for_box(timeline.model.box)}
	timeline.cache["commentary_context"] = ctx
	return ctx


static func _name(ctx: Dictionary, id: int) -> String:
	return str((ctx["names"] as Dictionary).get(id, "A player"))


static func _play_by_play(timeline: FcBroadcastTimeline, index: int, out: Array[Dictionary]) -> void:
	var text := FcCommentary.line_at(timeline, index)
	if text == "":
		return
	var e: Dictionary = timeline.model.entries[index]
	var type := int(e["type"])
	var priority: int = THREE_PBP_PRIORITY if (type == FcGameEventLog.EV_SHOT_MADE and int(e["points"]) == 3) else int(PBP_PRIORITY.get(type, 20))
	var snap := timeline.snapshot(index)
	var derived: bool = not (snap["milestone"] as Dictionary).is_empty() or (int(e["points"]) > 0 and int(snap["run"]["side"]) == int(e["side"]) and int(snap["run"]["points"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN) or index == timeline.clutch_start_index()
	out.append(_event(index, ROLE_PBP, "play", text, priority, "pbp:%d" % index, 0.0,
		FcPresentationEvent.DERIVED_FROM_RECORDED if derived else FcPresentationEvent.SIM_RECORDED, {"type": type}))


static func _color(timeline: FcBroadcastTimeline, index: int, ctx: Dictionary, out: Array[Dictionary]) -> void:
	var e: Dictionary = timeline.model.entries[index]
	var type := int(e["type"])
	var abbr: Array = timeline.model.box.abbreviations
	if type == FcGameEventLog.EV_SHOT_MADE or type == FcGameEventLog.EV_SHOT_MISSED:
		var pid := int(e["a"])
		var line := timeline.player_line(index, pid)
		var fga := int(line["fga"])
		if fga >= FG_EVERY and fga % FG_EVERY == 0:
			out.append(_event(index, ROLE_COLOR, "shooting", "%s is %d of %d from the field." % [_name(ctx, pid), int(line["fgm"]), fga], 35, "color:fg:%d:%d" % [pid, fga], 12.0,
				FcPresentationEvent.DERIVED_FROM_RECORDED, {"player_id": pid, "fgm": int(line["fgm"]), "fga": fga}))
	elif type == FcGameEventLog.EV_FOUL:
		var pid := int(e["a"])
		var pf := int(timeline.player_line(index, pid)["pf"])
		if pf >= FOUL_TROUBLE:
			out.append(_event(index, ROLE_COLOR, "foul_trouble", "%s has %d fouls." % [_name(ctx, pid), pf], 45, "color:pf:%d:%d" % [pid, pf], 12.0,
				FcPresentationEvent.DERIVED_FROM_RECORDED, {"player_id": pid, "pf": pf}))
	elif type == FcGameEventLog.EV_REBOUND and int(e["a"]) != 0:
		var pid := int(e["a"])
		var reb := int(timeline.player_line(index, pid)["reb"])
		if reb in REBOUND_MARKS:
			out.append(_event(index, ROLE_COLOR, "rebounds", "%s has %d rebounds." % [_name(ctx, pid), reb], 30, "color:reb:%d:%d" % [pid, reb], 12.0,
				FcPresentationEvent.DERIVED_FROM_RECORDED, {"player_id": pid, "reb": reb}))
	elif type == FcGameEventLog.EV_TURNOVER:
		var side := int(e["side"])
		var tov := int(timeline.team_line(index, side)["tov"])
		if tov > 0 and tov % TURNOVER_EVERY == 0:
			out.append(_event(index, ROLE_COLOR, "turnovers", "%s have turned it over %d times." % [abbr[side], tov], 28, "color:tov:%d:%d" % [side, tov], 12.0,
				FcPresentationEvent.DERIVED_FROM_RECORDED, {"side": side, "tov": tov}))


static func _narrative(timeline: FcBroadcastTimeline, index: int, ctx: Dictionary, out: Array[Dictionary]) -> void:
	var e: Dictionary = timeline.model.entries[index]
	var snap := timeline.snapshot(index)
	var abbr: Array = timeline.model.box.abbreviations
	var derived := FcPresentationEvent.DERIVED_FROM_RECORDED
	if index > 0:
		var before := timeline.snapshot(index - 1)
		if int(snap["lead_changes"]) > int(before["lead_changes"]):
			var count := int(snap["lead_changes"])
			if count in LEAD_CHANGES:
				out.append(_event(index, ROLE_NARRATIVE, "lead_changes", "That's lead change number %d." % count, 55, "narr:lc:%d" % count, 20.0, derived, {"lead_changes": count}))
			var leader := 0 if int(snap["lead"]) > 0 else 1
			var deficit := int((snap["largest_lead"] as Array)[1 - leader])
			if deficit >= COMEBACK_DEFICIT:
				out.append(_event(index, ROLE_NARRATIVE, "comeback", "%s have come back from %d down to take the lead." % [abbr[leader], deficit], 65, "narr:comeback:%d:%d" % [leader, deficit], 30.0, derived,
					{"side": leader, "deficit": deficit}))
	var run: Dictionary = snap["run"]
	if int(e["points"]) > 0 and int(run["side"]) == int(e["side"]):
		var before := int(run["points"]) - int(e["points"])
		for mark in RUN_POINTS:
			if before < mark and int(run["points"]) >= mark:   # the run has just passed this mark (a basket can jump over an exact number)
				out.append(_event(index, ROLE_NARRATIVE, "run", "%s have scored %d straight points." % [abbr[int(run["side"])], int(run["points"])], 60,
					"narr:run:%d:%d" % [int(run["side"]), mark], 20.0, derived, {"side": int(run["side"]), "points": int(run["points"])}))
				break
	var m: Dictionary = snap["milestone"]
	if not m.is_empty():
		out.append(_event(index, ROLE_NARRATIVE, "milestone", "%s has reached %d points." % [_name(ctx, int(m["player_id"])), int(m["points"])], 62,
			"narr:ms:%d:%d" % [int(m["player_id"]), int(m["points"])], 30.0, derived, {"player_id": int(m["player_id"]), "points": int(m["points"])}))
	if index == timeline.clutch_start_index() and index >= 0:
		out.append(_event(index, ROLE_NARRATIVE, "clutch", "We're in clutch time: %s %d, %s %d." % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])], 70, "narr:clutch", 600.0,
			FcPresentationEvent.PRESENTATION, {"home": int(snap["home"]), "away": int(snap["away"])}))


static func _announcer(timeline: FcBroadcastTimeline, index: int, ctx: Dictionary, out: Array[Dictionary]) -> void:
	var e: Dictionary = timeline.model.entries[index]
	var snap := timeline.snapshot(index)
	var abbr: Array = timeline.model.box.abbreviations
	var type := int(e["type"])
	var recorded := FcPresentationEvent.SIM_RECORDED
	if type == FcGameEventLog.EV_SHOT_MADE and int(e["side"]) == 0:
		var pid := int(e["a"])
		out.append(_event(index, ROLE_ANNOUNCER, "basket", "Basket by %s." % _who(ctx, pid), 45, "pa:basket:%d" % index, 0.0, recorded, {"player_id": pid, "points": int(e["points"])}, "pa_chime"))
	elif type == FcGameEventLog.EV_FOUL:
		var pid := int(e["a"])
		out.append(_event(index, ROLE_ANNOUNCER, "foul", "Foul on %s." % _who(ctx, pid), 40, "pa:foul:%d" % index, 0.0, recorded, {"player_id": pid}, "pa_chime"))
	elif type == FcGameEventLog.EV_PERIOD_END:
		out.append(_event(index, ROLE_ANNOUNCER, "period_end", "End of the %s. %s %d, %s %d." % [str(snap["period_name"]).to_lower(), abbr[0], int(snap["home"]), abbr[1], int(snap["away"])], 60,
			"pa:period:%d" % index, 0.0, recorded, {"home": int(snap["home"]), "away": int(snap["away"])}, "pa_chime"))
	elif type == FcGameEventLog.EV_GAME_END:
		out.append(_event(index, ROLE_ANNOUNCER, "final", "Final score: %s %d, %s %d." % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])], 70,
			"pa:final", 0.0, recorded, {"home": int(snap["home"]), "away": int(snap["away"])}, "pa_chime"))
	elif type == FcGameEventLog.EV_SUBSTITUTION:
		out.append(_event(index, ROLE_ANNOUNCER, "substitution", "Substitution: %s in for %s." % [_name(ctx, int(e["a"])), _name(ctx, int(e["b"]))], 20,
			"pa:sub:%d" % index, 6.0, recorded, {"in": int(e["a"]), "out": int(e["b"])}))


## "number 24, Herrera" (the number is the per-game display number, D-070; without one, just the name).
static func _who(ctx: Dictionary, id: int) -> String:
	var number := int((ctx["numbers"] as Dictionary).get(id, 0))
	return "number %d, %s" % [number, _name(ctx, id)] if number > 0 else _name(ctx, id)
