class_name FcUiState
extends RefCounted
## UI-only memory (D-048): things the interface remembers for the player's comfort that are NOT game data, kept in user://ui_state.cfg:
## which cards a Dynasty profile has already looked at (so new cards can wear a NEW marker), the collection's browse mode, and similar.
## It is not a save: deleting the file loses nothing but those markers, it never touches the Dynasty save, and a missing or damaged file
## just means defaults. The first time a profile is seen, every card it already owns counts as seen (so nothing floods with NEW).

const DEFAULT_PATH := "user://ui_state.cfg"
const SEEN_LIMIT := 5000

var path: String
var _cfg := ConfigFile.new()


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	_cfg.load(path)   # a missing or damaged file leaves it empty


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _cfg.get_value(section, key, default)


## Remembers a value (written at once; a failed write is ignored: the interface just forgets).
func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	_cfg.save(path)


func is_baselined(profile_id: String) -> bool:
	return bool(_cfg.get_value("seen:" + profile_id, "baselined", false))


## The card ids this profile has already looked at.
func seen_cards(profile_id: String) -> Array:
	return _cfg.get_value("seen:" + profile_id, "ids", [])


func mark_seen(profile_id: String, card_ids: Array) -> void:
	var seen: Array = seen_cards(profile_id).duplicate()
	for id in card_ids:
		if not seen.has(str(id)):
			seen.append(str(id))
	if seen.size() > SEEN_LIMIT:
		seen = seen.slice(seen.size() - SEEN_LIMIT)
	_cfg.set_value("seen:" + profile_id, "ids", seen)
	_cfg.set_value("seen:" + profile_id, "baselined", true)
	_cfg.save(path)


## The owned cards the player has not looked at yet. The first call for a profile marks everything owned as seen and returns none.
func new_cards(profile_id: String, owned_ids: Array) -> Array:
	if not is_baselined(profile_id):
		mark_seen(profile_id, owned_ids)
		return []
	var seen := seen_cards(profile_id)
	var out: Array = []
	for id in owned_ids:
		if not seen.has(str(id)):
			out.append(str(id))
	return out


## Forgets a profile (when it is deleted).
func forget(profile_id: String) -> void:
	if _cfg.has_section("seen:" + profile_id):
		_cfg.erase_section("seen:" + profile_id)
		_cfg.save(path)
