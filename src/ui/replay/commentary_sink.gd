class_name FcCommentarySink
extends RefCounted
## Where an accepted commentary line goes (Broadcast pass 2, M6, D-071). The content (FcCommentaryEvents) and the choice of what to say
## (FcCommentaryArbiter) never know how a line is delivered; a sink does. One interface serves every delivery:
##   KIND_CAPTION         written captions (built: FcCaptionSink), the only sink in the game today
##   KIND_RECORDED_VOICE  pre-recorded audio clips, one per line key (future)
##   KIND_TTS             text to speech on the player's own device (future)
##   KIND_AI              generated commentary from an optional service (future; never required, the game is fully playable offline)
## A voice sink returns true from has_voice(), which is what makes the audio duck the crowd while it speaks (FcDuckingModel); a caption sink
## never ducks anything. Subclasses override kind(), has_voice(), speak() and stop().

const KIND_CAPTION := "caption"
const KIND_RECORDED_VOICE := "recorded_voice"
const KIND_TTS := "tts"
const KIND_AI := "ai"
const KINDS := [KIND_CAPTION, KIND_RECORDED_VOICE, KIND_TTS, KIND_AI]


func kind() -> String:
	return KIND_CAPTION


## Whether this sink makes sound (so the background should duck while it speaks).
func has_voice() -> bool:
	return false


## Delivers one accepted FcCommentaryEvents event.
func speak(_line: Dictionary) -> void:
	pass


## Cuts off whatever is being delivered (a preempted line, a seek, leaving the screen).
func stop() -> void:
	pass
