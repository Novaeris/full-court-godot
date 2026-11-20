class_name FcContentManifest
extends RefCounted
## The description of one content release: what it is, what it needs, which files it
## contains and a checksum of each. It is the only thing the game trusts to find the rest.
##
## Numbers are integers (no floats: JSON would blur them). The manifest checksum is the
## SHA-256 of the canonical text (sorted keys, compact, UTF-8) of the manifest WITHOUT
## the `manifest_checksum` field, so the field never hashes itself.

const FORMAT := "fc_content_release"
const FILE_NAME := "manifest.json"
const ART_FOLDER := "art"
const ART_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]

var release_id: String = ""
var content_version: int = 1
var schema_version: int = FcContentFeatures.SCHEMA_VERSION
var min_game_version: String = FcVersion.GAME_VERSION
var requires_features: Array[String] = []
## "" for the first release.
var previous_release_id: String = ""
## Seconds since 1970 (an integer).
var published_at: int = 0
var published_by: String = ""
var approved_by: String = ""
var approval_note: String = ""
## Each entry: {"path": String, "kind": String, "bytes": int, "sha256": String}
var files: Array[Dictionary] = []
var manifest_checksum: String = ""

var _format_ok: bool = true
var _shape_problems: Array[String] = []


static func is_valid_release_id(text: String) -> bool:
	var re := RegEx.new()
	re.compile("^fcr_[0-9a-f]{16}$")
	return re.search(text) != null


## What kind of file a release path is: a definition kind, "art", or "" when not allowed.
static func kind_for_path(path: String) -> String:
	if not FcSafeFile.is_safe_relative_path(path):
		return ""
	var parts := path.split("/")
	if parts.size() != 2:
		return ""
	var ext := parts[1].get_extension().to_lower()
	if parts[0] == ART_FOLDER:
		return "art" if ART_EXTENSIONS.has(ext) else ""
	if FcContentFeatures.KIND_FOLDERS.has(parts[0]) and ext == "json":
		return FcContentFeatures.KIND_FOLDERS[parts[0]]
	return ""


func to_dict(include_checksum: bool = true) -> Dictionary:
	var sorted_files: Array = files.duplicate(true)
	sorted_files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))
	var d := {
		"format": FORMAT,
		"release_id": release_id,
		"content_version": content_version,
		"schema_version": schema_version,
		"min_game_version": min_game_version,
		"requires_features": requires_features.duplicate(),
		"previous_release_id": previous_release_id,
		"published_at": published_at,
		"published_by": published_by,
		"approved_by": approved_by,
		"approval_note": approval_note,
		"files": sorted_files,
	}
	if include_checksum:
		d["manifest_checksum"] = manifest_checksum
	return d


## Hash of the manifest body (everything except manifest_checksum).
func compute_checksum() -> String:
	return FcSafeFile.hash_text(FcSafeFile.canonical_text(to_dict(false)))


## Fills in manifest_checksum. Call after every other field is final.
func seal() -> void:
	manifest_checksum = compute_checksum()


func text() -> String:
	return JSON.stringify(to_dict(true), "\t", true)


## Builds a manifest from parsed JSON. Whole-number floats (how JSON returns integers)
## become ints; anything else wrong is reported by validate().
static func from_dict(data: Dictionary) -> FcContentManifest:
	var m := FcContentManifest.new()
	m.release_id = str(data.get("release_id", ""))
	m.content_version = _as_int(data.get("content_version"), -1)
	m.schema_version = _as_int(data.get("schema_version"), -1)
	m.min_game_version = str(data.get("min_game_version", ""))
	m.previous_release_id = str(data.get("previous_release_id", ""))
	m.published_at = _as_int(data.get("published_at"), -1)
	m.published_by = str(data.get("published_by", ""))
	m.approved_by = str(data.get("approved_by", ""))
	m.approval_note = str(data.get("approval_note", ""))
	m.manifest_checksum = str(data.get("manifest_checksum", ""))
	m._format_ok = str(data.get("format", "")) == FORMAT
	var feats = data.get("requires_features", [])
	if feats is Array:
		for f in feats:
			m.requires_features.append(str(f))
	else:
		m._shape_problems.append("requires_features must be a list")
	var entries = data.get("files", [])
	if entries is Array:
		for e in entries:
			if e is Dictionary:
				m.files.append({
					"path": str(e.get("path", "")),
					"kind": str(e.get("kind", "")),
					"bytes": _as_int(e.get("bytes"), -1),
					"sha256": str(e.get("sha256", "")),
				})
			else:
				m._shape_problems.append("a file entry is not an object")
	else:
		m._shape_problems.append("files must be a list")
	return m


## Reads and parses a manifest file; null when missing or not a JSON object.
static func from_file(path: String) -> FcContentManifest:
	var data = FcSafeFile.read_json_object(path)
	if data == null:
		return null
	return from_dict(data)


## Structural problems (empty = the manifest is well formed). Does not look at the disk.
func validate() -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(_shape_problems)
	if not _format_ok:
		errors.append("not a Full Court content manifest")
	if not is_valid_release_id(release_id):
		errors.append("release_id must look like fcr_ plus 16 lowercase hex digits")
	if content_version < 1:
		errors.append("content_version must be a whole number of at least 1")
	if schema_version < 1:
		errors.append("schema_version must be a whole number of at least 1")
	var ver_re := RegEx.new()
	ver_re.compile("^\\d+\\.\\d+\\.\\d+$")
	if ver_re.search(min_game_version) == null:
		errors.append("min_game_version must look like 1.2.3")
	if not previous_release_id.is_empty():
		if not is_valid_release_id(previous_release_id):
			errors.append("previous_release_id is not a valid release id")
		elif previous_release_id == release_id:
			errors.append("a release cannot follow itself")
	if published_at < 1:
		errors.append("published_at is missing")
	if published_by.strip_edges().is_empty():
		errors.append("published_by is missing")
	if approved_by.strip_edges().is_empty():
		errors.append("approved_by is missing (every release needs the owner's approval)")
	if approval_note.strip_edges().is_empty():
		errors.append("approval_note is missing")
	var hex_re := RegEx.new()
	hex_re.compile("^[0-9a-f]{64}$")
	var seen := {}
	for e in files:
		var p: String = e["path"]
		var expected_kind := kind_for_path(p)
		if expected_kind.is_empty():
			errors.append("file '%s' is not an allowed path" % p)
		elif e["kind"] != expected_kind:
			errors.append("file '%s' has kind '%s' but belongs to '%s'" % [p, e["kind"], expected_kind])
		if seen.has(p):
			errors.append("file '%s' is listed twice" % p)
		seen[p] = true
		if int(e["bytes"]) < 0:
			errors.append("file '%s' has an invalid size" % p)
		if hex_re.search(e["sha256"]) == null:
			errors.append("file '%s' has an invalid checksum" % p)
	return errors


## Why this build of the game cannot use the release (empty = compatible).
func compatibility_problems(game_version: String) -> Array[String]:
	var errors: Array[String] = []
	if schema_version > FcContentFeatures.SCHEMA_VERSION:
		errors.append("made with a newer content format (%d; this game reads up to %d): update the game"
			% [schema_version, FcContentFeatures.SCHEMA_VERSION])
	elif schema_version < FcContentFeatures.MIN_SCHEMA_VERSION:
		errors.append("made with an old content format (%d) this game no longer reads" % schema_version)
	if FcSafeFile.compare_versions(min_game_version, game_version) > 0:
		errors.append("needs game version %s or newer (this is %s)" % [min_game_version, game_version])
	for f in requires_features:
		if not FcContentFeatures.is_supported(f):
			errors.append("needs the feature '%s', which this game does not have: update the game" % f)
	return errors


static func _as_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, floorf(value)):
		return int(value)
	return fallback
