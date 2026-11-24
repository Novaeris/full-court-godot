class_name FcProductionPlan
extends RefCounted
## The broadcast production of ONE game (Broadcast pass 2, M7, D-071): pregame, halftime, postgame and the championship presentation, built from a
## template (data/broadcast/templates, FcProductionTemplate) and the game's recorded timeline. Pure and deterministic: it reads the broadcast timeline
## (recorded events) and the box score, and every line and number is a recorded or exactly derived fact (the tests recompute them). It invents nothing:
## no quotes, no predictions, no opinions about people. The segments are view models that FcProductionPanel draws.
##
## A plan is {template_id, title, index (the event the show is "at"), segments [segment], total_seconds}. A segment is
##   {type, title, seconds, rows [[String]], lines [String], facts {}, source (FcPresentationEvent.SIM_RECORDED or DERIVED_FROM_RECORDED), available, note}.

## What "player of the game" means, stated on screen: points + rebounds + assists + steals + blocks.
const PLAYER_OF_GAME_NOTE := "Player of the game: the most points + rebounds + assists + steals + blocks."


## The plan for `template_id` over `timeline` ({} for an empty game or an unknown template). `context` may hold "index" (the event to be at),
## "series_label" and "champion_side" for the championship presentation.
static func build(template_id: String, timeline: FcBroadcastTimeline, context: Dictionary = {}) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	var template := FcProductionTemplate.load_template(template_id)
	if not FcProductionTemplate.problems(template).is_empty() or str(template["scope"]) != FcProductionTemplate.SCOPE_GAME:
		return {}
	var index := int(context.get("index", _index_for(template_id, timeline)))
	index = clampi(index, 0, timeline.size() - 1)
	var segments: Array[Dictionary] = []
	var total := 0.0
	for spec in FcProductionTemplate.segments(template):
		var seg := _segment(str(spec["type"]), float(spec["seconds"]), timeline, index, context)
		segments.append(seg)
		total += float(spec["seconds"])
	return {"template_id": template_id, "title": str(template["title"]), "index": index, "segments": segments, "total_seconds": total}


## The event a show is at: the tip-off for the pregame, the half for the halftime report, the end of the game for the others.
static func _index_for(template_id: String, timeline: FcBroadcastTimeline) -> int:
	match template_id:
		"pregame":
			return timeline.model.start_index()
		"halftime":
			return halftime_index(timeline)
	return timeline.size() - 1


## The event that ends the second quarter of a four-quarter game (the half), or the middle of the game when there is none.
static func halftime_index(timeline: FcBroadcastTimeline) -> int:
	var model := timeline.model
	for e in model.entries:
		if int(e["type"]) == FcGameEventLog.EV_PERIOD_END and int(e["x"]) * 2 == model.quarters:
			return int(e["index"])
	return int(timeline.size() / 2.0)


static func _seg(type: String, title: String, seconds: float, rows: Array, lines: Array, facts: Dictionary, source: String = FcPresentationEvent.SIM_RECORDED, available: bool = true, note: String = "") -> Dictionary:
	return {"type": type, "title": title, "seconds": seconds, "rows": rows, "lines": lines, "facts": facts, "source": source, "available": available, "note": note}


static func _segment(type: String, seconds: float, timeline: FcBroadcastTimeline, index: int, context: Dictionary) -> Dictionary:
	var model := timeline.model
	var box := model.box
	var abbr: Array = box.abbreviations
	var snap := timeline.snapshot(index)
	var derived := FcPresentationEvent.DERIVED_FROM_RECORDED
	match type:
		"matchup":
			return _seg(type, "Tonight", seconds, [["Home", str(box.team_names[0]), str(abbr[0])], ["Visitors", str(box.team_names[1]), str(abbr[1])]],
				["%s at %s" % [box.team_names[1], box.team_names[0]]], {"home": str(abbr[0]), "away": str(abbr[1])})
		"lineups":
			var card := FcBroadcastGraphics.lineup_card(timeline)
			var rows: Array = []
			for side in card.get("sides", []):
				for r in side["rows"]:
					rows.append([str(side["abbreviation"]), str(r[0]), str(r[1]), str(r[2])])
			return _seg(type, "Starting lineups", seconds, rows, [], {"starters": rows.size()})
		"halftime_score":
			return _seg(type, "Halftime", seconds, [], ["Halftime: %s %d, %s %d" % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])]], {"home": int(snap["home"]), "away": int(snap["away"])})
		"final_score":
			var label := "Final" if box.overtimes == 0 else ("Final / OT" if box.overtimes == 1 else "Final / %dOT" % box.overtimes)
			return _seg(type, label, seconds, [], ["%s: %s %d, %s %d" % [label, abbr[0], int(snap["home"]), abbr[1], int(snap["away"])]], {"home": int(snap["home"]), "away": int(snap["away"]), "overtimes": box.overtimes})
		"line_score":
			return _line_score(timeline, index, seconds)
		"storyline":
			var largest: Array = snap["largest_lead"]
			var lines: Array = ["Lead changes: %d" % int(snap["lead_changes"]), "Times tied: %d" % int(snap["ties"]),
				"Largest lead: %s by %d, %s by %d" % [abbr[0], int(largest[0]), abbr[1], int(largest[1])]]
			var run: Dictionary = snap["run"]
			if int(run["points"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN:
				lines.append("Current run: %s, %d unanswered points" % [abbr[int(run["side"])], int(run["points"])])
			return _seg(type, "How the game has gone", seconds, [], lines, {"lead_changes": int(snap["lead_changes"]), "ties": int(snap["ties"]), "largest_lead": largest.duplicate()}, derived)
		"player_of_game":
			return _player_of_game(box, seconds)
		"team_comparison":
			var card2 := FcBroadcastGraphics.team_card_at(timeline, index)
			var rows2: Array = [["", str(abbr[0]), str(abbr[1])]]
			rows2.append_array(card2["rows"])
			return _seg(type, "Team comparison", seconds, rows2, [], {"home": card2["home"], "away": card2["away"]}, derived)
		"leaders":
			return _leaders(timeline, snap, seconds)
		"milestones":
			var lines2: Array = []
			var found: Array = []
			var names := {}
			for p in box.players:
				names[p.player_id] = FcPlayByPlay.short_name(p.name)
			for i in range(model.start_index(), index + 1):
				var m: Dictionary = timeline.snapshot(i)["milestone"]
				if not m.is_empty():
					lines2.append("%s  %s reached %d points" % [str(model.entries[i]["clock_text"]), str(names.get(int(m["player_id"]), "A player")), int(m["points"])])
					found.append({"index": i, "player_id": int(m["player_id"]), "points": int(m["points"])})
			if lines2.is_empty():
				lines2.append("No scoring milestones in this game.")
			return _seg(type, "Milestones", seconds, [], lines2, {"milestones": found}, derived)
		"highlights":
			var refs: Array = []
			var rows3: Array = []
			for ref in FcReplayCollections.package(timeline)["refs"]:
				if int(ref["end"]) <= index:
					refs.append(ref)
					rows3.append([str(model.entries[int(ref["end"])]["clock_text"]), str(ref["label"])])
			return _seg(type, "Highlights (reconstructed replays)", seconds, rows3, [], {"refs": refs}, derived, not refs.is_empty(), "" if not refs.is_empty() else "No highlights yet.")
		"trophy":
			var home_won := int(snap["home"]) > int(snap["away"])
			var side := int(context.get("champion_side", 0 if home_won else 1))
			var lines3: Array = ["%s are the champions!" % str(box.team_names[side])]
			if str(context.get("series_label", "")) != "":
				lines3.append(str(context["series_label"]))
			lines3.append("Final score: %s %d, %s %d" % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])])
			return _seg(type, "Champions", seconds, [], lines3, {"champion_side": side}, derived)
	return _seg(type, type, seconds, [], [], {}, derived, false, "Unknown segment.")


static func _line_score(timeline: FcBroadcastTimeline, index: int, seconds: float) -> Dictionary:
	var model := timeline.model
	var abbr: Array = model.box.abbreviations
	var header: Array = [""]
	var home: Array = [str(abbr[0])]
	var away: Array = [str(abbr[1])]
	var last_home := 0
	var last_away := 0
	for p in model.periods():
		var end_snap: Dictionary = {}
		for i in range(model.start_index(), index + 1):
			var e: Dictionary = model.entries[i]
			if int(e["type"]) == FcGameEventLog.EV_PERIOD_END and int(e["x"]) == p:
				end_snap = timeline.snapshot(i)
				break
		if end_snap.is_empty():
			end_snap = timeline.snapshot(index) if p == model.periods().back() else {}
		if end_snap.is_empty():
			continue
		header.append(("Q%d" % p) if p <= model.quarters else ("OT" if p == model.quarters + 1 else "OT%d" % (p - model.quarters)))
		home.append(str(int(end_snap["home"]) - last_home))
		away.append(str(int(end_snap["away"]) - last_away))
		last_home = int(end_snap["home"])
		last_away = int(end_snap["away"])
	header.append("T")
	home.append(str(last_home))
	away.append(str(last_away))
	return _seg("line_score", "Score by period", seconds, [header, home, away], [], {"home_total": last_home, "away_total": last_away}, FcPresentationEvent.DERIVED_FROM_RECORDED)


static func _player_of_game(box: FcBoxScore, seconds: float) -> Dictionary:
	var best: FcPlayerGameStats = null
	var best_value := -1
	for p in box.players:
		var value: int = p.points + p.oreb + p.dreb + p.ast + p.stl + p.blk
		if best == null or value > best_value or (value == best_value and (p.points > best.points or (p.points == best.points and p.player_id < best.player_id))):
			best = p
			best_value = value
	if best == null:
		return _seg("player_of_game", "Player of the game", seconds, [], [], {}, FcPresentationEvent.DERIVED_FROM_RECORDED, false, "No box score.")
	var side := 0 if best.team_id == box.team_ids[0] else 1
	var line := "%d PTS, %d REB, %d AST" % [best.points, best.oreb + best.dreb, best.ast]
	return _seg("player_of_game", "Player of the game", seconds, [[FcPlayByPlay.short_name(best.name), str(box.abbreviations[side]), line]],
		["%s (%s): %s" % [FcPlayByPlay.short_name(best.name), box.abbreviations[side], line], PLAYER_OF_GAME_NOTE],
		{"player_id": best.player_id, "points": best.points, "rebounds": best.oreb + best.dreb, "assists": best.ast, "value": best_value}, FcPresentationEvent.DERIVED_FROM_RECORDED)


static func _leaders(timeline: FcBroadcastTimeline, snap: Dictionary, seconds: float) -> Dictionary:
	var names := {}
	for p in timeline.model.box.players:
		names[p.player_id] = FcPlayByPlay.short_name(p.name)
	var abbr: Array = timeline.model.box.abbreviations
	var rows: Array = [["", str(abbr[0]), str(abbr[1])]]
	var leaders: Array = snap["leaders"]
	for cat in [["points", "Points"], ["rebounds", "Rebounds"], ["assists", "Assists"]]:
		var row: Array = [str(cat[1])]
		for side in 2:
			var l: Dictionary = (leaders[side] as Dictionary)[cat[0]]
			row.append("%s %d" % [str(names.get(int(l["player_id"]), "-")), int(l["value"])] if int(l["player_id"]) != 0 else "-")
		rows.append(row)
	return _seg("leaders", "Leaders so far", seconds, rows, [], {"leaders": leaders.duplicate(true)}, FcPresentationEvent.DERIVED_FROM_RECORDED)
