class_name FcCommentary
extends RefCounted
## Announcer-style commentary text for a replay event (master plan B7). It is built ONLY from recorded facts (who, what, the score, the run, the
## lead, the player's running total), never invents anything, and picks between a few phrasings by a hash of the event index (no RNG, so the same
## game always reads the same). Captions first: this is text; spoken voice is optional and off (decision 6 in D-069).

const PHRASES := {
	"layup": ["%s scores at the rim.", "%s finishes inside.", "%s with the layup."],
	"three": ["%s hits the three!", "%s from downtown, good!", "%s drains it from deep."],
	"jumper": ["%s makes the jumper.", "%s knocks down the shot.", "%s with the pull-up, good."],
	"free_throw": ["%s makes the free throw.", "%s converts at the line."],
	"miss": ["%s misses.", "%s can't get it to fall.", "%s with the miss."],
	"block": ["%s blocks the shot!", "Rejected by %s!"],
	"steal": ["%s takes it away!", "%s with the steal."],
	"turnover": ["%s turns it over.", "Giveaway by %s."],
	"foul": ["Foul on %s.", "%s picks up the foul."],
	"rebound": ["%s with the rebound.", "%s grabs it."],
}


## One line for event `index`, or "" when the event has nothing worth saying (a substitution, a period start).
static func line_at(timeline: FcBroadcastTimeline, index: int) -> String:
	if timeline == null or timeline.is_empty():
		return ""
	index = clampi(index, 0, timeline.size() - 1)
	var model := timeline.model
	var e: Dictionary = model.entries[index]
	var names := {}
	for p in model.box.players:
		names[p.player_id] = FcPlayByPlay.short_name(p.name)
	var a := str(names.get(int(e["a"]), "A player"))
	var b := str(names.get(int(e["b"]), "A player"))
	var snap := timeline.snapshot(index)
	var abbr: Array = model.box.abbreviations
	var text := ""
	match int(e["type"]):
		FcGameEventLog.EV_SHOT_MADE:
			var kind := "three" if int(e["points"]) == 3 else ("layup" if int(e["x"]) == FcGameEventLog.SHOT_RIM else "jumper")
			text = _pick(kind, index) % a
			var total := int(timeline.player_line(index, int(e["a"]))["points"])
			text += " That's %d for him." % total if total >= 20 and total - int(e["points"]) < 20 else ""
			if int(e["b"]) != 0:
				text += " Assisted by %s." % b
		FcGameEventLog.EV_SHOT_MISSED:
			text = _pick("miss", index) % a
		FcGameEventLog.EV_SHOT_BLOCKED:
			text = _pick("block", index) % b
		FcGameEventLog.EV_FREE_THROW:
			text = _pick("free_throw", index) % a if int(e["x"]) == 1 else ""
		FcGameEventLog.EV_TURNOVER:
			text = (_pick("steal", index) % b) if int(e["b"]) != 0 else (_pick("turnover", index) % a)
		FcGameEventLog.EV_FOUL:
			text = _pick("foul", index) % a
		FcGameEventLog.EV_REBOUND:
			text = _pick("rebound", index) % a
		FcGameEventLog.EV_GAME_END:
			text = "That's the game: %s %d, %s %d." % [abbr[0], int(snap["home"]), abbr[1], int(snap["away"])]
	if text == "":
		return ""
	var run: Dictionary = snap["run"]
	if int(e["points"]) > 0 and int(run["side"]) == int(e["side"]) and int(run["points"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN:
		text += " That's a %d-0 run for %s." % [int(run["points"]), abbr[int(e["side"])]]
	if index == timeline.clutch_start_index() and index >= 0:
		text += " We are in clutch time."
	return text


static func _pick(kind: String, index: int) -> String:
	var options: Array = PHRASES[kind]
	return str(options[int(FcCourtLayout.unit(index, 7) * options.size()) % options.size()])
