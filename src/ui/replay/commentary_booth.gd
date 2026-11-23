class_name FcCommentaryBooth
extends RefCounted
## The commentary booth (Broadcast pass 2, M6): turns the recorded game into spoken (or captioned) commentary. Per event it gets the role events
## (FcCommentaryEvents), lets the arbiter pick one line (FcCommentaryArbiter) and hands it to every sink (FcCommentarySink). When a sink has a voice it
## also reports who is speaking, through `on_speaking`, so the audio can duck the crowd (FcAudio.set_speaking). No sound, screen or network is
## touched here: a test can run a whole game through a booth with a recording sink.

var arbiter := FcCommentaryArbiter.new()
var sinks: Array[FcCommentarySink] = []
## Called as (role: String, on: bool) when a voice starts or stops speaking. Optional.
var on_speaking: Callable = Callable()
## The role a voice is speaking now ("" when none).
var speaking_role: String = ""


func add_sink(sink: FcCommentarySink) -> FcCommentaryBooth:
	sinks.append(sink)
	return self


## Offers event `index` at replay time `now`. Returns the arbiter's result ({line, preempted, dropped}).
func on_event(timeline: FcBroadcastTimeline, index: int, now: float) -> Dictionary:
	tick(now)
	var result := arbiter.offer(FcCommentaryEvents.at(timeline, index), now)
	var line: Dictionary = result["line"]
	if line.is_empty():
		return result
	if bool(result["preempted"]):
		for sink in sinks:
			sink.stop()
		_set_speaking("")
	var voiced := false
	for sink in sinks:
		sink.speak(line)
		voiced = voiced or sink.has_voice()
	if voiced:
		_set_speaking(str(line["role"]))
	return result


## Lets time pass without an event: a voice that has finished stops (so the ducking releases).
func tick(now: float) -> void:
	if speaking_role != "" and not arbiter.is_speaking(now):
		_set_speaking("")


## Forgets everything (a seek, a new replay, leaving the screen) and stops every sink.
func reset() -> void:
	arbiter.reset()
	for sink in sinks:
		sink.stop()
	_set_speaking("")


func _set_speaking(role: String) -> void:
	if role == speaking_role:
		return
	if speaking_role != "" and on_speaking.is_valid():
		on_speaking.call(speaking_role, false)
	speaking_role = role
	if role != "" and on_speaking.is_valid():
		on_speaking.call(role, true)
