class_name FcAmbienceModel
extends RefCounted
## How loud and tense the arena is at an event (Broadcast pass 2, M6): a 0 to 1 crowd intensity that picks and mixes the ambience bed
## (FcAudio.set_ambience_level). Pure and deterministic: it reads only the recorded game state (the period, the score margin, clutch time, a
## scoring run, whether play is stopped), never a clock or a random number, so a replay always sounds the same. It is presentation: the crowd
## gets louder when the game is tight and late, and quieter in a blowout or at a whistle.

const BASE := 0.3
const LATE_GAME := 0.1
const CLUTCH := 0.3
const CLOSE := 0.1
const BLOWOUT := -0.15
const BLOWOUT_MARGIN := 20
const CLOSE_MARGIN := 5
const RUN := 0.15
const JUST_SCORED := 0.05
const STOPPAGE := -0.1


static func level_at(timeline: FcBroadcastTimeline, index: int) -> float:
	if timeline == null or timeline.is_empty():
		return 0.0
	index = clampi(index, 0, timeline.size() - 1)
	var snap := timeline.snapshot(index)
	var e: Dictionary = timeline.model.entries[index]
	var level := BASE
	if int(snap["period"]) >= timeline.model.quarters:
		level += LATE_GAME
	if bool(snap["clutch"]):
		level += CLUTCH
	var margin := absi(int(snap["lead"]))
	if margin <= CLOSE_MARGIN:
		level += CLOSE
	elif margin >= BLOWOUT_MARGIN:
		level += BLOWOUT
	var run: Dictionary = snap["run"]
	if int(run["points"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN:
		level += RUN
	if int(e["points"]) > 0:
		level += JUST_SCORED
	if bool(FcStoppageModel.at(timeline, index)["active"]):
		level += STOPPAGE
	return clampf(level, 0.0, 1.0)
