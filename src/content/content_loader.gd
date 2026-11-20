class_name FcContentLoader
extends RefCounted
## Finds, verifies and loads the active content release; falls back safely when it cannot.
##
## Order: the release the pointer names; then, release by release, the one it says it followed
## (stopping at a missing link or a cycle); then the small starter release bundled with the game.
## Every candidate is verified in full (manifest, compatibility, every file's checksum, paths,
## definitions) before it is believed. The result is a report, never an exception.

const STARTER_DIR := "res://data/content_starter"

var store: FcContentStore
var starter_dir: String
var definitions: FcDefinitionSet
var game_version: String


func _init(content_store: FcContentStore, attribute_definitions: FcDefinitionSet = null,
		starter_directory: String = STARTER_DIR, version: String = FcVersion.GAME_VERSION) -> void:
	store = content_store
	definitions = attribute_definitions
	starter_dir = starter_directory
	game_version = version


func load_active() -> FcContentLoadReport:
	var report := FcContentLoadReport.new()
	var active := store.read_active()
	if not active.is_ok():
		report.rejected.append({"release_id": "", "reason": active.message, "problems": active.problems})
	else:
		report.requested_release_id = str(active.value)
	var id := report.requested_release_id
	var visited := {}
	while not id.is_empty():
		if visited.has(id):
			report.rejected.append({"release_id": id, "reason": "the chain of previous releases loops back to it", "problems": []})
			break
		visited[id] = true
		if not store.has_release(id):
			report.rejected.append({"release_id": id, "reason": "the release folder is missing", "problems": []})
			break
		var check := FcContentValidator.validate_release_dir(store.release_dir(id), game_version, definitions)
		if check.is_ok():
			_finish(report, check.value, store.release_dir(id))
			report.loaded_release_id = id
			return report
		report.rejected.append({"release_id": id, "reason": check.message, "problems": check.problems})
		var manifest := store.read_manifest(id)
		id = manifest.previous_release_id if manifest != null and FcContentManifest.is_valid_release_id(manifest.previous_release_id) else ""
	var starter := FcContentValidator.validate_release_dir(starter_dir, game_version, definitions)
	if starter.is_ok():
		_finish(report, starter.value, starter_dir)
		report.used_starter = true
	else:
		report.rejected.append({"release_id": "starter", "reason": starter.message, "problems": starter.problems})
	return report


## Makes a different, verified release the active one (the pointer moves; no release changes).
## Does not reload by itself: call load_active() afterwards.
func rollback_to(release_id: String) -> FcContentResult:
	return store.set_active(release_id)


## Every release in the store, newest version first: [{"release_id", "content_version", "published_at",
## "valid", "problems"}]. For choosing a release to return to.
func list_releases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in store.list_release_ids():
		var check := FcContentValidator.validate_release_dir(store.release_dir(id), game_version, definitions)
		var manifest := store.read_manifest(id)
		out.append({
			"release_id": id,
			"content_version": manifest.content_version if manifest != null else 0,
			"published_at": manifest.published_at if manifest != null else 0,
			"valid": check.is_ok(),
			"problems": check.problems if not check.is_ok() else [],
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["content_version"] > b["content_version"])
	return out


func _finish(report: FcContentLoadReport, manifest: FcContentManifest, directory: String) -> void:
	var paths: Array[String] = []
	for e in manifest.files:
		paths.append(e["path"])
	var checked := FcContentValidator.check_definitions(directory, paths, definitions)
	report.catalog = FcContentCatalog.build(manifest, directory, checked["defs"])
