class_name FcNotifier
extends RefCounted
## The one place messages go. Every screen's message ("Saved.", "Cannot create this league: ...") becomes a toast the player sees
## and a line in `history` (the last HISTORY_LIMIT messages; a notification centre can show it later). say() picks the kind from the
## words when the caller did not say; call info/success/warning/error when you know. Toasts are drawn by an FcToastStack the
## shell provides; with no stack (tests) messages are still recorded.

const HISTORY_LIMIT := 30

var stack: FcToastStack = null
var history: Array = []   # [{"kind": FcToast.Kind, "text": String}], oldest first


func info(text: String) -> void:
	_show(FcToast.Kind.INFO, text)


func success(text: String) -> void:
	_show(FcToast.Kind.SUCCESS, text)


func warning(text: String) -> void:
	_show(FcToast.Kind.WARNING, text)


func error(text: String) -> void:
	_show(FcToast.Kind.ERROR, text)


## Shows a message whose kind is guessed from its words (the older screens only have text).
func say(text: String) -> void:
	if text.strip_edges() != "":
		_show(classify(text), text)


## ERROR for failure words, SUCCESS for completion words, otherwise INFO.
static func classify(text: String) -> FcToast.Kind:
	var t := text.to_lower()
	for word in ["cannot", "can't", "could not", "couldn't", "failed", "not enough", "refused", "invalid", "damaged", "unable", "no such", "must "]:
		if t.contains(word):
			return FcToast.Kind.ERROR
	for word in ["saved", "created", "bought", "signed", "claimed", "converted", "raised", "complete", "champions", "welcome", "restored"]:
		if t.contains(word):
			return FcToast.Kind.SUCCESS
	return FcToast.Kind.INFO


## A gold achievement banner (a level reached, a title won) with its own sound; `cue_id` names the sound ("achievement" by default).
func achievement(text: String, cue_id: String = "achievement") -> void:
	if text.strip_edges() == "":
		return
	history.append({"kind": FcToast.Kind.ACHIEVEMENT, "text": text})
	FcAudio.cue(cue_id)
	if history.size() > HISTORY_LIMIT:
		history.pop_front()
	if stack != null and is_instance_valid(stack):
		stack.push(FcToast.Kind.ACHIEVEMENT, text)


func last() -> Dictionary:
	return history.back() if not history.is_empty() else {}


func _show(kind: FcToast.Kind, text: String) -> void:
	if text.strip_edges() == "":
		return
	history.append({"kind": kind, "text": text})
	FcAudio.cue("toast_" + str(FcToast.Kind.keys()[kind]).to_lower())
	if history.size() > HISTORY_LIMIT:
		history.pop_front()
	if stack != null and is_instance_valid(stack):
		stack.push(kind, text)
