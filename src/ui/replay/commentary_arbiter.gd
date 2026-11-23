class_name FcCommentaryArbiter
extends RefCounted
## Decides which commentary line is spoken (Broadcast pass 2, M6): one speaker at a time, the right role first, and no repeating. Fed the
## FcCommentaryEvents of each event with the replay time `now` (seconds on the replay's own axis, so playback speed and pausing are the caller's
## business), it returns at most ONE line to speak, or none. Pure and deterministic: no randomness and no wall clock.
##
## Rules, in order:
##  1. REPETITION: an event whose key was spoken less than its cooldown ago is dropped; the same text is not repeated within TEXT_REPEAT_SECONDS;
##     a role that speaks rarely (color, narrative) keeps a minimum gap between its lines (ROLE_MIN_GAP).
##  2. RANK: among what is left the role with the highest rank wins (play-by-play, then announcer, then narrative, then color), then the higher priority.
##  3. ONE VOICE: while a line is still being spoken (its estimated length, from the characters) a new line is DROPPED, not queued (live commentary
##     does not talk about the past), unless it PREEMPTS: a play-by-play line of priority PREEMPT_PRIORITY or more interrupts any other role, and a
##     higher-ranked role of that priority interrupts a lower one.

const TEXT_REPEAT_SECONDS := 90.0
const PREEMPT_PRIORITY := 75
## Play-by-play of a minor play (a miss, a rebound, a turnover) is shown as a caption but never takes the voice: plays come about a second apart and a spoken line takes
## three, so calling every one would leave no room for the analyst or the narrator. The big plays are called; the quiet moments are left to the other roles.
const MIN_SPOKEN_PBP_PRIORITY := 50
const CHARS_PER_SECOND := 14.0
const MIN_SECONDS := 1.2
const ROLE_MIN_GAP := {FcCommentaryEvents.ROLE_PBP: 0.0, FcCommentaryEvents.ROLE_ANNOUNCER: 0.0, FcCommentaryEvents.ROLE_NARRATIVE: 20.0, FcCommentaryEvents.ROLE_COLOR: 12.0}

## The line being spoken ({} when none) and when it ends (replay seconds).
var current: Dictionary = {}
var speaker_until: float = -1.0

var _last_key_at: Dictionary = {}
var _last_text_at: Dictionary = {}
var _last_role_at: Dictionary = {}


## How long a line takes to speak, estimated from its length.
static func duration_of(text: String) -> float:
	return maxf(MIN_SECONDS, float(text.length()) / CHARS_PER_SECOND)


## Offers the commentary events of one moment. Returns {"line": the event to speak or {}, "preempted": bool, "dropped": [{event, reason}]}.
func offer(events: Array, now: float) -> Dictionary:
	if now >= speaker_until:
		current = {}
	var dropped: Array = []
	var candidates: Array = []
	for ev in events:
		var reason := _repeat_reason(ev, now)
		if reason != "":
			dropped.append({"event": ev, "reason": reason})
		else:
			candidates.append(ev)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(FcCommentaryEvents.ROLE_RANK[a["role"]])
		var rb := int(FcCommentaryEvents.ROLE_RANK[b["role"]])
		if ra != rb:
			return ra > rb
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) > int(b["priority"])
		return str(a["key"]) < str(b["key"]))
	if candidates.is_empty():
		return {"line": {}, "preempted": false, "dropped": dropped}
	var best: Dictionary = candidates[0]
	var preempted := false
	if not current.is_empty():
		if _preempts(best, current):
			preempted = true
		else:
			for c in candidates:
				dropped.append({"event": c, "reason": "busy"})
			return {"line": {}, "preempted": false, "dropped": dropped}
	for c in candidates.slice(1):
		dropped.append({"event": c, "reason": "outranked"})
	current = best
	speaker_until = now + duration_of(str(best["text"]))
	_last_key_at[str(best["key"])] = now
	_last_text_at[str(best["text"])] = now
	_last_role_at[str(best["role"])] = now
	return {"line": best, "preempted": preempted, "dropped": dropped}


## Whether a line is being spoken at `now`.
func is_speaking(now: float) -> bool:
	return not current.is_empty() and now < speaker_until


func reset() -> void:
	current = {}
	speaker_until = -1.0
	_last_key_at = {}
	_last_text_at = {}
	_last_role_at = {}


func _repeat_reason(ev: Dictionary, now: float) -> String:
	if str(ev["role"]) == FcCommentaryEvents.ROLE_PBP and int(ev["priority"]) < MIN_SPOKEN_PBP_PRIORITY:
		return "minor"
	var key := str(ev["key"])
	if _last_key_at.has(key) and now - float(_last_key_at[key]) < float(ev["cooldown"]):
		return "repeat_key"
	var text := str(ev["text"])
	if _last_text_at.has(text) and now - float(_last_text_at[text]) < TEXT_REPEAT_SECONDS:
		return "repeat_text"
	var role := str(ev["role"])
	if _last_role_at.has(role) and now - float(_last_role_at[role]) < float(ROLE_MIN_GAP.get(role, 0.0)):
		return "role_gap"
	return ""


## Whether `incoming` may interrupt the line being spoken.
static func _preempts(incoming: Dictionary, speaking: Dictionary) -> bool:
	var in_role := str(incoming["role"])
	var now_role := str(speaking["role"])
	if in_role == FcCommentaryEvents.ROLE_PBP and now_role != FcCommentaryEvents.ROLE_PBP and int(incoming["priority"]) >= PREEMPT_PRIORITY:
		return true
	return int(FcCommentaryEvents.ROLE_RANK[in_role]) > int(FcCommentaryEvents.ROLE_RANK[now_role]) and int(incoming["priority"]) >= PREEMPT_PRIORITY
