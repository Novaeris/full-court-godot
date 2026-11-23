class_name FcDuckingModel
extends RefCounted
## Ducking (Broadcast pass 2, M6): when a voice speaks (commentary, analysis, narrative or the stadium announcer) the background sounds (crowd,
## ambience, music) step down so it can be heard, then come back smoothly. Pure and driven by `advance(delta)`, so tests run it without an audio
## device. The announcer ducks deeper than the commentary because it is a different, nearer voice. The offset moves at a fixed number of dB per
## second (a fast attack, a slow release), so it is a smooth ramp, never a jump and never past the target.
##
## Only a sink that really produces sound should call set_speaking (see FcCommentarySink.has_voice): captions alone never duck anything.

const ROLE_DUCK_DB := {"play_by_play": -6.0, "color": -6.0, "narrative": -6.0, "announcer": -9.0}
const ATTACK_DB_PER_SECOND := 60.0
const RELEASE_DB_PER_SECOND := 15.0
## The buses that step down for a voice.
const DUCKED_BUSES := ["Crowd", "Ambience", "Music"]

## The current offset in dB (0 or negative).
var offset_db: float = 0.0
var _speaking: Dictionary = {}


func set_speaking(role: String, on: bool) -> void:
	if on and ROLE_DUCK_DB.has(role):
		_speaking[role] = true
	else:
		_speaking.erase(role)


func is_speaking() -> bool:
	return not _speaking.is_empty()


## Where the offset is heading: the deepest duck among the voices speaking now, 0 when none is.
func target_db() -> float:
	var deepest := 0.0
	for role in _speaking:
		deepest = minf(deepest, float(ROLE_DUCK_DB[role]))
	return deepest


## One step of time; returns the new offset. Falls quickly towards a deeper target and rises slowly back towards 0.
func advance(delta: float) -> float:
	var target := target_db()
	if offset_db > target:
		offset_db = maxf(target, offset_db - ATTACK_DB_PER_SECOND * maxf(delta, 0.0))
	elif offset_db < target:
		offset_db = minf(target, offset_db + RELEASE_DB_PER_SECOND * maxf(delta, 0.0))
	return offset_db


## The dB offset to apply to `bus_name` (0 for a bus that does not duck).
func offset_for(bus_name: String) -> float:
	return offset_db if bus_name in DUCKED_BUSES else 0.0
