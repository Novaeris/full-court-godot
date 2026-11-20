class_name FcLocalContentStore
extends FcContentStore
## Content releases in an ordinary folder (the shared content directory).
##
## Layout: <root>/releases/<release_id>/  (immutable)   <root>/tmp/  (unfinished work)
##         <root>/active.json  (+ active.json.bak while a swap is in progress)
##
## CRASH SAFETY: a release is built in tmp/, verified, then renamed into releases/ in one
## step; only after that does the pointer change. The pointer is replaced by: write
## active.json.tmp, move the old active.json to .bak, move the temp into place, read it
## back. Reading uses active.json, then .bak (never the unconfirmed .tmp), so at every
## moment the previously active release stays usable until the new pointer is confirmed.

const ACTIVE_FILE := "active.json"
const POINTER_FORMAT := "fc_active_pointer"

var _root: String
## Needed only to check attribute names while verifying (optional).
var definitions: FcDefinitionSet = null
var game_version: String = FcVersion.GAME_VERSION
## TESTS ONLY: name of a step at which to stop and report failure, simulating a crash:
## "commit_before_rename", "commit_after_rename", "pointer_after_tmp", "pointer_after_backup",
## "pointer_after_swap".
var fail_at: String = ""


func _init(root: String) -> void:
	_root = root


func root_dir() -> String:
	return _root


func releases_dir() -> String:
	return _root.path_join("releases")


func tmp_dir() -> String:
	return _root.path_join("tmp")


func _active_path() -> String:
	return _root.path_join(ACTIVE_FILE)


func list_release_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(releases_dir())
	if dir == null:
		return out
	for d in dir.get_directories():
		if FcContentManifest.is_valid_release_id(d):
			out.append(d)
	out.sort()
	return out


func has_release(release_id: String) -> bool:
	return FcContentManifest.is_valid_release_id(release_id) \
			and DirAccess.dir_exists_absolute(releases_dir().path_join(release_id))


func release_dir(release_id: String) -> String:
	return releases_dir().path_join(release_id)


func read_manifest(release_id: String) -> FcContentManifest:
	if not FcContentManifest.is_valid_release_id(release_id):
		return null
	return FcContentManifest.from_file(release_dir(release_id).path_join(FcContentManifest.FILE_NAME))


func new_staging_dir(release_id: String) -> String:
	# Old unfinished work is never reused: start clean every time.
	FcSafeFile.remove_tree(tmp_dir().path_join("stage_" + release_id))
	var path := tmp_dir().path_join("stage_" + release_id)
	FcSafeFile.make_dir(path)
	return path


func commit_release(staging_dir: String, release_id: String) -> FcContentResult:
	if not FcContentManifest.is_valid_release_id(release_id):
		return FcContentResult.failure(FcContentResult.Code.INVALID, "'%s' is not a valid release id" % release_id)
	if has_release(release_id):
		return FcContentResult.failure(FcContentResult.Code.ALREADY_EXISTS,
			"release %s already exists and is never overwritten" % release_id)
	var check := FcContentValidator.validate_release_dir(staging_dir, game_version, definitions)
	if not check.is_ok():
		return check
	if (check.value as FcContentManifest).release_id != release_id:
		return FcContentResult.failure(FcContentResult.Code.INVALID, "the manifest names a different release id")
	if fail_at == "commit_before_rename":
		return _crash("commit_before_rename")
	if not FcSafeFile.make_dir(releases_dir()):
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not create the releases folder")
	if DirAccess.rename_absolute(staging_dir, release_dir(release_id)) != OK:
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not move the release into place")
	for p in FcSafeFile.list_files(release_dir(release_id)):
		FcSafeFile.set_read_only(release_dir(release_id).path_join(p), true)
	if fail_at == "commit_after_rename":
		return _crash("commit_after_rename")
	var final_check := FcContentValidator.validate_release_dir(release_dir(release_id), game_version, definitions)
	if not final_check.is_ok():
		FcSafeFile.remove_tree(release_dir(release_id))
		return final_check
	return FcContentResult.success(release_id)


func read_active() -> FcContentResult:
	var any := false
	for path in [_active_path(), _active_path() + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		any = true
		var data = FcSafeFile.read_json_object(path)
		var id := _pointer_release(data)
		if not id.is_empty():
			return FcContentResult.success(id)
	if any:
		return FcContentResult.failure(FcContentResult.Code.CORRUPT, "the active release pointer is damaged")
	return FcContentResult.success("")


func set_active(release_id: String) -> FcContentResult:
	if not has_release(release_id):
		return FcContentResult.failure(FcContentResult.Code.NOT_FOUND, "release %s does not exist" % release_id)
	var check := FcContentValidator.validate_release_dir(release_dir(release_id), game_version, definitions)
	if not check.is_ok():
		return check
	var manifest: FcContentManifest = check.value
	var pointer := {
		"format": POINTER_FORMAT,
		"release_id": release_id,
		"content_version": manifest.content_version,
	}
	pointer["pointer_checksum"] = _pointer_checksum(pointer)
	var main := _active_path()
	var tmp := main + ".tmp"
	var bak := main + ".bak"
	if not FcSafeFile.write_text(tmp, JSON.stringify(pointer, "\t", true)):
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not write the new pointer")
	if fail_at == "pointer_after_tmp":
		return _crash("pointer_after_tmp")
	var had_main := FileAccess.file_exists(main)
	if had_main:
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		if DirAccess.rename_absolute(main, bak) != OK:
			DirAccess.remove_absolute(tmp)
			return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not keep the previous pointer")
	if fail_at == "pointer_after_backup":
		return _crash("pointer_after_backup")
	if DirAccess.rename_absolute(tmp, main) != OK:
		_restore_backup(had_main)
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not activate the release")
	if fail_at == "pointer_after_swap":
		return _crash("pointer_after_swap")
	var back := _pointer_release(FcSafeFile.read_json_object(main))
	if back != release_id:
		DirAccess.remove_absolute(main)
		_restore_backup(had_main)
		return FcContentResult.failure(FcContentResult.Code.CORRUPT, "the new pointer did not read back correctly")
	return FcContentResult.success(release_id)


func _restore_backup(had_main: bool) -> void:
	var main := _active_path()
	if had_main and FileAccess.file_exists(main + ".bak") and not FileAccess.file_exists(main):
		DirAccess.rename_absolute(main + ".bak", main)


func _crash(stage: String) -> FcContentResult:
	return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "simulated interruption at %s" % stage)


static func _pointer_checksum(pointer: Dictionary) -> String:
	return FcSafeFile.hash_text("%s|%s|%d" % [POINTER_FORMAT, str(pointer["release_id"]), int(pointer["content_version"])])


## The release id in a verified pointer, or "" when the pointer is missing or altered.
static func _pointer_release(data: Variant) -> String:
	if not (data is Dictionary) or str(data.get("format", "")) != POINTER_FORMAT:
		return ""
	var id := str(data.get("release_id", ""))
	if not FcContentManifest.is_valid_release_id(id):
		return ""
	var version := FcContentManifest._as_int(data.get("content_version"), -1)
	var check := {"release_id": id, "content_version": version}
	if _pointer_checksum(check) != str(data.get("pointer_checksum", "")):
		return ""
	return id
