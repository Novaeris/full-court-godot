class_name FcDynastyStore
extends RefCounted
## Reads and writes Dynasty profile files (user://dynasty/<slot>.dyn). This is the storage boundary: services only call
## save() and load_slot(), so a different (for example server-side) implementation could replace it later.
##
## Same safety as the main save system: line 1 is a header (version, SHA-256 and size of the payload), the rest is the
## payload JSON. A save is written to <slot>.dyn.tmp, read back and verified, the previous file is kept as .bak, and
## only then is the new file moved into place. Loading falls back to the temp file and then the backup.

const EXTENSION := ".dyn"
const FORMAT := "fc_dynasty_profile"

var base_dir: String
var migrator := FcDynastyMigrator.new()
## Overridable only for tests of the migration chain.
var current_version: int = FcVersion.DYNASTY_DATA_VERSION


func _init(directory: String = "user://dynasty") -> void:
	base_dir = directory


static func is_valid_slot(slot: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9_]{1,32}$")
	return re.search(slot) != null


func has_slot(slot: String) -> bool:
	return is_valid_slot(slot) and (FileAccess.file_exists(_path(slot)) or FileAccess.file_exists(_path(slot) + ".bak"))


## Slot names that have a profile file, sorted.
func list_slots() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(EXTENSION) and is_valid_slot(f.trim_suffix(EXTENSION)):
			out.append(f.trim_suffix(EXTENSION))
	out.sort()
	return out


func save(slot: String, profile: FcDynastyProfile) -> FcDynastyResult:
	if not is_valid_slot(slot):
		return FcDynastyResult.failure("invalid_slot", "'%s' is not a valid Dynasty save name." % slot)
	if DirAccess.make_dir_recursive_absolute(base_dir) != OK:
		return FcDynastyResult.failure("write_failed", "Could not create the Dynasty save folder.")
	var payload := JSON.stringify(profile.to_dict())
	var header := {"format": FORMAT, "data_version": current_version, "sha256": payload.sha256_text(),
		"bytes": payload.to_utf8_buffer().size(), "slot": slot}
	var main_path := _path(slot)
	var tmp_path := main_path + ".tmp"
	var bak_path := main_path + ".bak"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FcDynastyResult.failure("write_failed", "Could not write the Dynasty save file.")
	file.store_string(JSON.stringify(header) + "\n" + payload)
	file.flush()
	file.close()
	if _read_verified(tmp_path).is_empty():
		DirAccess.remove_absolute(tmp_path)
		return FcDynastyResult.failure("write_failed", "The Dynasty save could not be verified after writing.")
	if FileAccess.file_exists(main_path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		if DirAccess.rename_absolute(main_path, bak_path) != OK:
			return FcDynastyResult.failure("write_failed", "Could not rotate the previous Dynasty save.")
	if DirAccess.rename_absolute(tmp_path, main_path) != OK:
		return FcDynastyResult.failure("write_failed", "Could not finalize the Dynasty save file.")
	return FcDynastyResult.success()


## On success data["profile"] is the FcDynastyProfile and data["recovered_from"] is "", "temp" or "backup".
func load_slot(slot: String) -> FcDynastyResult:
	if not is_valid_slot(slot):
		return FcDynastyResult.failure("invalid_slot", "'%s' is not a valid Dynasty save name." % slot)
	var any := false
	var first_failure: FcDynastyResult = null
	for candidate in [["", _path(slot)], ["temp", _path(slot) + ".tmp"], ["backup", _path(slot) + ".bak"]]:
		if not FileAccess.file_exists(candidate[1]):
			continue
		any = true
		var read := _read_verified(candidate[1])
		if read.is_empty():
			if first_failure == null:
				first_failure = FcDynastyResult.failure("corrupt", "The Dynasty save file is damaged.")
			continue
		if int(read["data_version"]) > current_version:
			return FcDynastyResult.failure("unsupported_version",
				"This Dynasty save was made by a newer version of the game (version %d, this game supports %d)." % [int(read["data_version"]), current_version])
		var migrated := migrator.migrate(read["payload"], int(read["data_version"]), current_version)
		if not migrated["ok"]:
			return FcDynastyResult.failure("migration_failed", str(migrated["message"]))
		var profile := FcDynastyProfile.from_dict(migrated["payload"])
		return FcDynastyResult.success({"profile": profile, "recovered_from": candidate[0]})
	if not any:
		return FcDynastyResult.failure("not_found", "No Dynasty save exists in '%s'." % slot)
	return first_failure


func delete_slot(slot: String) -> void:
	if not is_valid_slot(slot):
		return
	for p in [_path(slot), _path(slot) + ".tmp", _path(slot) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _path(slot: String) -> String:
	return base_dir.path_join(slot + EXTENSION)


## {} when the file is missing or damaged, else {"payload": Dictionary, "data_version": int}.
func _read_verified(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var newline := text.find("\n")
	if text.is_empty() or newline < 0:
		return {}
	var header = FcChecks.parse_json(text.substr(0, newline))
	if not (header is Dictionary) or str(header.get("format", "")) != FORMAT:
		return {}
	var payload_text := text.substr(newline + 1)
	if payload_text.to_utf8_buffer().size() != int(header.get("bytes", -1)) or payload_text.sha256_text() != str(header.get("sha256", "")):
		return {}
	var payload = FcChecks.parse_json(payload_text)
	if not (payload is Dictionary):
		return {}
	return {"payload": payload, "data_version": int(header.get("data_version", 0))}
