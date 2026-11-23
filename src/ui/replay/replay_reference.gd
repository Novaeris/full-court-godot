class_name FcReplayReference
extends RefCounted
## A pointer to a stretch of a game worth watching again (Broadcast pass 2, M4, D-071): {game_key, start, end, label, source, importance}.
## It is a REFERENCE, never recorded video: nothing was ever filmed. Playing one re-runs the movement reconstruction over the recorded events
## between `start` and `end` (event indices of the game's replay model), so the picture is reconstructed and is labelled that way everywhere
## (REPLAY_WORDING). A reference holds no positions, no times and no randomness, so the same reference always plays the same sequence.
##
## Sources: USER_BOOKMARK (the person marked a play), AUTO_HIGHLIGHT (the importance model's best plays) and KEY_PLAY (every play the importance
## model marks, shown as a tick on the timeline).

const USER_BOOKMARK := "user_bookmark"
const AUTO_HIGHLIGHT := "auto_highlight"
const KEY_PLAY := "key_play"
const SOURCES := [USER_BOOKMARK, AUTO_HIGHLIGHT, KEY_PLAY]

## What the screen says wherever a reference is played.
const REPLAY_WORDING := "Replay (reconstructed from the recorded events, not video)"
const BADGE_TEXT := "REPLAY (reconstructed)"
const REEL_BADGE_TEXT := "HIGHLIGHTS (reconstructed)"


## A reference to the possession that ended at event `index` (the same window the instant replay uses).
static func around(timeline: FcBroadcastTimeline, index: int, source: String, label: String, importance: int = 0) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	var window := timeline.replay_window(index)
	return {"game_key": timeline.model.game_key(), "start": int(window["start"]), "end": int(window["end"]), "label": label, "source": source, "importance": importance}


## Whether `ref` is a well-formed reference into `timeline`'s game.
static func is_valid(timeline: FcBroadcastTimeline, ref: Dictionary) -> bool:
	if timeline == null or timeline.is_empty():
		return false
	for key in ["game_key", "start", "end", "label", "source", "importance"]:
		if not ref.has(key):
			return false
	var start := int(ref["start"])
	var end := int(ref["end"])
	return str(ref["game_key"]) == timeline.model.game_key() and ref["source"] in SOURCES and start >= 0 and start <= end and end < timeline.size() \
		and int(ref["importance"]) >= 0 and int(ref["importance"]) <= 100


## The text shown for a reference in lists: "3:06  G. Delgado connects from deep".
static func describe(timeline: FcBroadcastTimeline, ref: Dictionary) -> String:
	var at := clampi(int(ref.get("end", 0)), 0, timeline.size() - 1)
	return "%s  %s" % [str(timeline.model.entries[at]["clock_text"]), str(ref.get("label", ""))]
