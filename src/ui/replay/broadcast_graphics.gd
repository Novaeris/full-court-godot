class_name FcBroadcastGraphics
extends RefCounted
## What a broadcast graphic says at event `i` (master plan B2b, option A): the view models for scoring alerts, scoring runs, milestones,
## lead changes, the bonus, fouls, substitutions, period and final panels and clutch time. Pure: it reads the timeline and the recorded
## event only, so a graphic can never say something the play-by-play or the box score does not (tests/unit/test_broadcast_graphics.gd
## checks the numbers on them against the box score). The same items drive the 2D overlay now and a 3D viewer later, so there is one
## implementation of every graphic.
##
## An item is {kind, title, detail, side (0 home, 1 away, -1 neutral), priority, value (the key number, for tests)}. `items_at` returns them
## most important first; the overlay shows the first. Nothing here invents a fact: no shot clock, timeout or tip-off exists in the game.

const SCORE := "score"
const MILESTONE := "milestone"
const RUN := "run"
const LEAD_CHANGE := "lead_change"
const TIED := "tied"
const BONUS := "bonus"
const FOUL := "foul"
const SUBSTITUTION := "substitution"
const INJURY := "injury"
const TURNOVER := "turnover"
const BLOCK := "block"
const PERIOD_START := "period_start"
const PERIOD_END := "period_end"
const FINAL := "final"
const CLUTCH := "clutch"
const HALFTIME := "halftime"

## Higher is shown first when several things happen at once.
const PRIORITY := {FINAL: 100, HALFTIME: 92, PERIOD_END: 90, MILESTONE: 85, INJURY: 80, RUN: 75, LEAD_CHANGE: 70, TIED: 68, BONUS: 65, CLUTCH: 60,
	SCORE: 50, BLOCK: 40, TURNOVER: 35, SUBSTITUTION: 30, FOUL: 25, PERIOD_START: 20}


## All items for event `index`, most important first (empty when nothing is worth a graphic, for example a plain miss or rebound).
static func items_at(timeline: FcBroadcastTimeline, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if timeline == null or timeline.is_empty():
		return out
	index = clampi(index, 0, timeline.size() - 1)
	var model := timeline.model
	var e: Dictionary = model.entries[index]
	var snap := timeline.snapshot(index)
	var before := timeline.snapshot(index - 1) if index > 0 else {}
	var names := _names(model.box)
	var abbr: Array = model.box.abbreviations
	var type: int = e["type"]
	var side: int = e["side"]
	match type:
		FcGameEventLog.EV_SHOT_MADE:
			var total := int(timeline.player_line(index, int(e["a"]))["points"])
			var detail := "%d PTS" % total
			if int(e["b"]) != 0:
				detail += "  ·  Assist: %s" % _who(names, int(e["b"]))
			out.append(_item(SCORE, "%s  +%d" % [_who(names, int(e["a"])), int(e["points"])], detail, side, total))
		FcGameEventLog.EV_FREE_THROW:
			if int(e["x"]) == 1:
				var total_ft := int(timeline.player_line(index, int(e["a"]))["points"])
				out.append(_item(SCORE, "%s  free throw  +1" % _who(names, int(e["a"])), "%d PTS" % total_ft, side, total_ft))
		FcGameEventLog.EV_SHOT_BLOCKED:
			out.append(_item(BLOCK, "Block  %s" % _who(names, int(e["b"])), "on %s" % _who(names, int(e["a"])), 1 - side, int(e["b"])))
		FcGameEventLog.EV_TURNOVER:
			if int(e["b"]) != 0:
				out.append(_item(TURNOVER, "Steal  %s" % _who(names, int(e["b"])), "from %s" % _who(names, int(e["a"])), 1 - side, int(e["b"])))
			else:
				out.append(_item(TURNOVER, "Turnover  %s" % _who(names, int(e["a"])), "", side, int(e["a"])))
		FcGameEventLog.EV_FOUL:
			var fouls := int(timeline.player_line(index, int(e["a"]))["pf"])
			out.append(_item(FOUL, "Foul  %s  (%d)" % [_who(names, int(e["a"])), fouls], "Team fouls: %d" % int((snap["team_fouls"] as Array)[side]), side, fouls))
		FcGameEventLog.EV_SUBSTITUTION:
			out.append(_item(SUBSTITUTION, "In: %s" % _who(names, int(e["a"])), "Out: %s" % _who(names, int(e["b"])), side, int(e["a"])))
		FcGameEventLog.EV_INJURY:
			out.append(_item(INJURY, "Injury  %s" % _who(names, int(e["a"])), "", side, int(e["a"])))
		FcGameEventLog.EV_PERIOD_START:
			out.append(_item(PERIOD_START, "Start of the %s" % str(snap["period_name"]), "", -1, int(e["x"])))
		FcGameEventLog.EV_PERIOD_END:
			var scores := "%s %d   %s %d" % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])]
			if int(e["x"]) * 2 == model.quarters:   # the break in the middle of regulation
				out.append(_item(HALFTIME, "Halftime", scores, -1, int(e["x"])))
			else:
				out.append(_item(PERIOD_END, "End of the %s" % str(snap["period_name"]), scores, -1, int(e["x"])))
		FcGameEventLog.EV_GAME_END:
			var label := "Final" if model.box.overtimes == 0 else ("Final / OT" if model.box.overtimes == 1 else "Final / %dOT" % model.box.overtimes)
			out.append(_item(FINAL, label, "%s %d   %s %d" % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])], -1, int(snap["lead"])))
	# state changes around the event
	var m: Dictionary = snap["milestone"]
	if not m.is_empty():
		out.append(_item(MILESTONE, "%s  reaches %d points" % [_who(names, int(m["player_id"])), int(m["points"])], "", int(m["side"]), int(m["points"])))
	var run: Dictionary = snap["run"]
	if int(e["points"]) > 0 and int(run["side"]) == side and int(run["points"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN:
		out.append(_item(RUN, "%d-0 run  %s" % [int(run["points"]), abbr[side]], "", side, int(run["points"])))
	if not before.is_empty():
		if int(snap["lead_changes"]) > int(before["lead_changes"]):
			var leader := 0 if int(snap["lead"]) > 0 else 1
			out.append(_item(LEAD_CHANGE, "Lead change", "%s by %d" % [abbr[leader], absi(int(snap["lead"]))], leader, absi(int(snap["lead"]))))
		if int(snap["ties"]) > int(before["ties"]):
			out.append(_item(TIED, "Game tied", "%d - %d" % [int(snap["home"]), int(snap["away"])], -1, int(snap["home"])))
		for s in 2:
			if bool((snap["bonus_for"] as Array)[s]) and not bool((before["bonus_for"] as Array)[s]) and int(before["period"]) == int(snap["period"]):
				out.append(_item(BONUS, "%s in the bonus" % abbr[s], "Team fouls: %d" % int((snap["team_fouls"] as Array)[1 - s]), s, int((snap["team_fouls"] as Array)[1 - s])))
	if index == timeline.clutch_start_index() and index >= 0:
		out.append(_item(CLUTCH, "Clutch time", "%s %d   %s %d" % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])], -1, absi(int(snap["lead"]))))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["priority"]) > int(b["priority"]))
	return out


## The team comparison card at event `i`: rows of [label, home value, away value] counted from the same events as the box score
## (field goals, three-pointers, free throws, rebounds, assists, turnovers, fouls), plus the lead and the longest lead of each side.
static func team_card_at(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	index = clampi(index, 0, timeline.size() - 1)
	var h := timeline.team_line(index, 0)
	var a := timeline.team_line(index, 1)
	var snap := timeline.snapshot(index)
	var abbr: Array = timeline.model.box.abbreviations
	var rows: Array = [
		["FG", "%d-%d" % [h["fgm"], h["fga"]], "%d-%d" % [a["fgm"], a["fga"]]],
		["3PT", "%d-%d" % [h["tpm"], h["tpa"]], "%d-%d" % [a["tpm"], a["tpa"]]],
		["FT", "%d-%d" % [h["ftm"], h["fta"]], "%d-%d" % [a["ftm"], a["fta"]]],
		["Rebounds", str(h["reb"]), str(a["reb"])],
		["Assists", str(h["ast"]), str(a["ast"])],
		["Turnovers", str(h["tov"]), str(a["tov"])],
		["Fouls", str(h["pf"]), str(a["pf"])],
		["Biggest lead", str(snap["largest_lead"][0]), str(snap["largest_lead"][1])]]
	return {"title": "Team comparison", "abbreviations": [abbr[0], abbr[1]], "rows": rows, "home": h, "away": a}


## The starting-lineups card (pregame): per side the five starters, in position order, as rows [display number, short name, position]. Numbers are
## the per-game DISPLAY numbers of FcJerseyNumbers (nothing stored; D-070); a player with no number (0) shows "". The starters are the five on court at
## the tip-off, from the recorded starter events, never guessed.
static func lineup_card(timeline: FcBroadcastTimeline) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	var model := timeline.model
	var on_court: Array = model.state_at(model.start_index())["on_court"]
	var numbers := FcJerseyNumbers.for_box(model.box)
	var by_id := {}
	for p in model.box.players:
		by_id[p.player_id] = p
	var sides: Array = []
	for side in 2:
		var rows: Array = []
		var ids: Array = (on_court[side] as Array).duplicate()
		ids.sort_custom(func(a: int, b: int) -> bool:
			var pa: int = by_id[a].position if by_id.has(a) else 9
			var pb: int = by_id[b].position if by_id.has(b) else 9
			return pa < pb if pa != pb else a < b)
		for id in ids:
			if not by_id.has(id):
				continue
			var p = by_id[id]
			var n := int(numbers.get(id, 0))
			rows.append([str(n) if n > 0 else "", FcPlayByPlay.short_name(p.name), FcPosition.abbreviation(p.position)])
		sides.append({"abbreviation": str(model.box.abbreviations[side]), "team": str(model.box.team_names[side]), "rows": rows})
	return {"title": "Starting lineups", "sides": sides}


## The one graphic to show at event `i` ({} when there is none).
static func top_item_at(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	var items := items_at(timeline, index)
	return items[0] if not items.is_empty() else {}


static func _item(kind: String, title: String, detail: String, side: int, value: int) -> Dictionary:
	return {"kind": kind, "title": title, "detail": detail, "side": side, "priority": int(PRIORITY[kind]), "value": value}


static func _names(box: FcBoxScore) -> Dictionary:
	var out := {}
	for p in box.players:
		out[p.player_id] = FcPlayByPlay.short_name(p.name)
	return out


static func _who(names: Dictionary, id: int) -> String:
	return str(names.get(id, "A player"))
