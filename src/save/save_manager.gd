class_name FcSaveManager
extends RefCounted
## Saves and loads whole playthroughs to slot files.
##
## FILE LAYOUT (one file per slot, e.g. user://saves/slot_1.sav):
##   line 1:  header JSON (FcSaveMetadata) incl. SHA-256 checksum of the payload
##   rest:    payload JSON (FcGameState.to_dict())
## JSON keeps saves human-debuggable; compression/binary can be added later
## by bumping the file format version.
##
## SAFETY: a save is written to "<slot>.sav.tmp", read back and verified, the
## previous save is kept as "<slot>.sav.bak", and only then is the new file
## moved into place. At every step at least one complete, verified copy exists.
## When loading, if the main file is damaged we try the verified temp file,
## then the backup, and tell the caller which was used (recovered_from).
##
## POLICY: saving never refuses because the world has integrity problems
## (the player's progress matters more); load reports them as warnings.
## Slots: any id of 1-32 lowercase letters/digits/underscores; "autosave" is
## the reserved slot for automatic saves.

const AUTOSAVE_SLOT := "autosave"
const EXTENSION := ".sav"

var base_dir: String
var migrator := FcSaveMigrator.new()
## Version this build writes and understands. Overridable only for tests.
var current_data_version: int = FcVersion.DATA_VERSION


func _init(directory: String = "user://saves") -> void:
	base_dir = directory


static func is_valid_slot_id(slot_id: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9_]{1,32}$")
	return re.search(slot_id) != null


func save(slot_id: String, state: FcGameState, label: String = "") -> FcSaveResult:
	if not is_valid_slot_id(slot_id):
		return FcSaveResult.failure(FcSaveResult.Code.INVALID_SLOT, "'%s' is not a valid save slot name" % slot_id)
	if DirAccess.make_dir_recursive_absolute(base_dir) != OK:
		return FcSaveResult.failure(FcSaveResult.Code.WRITE_FAILED, "could not create the save folder")

	var payload_text := JSON.stringify(state.to_dict())
	var meta := FcSaveMetadata.from_state(slot_id, label, state)
	meta.data_version = current_data_version
	meta.payload_sha256 = payload_text.sha256_text()
	meta.payload_bytes = payload_text.to_utf8_buffer().size()
	var content := JSON.stringify(meta.to_header_dict()) + "\n" + payload_text

	var main_path := _path(slot_id)
	var tmp_path := main_path + ".tmp"
	var bak_path := main_path + ".bak"

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FcSaveResult.failure(FcSaveResult.Code.WRITE_FAILED, "could not write the save file")
	file.store_string(content)
	file.flush()
	file.close()

	# Verify what actually reached the disk before touching the old save.
	var check := _read_verified(tmp_path)
	if check["code"] != FcSaveResult.Code.OK:
		DirAccess.remove_absolute(tmp_path)
		return FcSaveResult.failure(FcSaveResult.Code.WRITE_FAILED, "the save could not be verified after writing")

	if FileAccess.file_exists(main_path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		if DirAccess.rename_absolute(main_path, bak_path) != OK:
			return FcSaveResult.failure(FcSaveResult.Code.WRITE_FAILED, "could not rotate the previous save")
	if DirAccess.rename_absolute(tmp_path, main_path) != OK:
		return FcSaveResult.failure(FcSaveResult.Code.WRITE_FAILED, "could not finalize the save file")

	var result := FcSaveResult.new()
	result.metadata = meta
	result.warnings.append_array(state.validate())
	return result


func autosave(state: FcGameState) -> FcSaveResult:
	return save(AUTOSAVE_SLOT, state, "Autosave")


func load_slot(slot_id: String, defs: FcDefinitionSet) -> FcSaveResult:
	if not is_valid_slot_id(slot_id):
		return FcSaveResult.failure(FcSaveResult.Code.INVALID_SLOT, "'%s' is not a valid save slot name" % slot_id)
	var main_path := _path(slot_id)
	var candidates := [["", main_path], ["temp", main_path + ".tmp"], ["backup", main_path + ".bak"]]

	var any_file := false
	var first_failure: FcSaveResult = null
	for candidate in candidates:
		if not FileAccess.file_exists(candidate[1]):
			continue
		any_file = true
		var read := _read_verified(candidate[1])
		if read["code"] != FcSaveResult.Code.OK:
			if first_failure == null:
				first_failure = FcSaveResult.failure(read["code"], read["message"])
			continue
		var result := _build_state(read, defs)
		if result.is_ok():
			result.recovered_from = candidate[0]
			return result
		if first_failure == null:
			first_failure = result
	if not any_file:
		return FcSaveResult.failure(FcSaveResult.Code.NOT_FOUND, "no save exists in slot '%s'" % slot_id)
	return first_failure


## Summaries of every slot, newest first. Slots whose header cannot be read
## are included with readable = false so the UI can offer recovery/deletion.
func list_slots() -> Array[FcSaveMetadata]:
	var out: Array[FcSaveMetadata] = []
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var slot := file_name.trim_suffix(EXTENSION)
		if not is_valid_slot_id(slot):
			continue
		var m := _read_header_only(_path(slot))
		if m == null:
			m = FcSaveMetadata.new()
			m.slot_id = slot
			m.readable = false
		m.has_backup = FileAccess.file_exists(_path(slot) + ".bak")
		out.append(m)
	out.sort_custom(func(a: FcSaveMetadata, b: FcSaveMetadata): return a.saved_at > b.saved_at)
	return out


func has_slot(slot_id: String) -> bool:
	return is_valid_slot_id(slot_id) and FileAccess.file_exists(_path(slot_id))


## Removes the slot and its backup/temp files.
func delete_slot(slot_id: String) -> FcSaveResult:
	if not is_valid_slot_id(slot_id):
		return FcSaveResult.failure(FcSaveResult.Code.INVALID_SLOT, "'%s' is not a valid save slot name" % slot_id)
	var main_path := _path(slot_id)
	var found := false
	for p in [main_path, main_path + ".bak", main_path + ".tmp"]:
		if FileAccess.file_exists(p):
			found = true
			DirAccess.remove_absolute(p)
	if not found:
		return FcSaveResult.failure(FcSaveResult.Code.NOT_FOUND, "no save exists in slot '%s'" % slot_id)
	return FcSaveResult.new()


func _path(slot_id: String) -> String:
	return base_dir.path_join(slot_id + EXTENSION)


func _read_header_only(path: String) -> FcSaveMetadata:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed = FcChecks.parse_json(file.get_line())
	if not (parsed is Dictionary):
		return null
	return FcSaveMetadata.from_header_dict(parsed)


## Reads a save file and checks header, length and checksum.
## Returns {"code", "message", "meta", "payload_text"}.
func _read_verified(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var newline := text.find("\n")
	if text.is_empty() or newline < 0:
		return {"code": FcSaveResult.Code.CORRUPT, "message": "the save file is empty or truncated"}
	var header = FcChecks.parse_json(text.substr(0, newline))
	var meta: FcSaveMetadata = FcSaveMetadata.from_header_dict(header) if header is Dictionary else null
	if meta == null:
		return {"code": FcSaveResult.Code.CORRUPT, "message": "the save file is not a valid Full Court save"}
	var payload_text := text.substr(newline + 1)
	if payload_text.to_utf8_buffer().size() != meta.payload_bytes \
			or payload_text.sha256_text() != meta.payload_sha256:
		return {"code": FcSaveResult.Code.CORRUPT, "message": "the save file is damaged (checksum mismatch)"}
	return {"code": FcSaveResult.Code.OK, "message": "", "meta": meta, "payload_text": payload_text}


func _build_state(read: Dictionary, defs: FcDefinitionSet) -> FcSaveResult:
	var meta: FcSaveMetadata = read["meta"]
	if meta.data_version > current_data_version:
		return FcSaveResult.failure(FcSaveResult.Code.UNSUPPORTED_VERSION,
			"this save was made by a newer version of the game (save version %d, this game supports up to %d)"
			% [meta.data_version, current_data_version])
	var payload = FcChecks.parse_json(read["payload_text"])
	if not (payload is Dictionary):
		return FcSaveResult.failure(FcSaveResult.Code.CORRUPT, "the save contents could not be read")
	var migrated := migrator.migrate(payload, meta.data_version, current_data_version)
	if not migrated["ok"]:
		return FcSaveResult.failure(FcSaveResult.Code.MIGRATION_FAILED, migrated["message"])
	var result := FcSaveResult.new()
	var load_errors: Array[String] = []
	result.state = FcGameState.from_dict(migrated["payload"], defs, load_errors)
	result.warnings.append_array(load_errors)
	result.warnings.append_array(result.state.validate())
	result.metadata = meta
	return result
