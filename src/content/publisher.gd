class_name FcPublisher
extends RefCounted
## Turns an approved draft into an immutable, versioned content release.
##
## This is the ONLY code that writes releases or moves the active pointer for new content.
## Nothing that saves, edits or validates a draft refers to it (a test checks that).
##
## Order: approval check, validate the draft, check the card revision rules against the
## current release, build the release in the store's tmp area, verify and move it into
## releases/, then switch the pointer. Previous releases are never touched.

var store: FcContentStore
var definitions: FcDefinitionSet = null
var game_version: String = FcVersion.GAME_VERSION
## Seconds since 1970; tests replace it with a fixed value.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())


func _init(target_store: FcContentStore, attribute_definitions: FcDefinitionSet = null) -> void:
	store = target_store
	definitions = attribute_definitions


## Identifies the exact content of a draft (paths and raw-byte hashes). Approvals bind to it.
static func draft_hash(content_dir: String) -> String:
	return FcSafeFile.hash_tree(content_dir)


## Publishes. On success `value` is the new FcContentManifest and the release is active.
func publish(content_dir: String, approval: FcApproval) -> FcContentResult:
	var hash_now := draft_hash(content_dir)
	if approval == null or not approval.covers(hash_now):
		return FcContentResult.failure(FcContentResult.Code.NOT_APPROVED,
			"the owner has not approved this exact content (approval missing, already used, or the draft changed)")
	var problems := FcContentValidator.draft_problems(content_dir, definitions)
	if not problems.is_empty():
		return FcContentResult.failure(FcContentResult.Code.INVALID, "the draft has problems", problems)

	var active := store.read_active()
	var previous_id := ""
	var previous_version := 0
	if active.is_ok() and not str(active.value).is_empty() and store.has_release(str(active.value)):
		var prev := store.read_manifest(str(active.value))
		if prev != null:
			previous_id = prev.release_id
			previous_version = prev.content_version
	var paths := FcSafeFile.list_files(content_dir)
	if not previous_id.is_empty():
		var prev_manifest := store.read_manifest(previous_id)
		var prev_paths: Array[String] = []
		for e in prev_manifest.files:
			prev_paths.append(e["path"])
		var before := FcContentValidator.check_definitions(store.release_dir(previous_id), prev_paths)
		var now_defs := FcContentValidator.check_definitions(content_dir, paths)
		var rev := FcContentValidator.revision_problems(now_defs["defs"]["card"], before["defs"]["card"])
		if not rev.is_empty():
			return FcContentResult.failure(FcContentResult.Code.INVALID,
				"card identity rules would be broken", rev)

	var checked := FcContentValidator.check_definitions(content_dir, paths)
	var features := {}
	for kind in checked["defs"]:
		for id in checked["defs"][kind]:
			for f in checked["defs"][kind][id].get("requires_features", []):
				features[str(f)] = true

	var release_id := _new_release_id(hash_now)
	var staging := store.new_staging_dir(release_id)
	var m := FcContentManifest.new()
	m.release_id = release_id
	m.content_version = previous_version + 1
	m.schema_version = FcContentFeatures.SCHEMA_VERSION
	m.min_game_version = game_version
	var feature_list: Array = features.keys()
	feature_list.sort()
	for f in feature_list:
		m.requires_features.append(str(f))
	m.previous_release_id = previous_id
	m.published_at = int(clock.call())
	m.published_by = approval.approver
	m.approved_by = approval.approver
	m.approval_note = approval.note
	for p in paths:
		if not FcSafeFile.copy_file(content_dir.path_join(p), staging.path_join(p)):
			return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not copy '%s'" % p)
		m.files.append({
			"path": p,
			"kind": FcContentManifest.kind_for_path(p),
			"bytes": FcSafeFile.read_bytes(staging.path_join(p)).size(),
			"sha256": FcSafeFile.hash_file(staging.path_join(p)),
		})
	m.seal()
	if not FcSafeFile.write_text(staging.path_join(FcContentManifest.FILE_NAME), m.text()):
		return FcContentResult.failure(FcContentResult.Code.WRITE_FAILED, "could not write the manifest")

	var committed := store.commit_release(staging, release_id)
	if not committed.is_ok():
		return committed
	approval.consume()
	var activated := store.set_active(release_id)
	if not activated.is_ok():
		activated.message = "the release %s was stored but not activated: %s" % [release_id, activated.message]
		return activated
	return FcContentResult.success(m)


## "fcr_" plus 16 hex digits, seeded from the draft and the clock; never an id already in the store.
func _new_release_id(hash_now: String) -> String:
	var rng := FcRng.new(hash_now.hash() ^ int(clock.call()))
	while true:
		var id := "fcr_%08x%08x" % [rng.range_int(0, 0x7FFFFFFF), rng.range_int(0, 0x7FFFFFFF)]
		if not store.has_release(id):
			return id
	return ""
