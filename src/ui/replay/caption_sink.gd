class_name FcCaptionSink
extends FcCommentarySink
## The written-captions sink: keeps the latest line of each role and a short history, for the screen to draw. The only sink the game ships;
## recorded voice, text to speech and AI commentary will be other FcCommentarySink classes fed the same events. It has no voice, so it never
## ducks the crowd. Delivering a caption changes nothing about the game.

const HISTORY := 60

var lines: Dictionary = {}     # role -> the latest text
var history: Array[Dictionary] = []   # {role, text, index}, oldest first, capped


func kind() -> String:
	return FcCommentarySink.KIND_CAPTION


func has_voice() -> bool:
	return false


func speak(line: Dictionary) -> void:
	lines[str(line["role"])] = str(line["text"])
	history.append({"role": str(line["role"]), "text": str(line["text"]), "index": int(line["index"])})
	while history.size() > HISTORY:
		history.pop_front()


## The latest caption of a role ("" when it has not spoken since the last stop).
func latest(role: String) -> String:
	return str(lines.get(role, ""))


func stop() -> void:
	lines = {}
