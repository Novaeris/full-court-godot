class_name FcSaveMetadata
extends RefCounted
## The summary of a save slot shown in the "Load Game" list. It is stored in
## the first line of the save file so the list can be built without reading
## (or understanding) the whole save.

const FORMAT_NAME := "fullcourt-save"
const FORMAT_VERSION := 1  # layout of the file itself (header + payload)

var slot_id: String = ""
var label: String = ""
var mode: String = ""
var team_name: String = ""
var season: int = 0
var game_version: String = ""
var data_version: int = 0
var saved_at: String = ""
var payload_sha256: String = ""
var payload_bytes: int = 0
## Set by FcSaveManager.list_slots(): false if the header could not be read.
var readable: bool = true
## Set by FcSaveManager.list_slots(): a backup copy exists for this slot.
var has_backup: bool = false


static func from_state(slot: String, text_label: String, state: FcGameState) -> FcSaveMetadata:
	var m := FcSaveMetadata.new()
	m.slot_id = slot
	m.label = text_label
	m.mode = state.mode
	m.team_name = state.user_team_name()
	m.season = state.current_season
	m.game_version = FcVersion.GAME_VERSION
	m.data_version = FcVersion.DATA_VERSION
	m.saved_at = Time.get_datetime_string_from_system(true)
	return m


func to_header_dict() -> Dictionary:
	return {
		"format": FORMAT_NAME, "format_version": FORMAT_VERSION,
		"slot_id": slot_id, "label": label, "mode": mode, "team_name": team_name,
		"season": season, "game_version": game_version, "data_version": data_version,
		"saved_at": saved_at, "payload_sha256": payload_sha256, "payload_bytes": payload_bytes,
	}


## Returns null if this is not a header of a Full Court save.
static func from_header_dict(data: Dictionary) -> FcSaveMetadata:
	if str(data.get("format", "")) != FORMAT_NAME:
		return null
	var m := FcSaveMetadata.new()
	m.slot_id = str(data.get("slot_id", ""))
	m.label = str(data.get("label", ""))
	m.mode = str(data.get("mode", ""))
	m.team_name = str(data.get("team_name", ""))
	m.season = int(data.get("season", 0))
	m.game_version = str(data.get("game_version", ""))
	m.data_version = int(data.get("data_version", 0))
	m.saved_at = str(data.get("saved_at", ""))
	m.payload_sha256 = str(data.get("payload_sha256", ""))
	m.payload_bytes = int(data.get("payload_bytes", 0))
	if int(data.get("format_version", 0)) != FORMAT_VERSION:
		return null
	return m
