class_name FcBroadcastAudio
extends RefCounted
## Which sounds a game event makes in a replay (master plan B3), and the written caption for each. Pure and deterministic: the cues come from
## the recorded event and the timeline's running state only, never from a random number or a clock, so the same replay always sounds the
## same and playing a replay can never change a game. All sounds are made by the game itself (data/ui/audio.json, FcAudioSynth); none is
## recorded or licensed.
##
## Presentation choices (not basketball rules): the crowd is for the HOME team, so a home basket cheers (louder for a three, a run or clutch
## time) and an away basket is quiet unless it is a run or a clutch basket, when the crowd groans. A block draws an "oh", an injury a groan,
## a home win a big cheer and a home loss a groan.

const CUE_SWISH := "court_swish"
const CUE_RIM := "court_rim"
const CUE_BLOCK := "court_block"
const CUE_SQUEAK := "court_squeak"
const CUE_WHISTLE := "court_whistle"
const CUE_BUZZER := "court_buzzer"
const CUE_BOUNCE := "court_bounce"   # not an event cue: the 3D view raises it when a dribbled ball hits the floor, so it has no caption
const CUE_CHEER_SMALL := "crowd_cheer_small"
const CUE_CHEER_BIG := "crowd_cheer_big"
const CUE_GROAN := "crowd_groan"
const CUE_OH := "crowd_oh"

## The caption of each cue, for people who play without sound ("" = a sound too small to describe).
const CAPTIONS := {CUE_SWISH: "", CUE_RIM: "(ball hits the rim)", CUE_BLOCK: "(block)", CUE_SQUEAK: "(sneakers squeak)", CUE_WHISTLE: "(whistle)",
	CUE_BUZZER: "(buzzer)", CUE_CHEER_SMALL: "(crowd cheers)", CUE_CHEER_BIG: "(crowd roars)", CUE_GROAN: "(crowd groans)", CUE_OH: "(crowd gasps)"}

## A dribbled ball bounces about five times a second, which at normal speed is a rhythm and at fast forward a buzz. The bounce is heard only at normal speed
## or slower, never closer together than MIN_BOUNCE_GAP seconds, and only while the replay plays.
const MIN_BOUNCE_GAP := 0.33
const MAX_BOUNCE_SPEED := 1.0


## Whether a bounce at `now` (seconds, real time) is heard, given the time of the last one heard and the replay speed.
static func bounce_heard(now: float, last: float, speed: float, playing: bool) -> bool:
	return playing and speed <= MAX_BOUNCE_SPEED and now - last >= MIN_BOUNCE_GAP


## At most this many sounds per event, so a busy moment is never a wall of noise.
const MAX_CUES := 3


## The cue ids for event `index`, in the order they should start (no duplicates, at most MAX_CUES, often none).
static func cues_at(timeline: FcBroadcastTimeline, index: int) -> Array[String]:
	var out: Array[String] = []
	if timeline == null or timeline.is_empty():
		return out
	index = clampi(index, 0, timeline.size() - 1)
	var model := timeline.model
	var e: Dictionary = model.entries[index]
	var snap := timeline.snapshot(index)
	var side: int = e["side"]
	var big_moment: bool = bool(snap["clutch"]) or (int(snap["run"]["points"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN and int(snap["run"]["side"]) == side)
	match int(e["type"]):
		FcGameEventLog.EV_SHOT_MADE:
			out.append(CUE_SWISH)
			if side == 0:
				out.append(CUE_CHEER_BIG if (int(e["x"]) == FcGameEventLog.SHOT_THREE or big_moment) else CUE_CHEER_SMALL)
			elif big_moment:
				out.append(CUE_GROAN)
		FcGameEventLog.EV_SHOT_MISSED:
			out.append(CUE_RIM)
		FcGameEventLog.EV_SHOT_BLOCKED:
			out.append(CUE_BLOCK)
			out.append(CUE_OH)
		FcGameEventLog.EV_TURNOVER:
			if int(e["b"]) != 0:
				out.append(CUE_SQUEAK)
		FcGameEventLog.EV_FOUL:
			out.append(CUE_WHISTLE)
		FcGameEventLog.EV_FREE_THROW:
			out.append(CUE_SWISH if int(e["x"]) == 1 else CUE_RIM)
			if int(e["x"]) == 1 and side == 0:
				out.append(CUE_CHEER_SMALL)
		FcGameEventLog.EV_INJURY:
			out.append(CUE_GROAN)
		FcGameEventLog.EV_PERIOD_END:
			out.append(CUE_BUZZER)
		FcGameEventLog.EV_GAME_END:
			out.append(CUE_BUZZER)
			out.append(CUE_CHEER_BIG if int(snap["lead"]) > 0 else CUE_GROAN)
	var m: Dictionary = snap["milestone"]
	if not m.is_empty() and int(m["side"]) == 0:
		out.append(CUE_CHEER_BIG)
	var unique: Array[String] = []
	for id in out:
		if not unique.has(id):
			unique.append(id)
	if unique.size() > MAX_CUES:
		unique.resize(MAX_CUES)
	return unique


## The written caption for a set of cues ("(whistle) (crowd groans)"), "" when none of them needs one.
static func caption_for(cues: Array[String]) -> String:
	var parts: Array[String] = []
	for id in cues:
		var text := str(CAPTIONS.get(id, ""))
		if text != "" and not parts.has(text):
			parts.append(text)
	return " ".join(parts)


## Every cue id this class can produce (used to check the sound map has all of them).
static func all_cues() -> Array[String]:
	var out: Array[String] = []
	for id in CAPTIONS:
		out.append(str(id))
	return out
