class_name FcRecordingSink
extends FcCommentarySink
## A test double for a VOICE sink (recorded voice, text to speech or AI in the future): it records every line it is asked to speak and every stop,
## and reports a voice, so tests can prove that the booth, the arbiter and the ducking behave with a sink that makes sound, without any audio.

var spoken: Array[Dictionary] = []
var stops: int = 0


func kind() -> String:
	return FcCommentarySink.KIND_TTS


func has_voice() -> bool:
	return true


func speak(line: Dictionary) -> void:
	spoken.append(line)


func stop() -> void:
	stops += 1
