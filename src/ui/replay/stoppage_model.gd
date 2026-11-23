class_name FcStoppageModel
extends RefCounted
## Whether play is stopped at an event, and why (Broadcast pass 2, M2). Derived ONLY from the recorded event type, so it is a fact about the
## recording (a foul was called, a substitution was made), never a guess: SIM_RECORDED data, confidence EXACT. The game has no timeouts, so
## none is ever reported. The scoreboard shows it where the estimated shot clock is hidden, and the M3 camera director uses the same reasons
## to pick its stoppage shots.
##
## Result: {active, reason ("foul", "free_throws", "substitution", "injury", "period_end", "game_end", "") , text}.

const REASONS := {
	FcGameEventLog.EV_FOUL: ["foul", "Foul"],
	FcGameEventLog.EV_FREE_THROW: ["free_throws", "Free throws"],
	FcGameEventLog.EV_SUBSTITUTION: ["substitution", "Substitution"],
	FcGameEventLog.EV_INJURY: ["injury", "Injury"],
	FcGameEventLog.EV_PERIOD_END: ["period_end", "End of period"],
	FcGameEventLog.EV_GAME_END: ["game_end", "Final"]}


static func at(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	var none := {"active": false, "reason": "", "text": ""}
	if timeline == null or timeline.is_empty():
		return none
	index = clampi(index, 0, timeline.size() - 1)
	var type := int(timeline.model.entries[index]["type"])
	if not REASONS.has(type):
		return none
	return {"active": true, "reason": REASONS[type][0], "text": REASONS[type][1]}
