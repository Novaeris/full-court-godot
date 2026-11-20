class_name FcSafeFile
extends RefCounted
## Small, careful file helpers shared by the content publisher and loader.
##
## WHY: content files are trusted definitions of players and cards, so every read
## and write goes through these checks: hashes are over raw bytes (never a text
## rendering), relative paths can never leave their release folder, and the active
## pointer is swapped so at every moment one complete copy exists.

## Longest relative path accepted inside a release.
const MAX_PATH_LENGTH := 160


## SHA-256 (lowercase hex) of raw bytes.
static func hash_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## SHA-256 of a file's actual bytes ("" if unreadable). Used for JSON and artwork alike.
static func hash_file(path: String) -> String:
	return FileAccess.get_sha256(path)


## The one text form hashed for manifests: sorted keys at every level, compact, UTF-8.
static func canonical_text(value: Variant) -> String:
	return JSON.stringify(value, "", true)


static func hash_text(text: String) -> String:
	return hash_bytes(text.to_utf8_buffer())


## True only for plain forward-slash relative paths that stay inside their folder:
## no absolute paths, drive letters, backslashes, "." or ".." parts, or empty parts.
static func is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.length() > MAX_PATH_LENGTH:
		return false
	if path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	for part in path.split("/"):
		if part.is_empty() or part == "." or part == ".." or part.begins_with(" ") \
				or part.ends_with(" ") or part.ends_with("."):
			return false
	return true


static func make_dir(path: String) -> bool:
	return DirAccess.make_dir_recursive_absolute(path) == OK


## Writes bytes to `path` (folders created), flushes and reads the size back.
static func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	if not make_dir(path.get_base_dir()):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	file.close()
	return FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() == bytes.size()


static func write_text(path: String, text: String) -> bool:
	return write_bytes(path, text.to_utf8_buffer())


static func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


## Parsed JSON object from a file, or null if missing, damaged or not an object.
static func read_json_object(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed = FcChecks.parse_json(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else null


static func copy_file(from_path: String, to_path: String) -> bool:
	return write_bytes(to_path, read_bytes(from_path))


## Every file under `root` as sorted forward-slash relative paths.
static func list_files(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, "", out)
	out.sort()
	return out


static func _walk(root: String, prefix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root.path_join(prefix) if not prefix.is_empty() else root)
	if dir == null:
		return
	for f in dir.get_files():
		out.append(prefix + f)
	for d in dir.get_directories():
		_walk(root, prefix + d + "/", out)


## One hash for a whole folder: every relative path with the hash of its raw bytes.
static func hash_tree(root: String) -> String:
	var lines: Array[String] = []
	for p in list_files(root):
		lines.append("%s:%s" % [p, hash_file(root.path_join(p))])
	return hash_text("\n".join(lines))


## Marks a file read-only where the OS supports it (published releases are never edited).
static func set_read_only(path: String, read_only: bool) -> void:
	FileAccess.set_read_only_attribute(path, read_only)


## Deletes a folder and everything in it, clearing read-only flags first.
static func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		var fp := path.path_join(f)
		FileAccess.set_read_only_attribute(fp, false)
		DirAccess.remove_absolute(fp)
	for d in dir.get_directories():
		remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


## Compares "1.2.3" style versions: -1, 0 or 1 (missing parts count as 0).
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0
