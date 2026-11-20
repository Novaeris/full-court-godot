class_name FcHints
extends RefCounted
## First-run hints: which hint a screen should show, and which the player has already dismissed. The words live in data/ui/hints.json.
## What was dismissed is UI memory (FcUiState, user://ui_state.cfg), never a save, and the player can turn hints off for good or ask to see
## them again in Settings. A missing state file just means every hint is new. Nothing here touches the game.

const PATH := "res://data/ui/hints.json"
const SECTION := "hints"

var _state: FcUiState
var _prefs: FcPreferences
var _hints: Dictionary = {}   # id -> {id, mode, title, text}


func _init(state: FcUiState, preferences: FcPreferences) -> void:
	_state = state
	_prefs = preferences
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		for h in (parsed as Dictionary).get("hints", []):
			_hints[str(h["id"])] = h


func ids() -> Array:
	return _hints.keys()


func get_hint(id: String) -> Dictionary:
	return _hints.get(id, {})


## True when this hint exists, hints are on, and the player has not dismissed it.
func is_pending(id: String) -> bool:
	return _hints.has(id) and _prefs.hints_enabled and _state != null and not bool(_state.get_value(SECTION, id, false))


func dismiss(id: String) -> void:
	if _state != null and _hints.has(id):
		_state.set_value(SECTION, id, true)


## Makes every hint new again (Settings: "Show the hints again").
func reset() -> void:
	if _state == null:
		return
	for id in _hints:
		_state.set_value(SECTION, id, false)


func pending_count() -> int:
	var n := 0
	for id in _hints:
		if is_pending(id):
			n += 1
	return n


## The card for a hint, or null when there is nothing to show. Pressing Got it dismisses it and removes the card.
func card(id: String) -> Control:
	if not is_pending(id):
		return null
	var hint: Dictionary = _hints[id]
	var panel := FcPanel.new(str(hint["title"]), FcPanel.Variant.RAISED)
	panel.name = "Hint"
	panel.set_accent(FcUiTokens.INFO)
	var text := FcUiTables.label(str(hint["text"]), FcUiTokens.TYPE_BODY)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 160
	panel.body.add_child(text)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	row.add_child(FcButton.make("Got it", FcButton.Variant.PRIMARY, func() -> void:
		dismiss(id)
		if is_instance_valid(panel):
			panel.get_parent().remove_child(panel)
			panel.queue_free()))
	row.add_child(FcButton.make("Turn hints off", FcButton.Variant.GHOST, func() -> void:
		_prefs.hints_enabled = false
		_prefs.save_file()
		if is_instance_valid(panel):
			panel.get_parent().remove_child(panel)
			panel.queue_free()))
	panel.body.add_child(row)
	return panel
