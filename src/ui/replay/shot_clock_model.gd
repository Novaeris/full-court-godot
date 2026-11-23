class_name FcShotClockModel
extends RefCounted
## A presentation-only shot clock (Broadcast pass 2, M2, D-071). The simulator has NO shot clock (docs: game_simulator "NOT included"), so
## this never claims one existed. It ESTIMATES how much of 24 seconds the offence has used: the possession is taken to start at the last
## event that ends one (FcBroadcastTimeline.ends_possession: a made basket, a turnover, a defensive rebound, a period boundary), and the time
## used is the drop in the RECORDED game clock since then. Offensive rebounds do not reset it (the game has no such rule).
##
## It reads the recorded game clock, not the movement reconstruction, so the reconstruction's compressed steps (19.5%, see
## docs/validation/B2_PASS2_RECONSTRUCTION_TIMING.md) cannot distort it. It is still APPROXIMATE (the possession start is inferred), so
## FcPresentationEvent.may_state_as_fact is false for it, and the scoreboard labels it "≈". It is hidden whenever it would be misleading:
## during free throws, at period and game boundaries, on the event that ends a possession (a dead ball), and when more than 24 seconds
## have passed (the game did not enforce 24).
##
## Result: {visible, seconds (the estimate remaining, whole seconds), elapsed, confidence, source, label}. Pure and deterministic.


static func at(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	var hidden := {"visible": false, "seconds": 0, "elapsed": 0.0, "confidence": FcPresentationEvent.APPROXIMATE,
		"source": FcPresentationEvent.DERIVED_FROM_RECORDED, "label": FcBroadcastStyle.scoreboard_text("shot_clock_label", "SHOT CLOCK ≈")}
	if timeline == null or timeline.is_empty():
		return hidden
	var model := timeline.model
	index = clampi(index, 0, timeline.size() - 1)
	var e: Dictionary = model.entries[index]
	if index < model.start_index():
		return hidden
	if int(e["type"]) == FcGameEventLog.EV_PERIOD_START or bool(FcStoppageModel.at(timeline, index)["active"]):
		return hidden   # a recorded stoppage (foul, free throws, substitution, injury, period end, final) or a period start: the clock is not running
	if FcBroadcastTimeline.ends_possession(e):
		return hidden   # a dead ball: the next possession has not started
	var start_clock := -1.0
	var k := index - 1
	while k >= model.start_index():
		var before: Dictionary = model.entries[k]
		if int(before["period"]) != int(e["period"]):
			break
		if FcBroadcastTimeline.ends_possession(before):
			start_clock = float(before["clock"])
			break
		k -= 1
	if start_clock < 0.0:
		return hidden
	var elapsed := start_clock - float(e["clock"])
	var limit := FcBroadcastStyle.shot_clock_max()
	if elapsed < 0.0 or elapsed > float(limit):
		return hidden
	var out := hidden.duplicate()
	out["visible"] = true
	out["elapsed"] = elapsed
	out["seconds"] = clampi(int(ceil(float(limit) - elapsed)), 0, limit)
	return out
