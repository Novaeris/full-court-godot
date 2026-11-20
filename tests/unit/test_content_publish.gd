extends FcTestCase
## Publishing: approval, immutability, versioning, crash-safe activation, the draft workspace.

var defs: FcDefinitionSet
var root: String
var store: FcLocalContentStore
var workspace: FcDraftWorkspace
var publisher: FcPublisher
var draft: String
var clock_value: int = 1700000000


func before_each() -> void:
	FcContentFixture.wipe()
	defs = FcTestData.defs()
	root = FcContentFixture.ROOT.path_join("root")
	store = FcLocalContentStore.new(root)
	workspace = FcDraftWorkspace.new(root.path_join("drafts"), defs)
	publisher = FcPublisher.new(store, defs)
	publisher.clock = func() -> int: return clock_value
	draft = workspace.create_draft("Season One", clock_value)
	FcContentFixture.write_sample_content(workspace.content_dir(draft))


func after_each() -> void:
	FcContentFixture.wipe()


func _approve(note: String = "looks right") -> FcApproval:
	return FcApproval.grant("Owner", note, FcSafeFile.hash_tree(workspace.content_dir(draft)))


func _publish() -> FcContentResult:
	return publisher.publish(workspace.content_dir(draft), _approve())


func _active() -> String:
	return str(store.read_active().value)


func test_publish_creates_an_active_release() -> void:
	var r := _publish()
	assert_true(r.is_ok(), "published: %s %s" % [r.message, str(r.problems)])
	var m: FcContentManifest = r.value
	assert_true(FcContentManifest.is_valid_release_id(m.release_id), "release id format")
	assert_eq(m.content_version, 1, "first content version")
	assert_eq(m.previous_release_id, "", "first release has no predecessor")
	assert_eq(m.approved_by, "Owner", "approval recorded")
	assert_eq(m.published_at, clock_value, "publication time recorded")
	assert_eq(m.requires_features, ["card_rarity_v1", "pack_fixed_v1"], "features collected from the definitions")
	assert_eq(_active(), m.release_id, "the pointer names the new release")
	assert_true(FcContentValidator.validate_release_dir(store.release_dir(m.release_id), FcVersion.GAME_VERSION, defs).is_ok(),
		"the published folder verifies")


func test_publish_requires_an_approval_that_matches_the_draft() -> void:
	var dir := workspace.content_dir(draft)
	assert_eq(publisher.publish(dir, null).code, FcContentResult.Code.NOT_APPROVED, "no approval")
	assert_true(FcApproval.grant("", "note", "h") == null and FcApproval.grant("Owner", " ", "h") == null,
		"an approval needs a named approver and a note")
	var stale := _approve()
	workspace.save_definition(draft, "packs/extra.json", {"pack_id": "extra", "name": "Extra", "card_ids": ["sample_big_base"]})
	assert_eq(publisher.publish(dir, stale).code, FcContentResult.Code.NOT_APPROVED, "draft changed after approval")
	assert_true(store.list_release_ids().is_empty(), "nothing was published")
	assert_eq(_active(), "", "no active release")


func test_an_approval_cannot_be_reused() -> void:
	var approval := _approve()
	assert_true(publisher.publish(workspace.content_dir(draft), approval).is_ok(), "first use")
	assert_true(approval.is_used(), "consumed")
	assert_eq(publisher.publish(workspace.content_dir(draft), approval).code, FcContentResult.Code.NOT_APPROVED, "second use")
	assert_eq(store.list_release_ids().size(), 1, "still one release")


func test_an_approval_for_one_draft_cannot_publish_another() -> void:
	var other := workspace.create_draft("Other", clock_value)
	FcContentFixture.write_sample_content(workspace.content_dir(other), " B")
	var approval_for_first := _approve()
	assert_eq(publisher.publish(workspace.content_dir(other), approval_for_first).code,
		FcContentResult.Code.NOT_APPROVED, "different draft content")


func test_editing_saving_and_validating_never_publish() -> void:
	workspace.save_definition(draft, "packs/another.json", {"pack_id": "another", "name": "A", "card_ids": ["sample_big_base"]})
	workspace.save_art(draft, "art/new.png", PackedByteArray([1, 2, 3]))
	assert_true(workspace.validate(draft).is_ok(), "valid")
	assert_true(store.list_release_ids().is_empty(), "no release")
	assert_eq(_active(), "", "no active pointer")
	assert_true(not FileAccess.file_exists(root.path_join("active.json")), "no pointer file")
	var source := FileAccess.get_file_as_string("res://src/content/draft_workspace.gd")
	for forbidden in ["FcPublisher", "commit_release", "set_active", "FcLocalContentStore", "FcApproval"]:
		assert_true(not source.contains(forbidden), "the workspace never refers to %s" % forbidden)


func test_invalid_drafts_are_not_published() -> void:
	workspace.save_definition(draft, "cards/bad.json", {"card_id": "bad", "player_id": "nobody", "title": "x", "rarity": "common", "revision": 1})
	var r := _publish()
	assert_eq(r.code, FcContentResult.Code.INVALID, "invalid draft")
	assert_true(str(r.problems).contains("nobody"), "problem listed")
	assert_true(store.list_release_ids().is_empty(), "nothing stored")


func test_second_publish_chains_to_the_first_and_leaves_it_untouched() -> void:
	var first: FcContentManifest = _publish().value
	var before := FcSafeFile.hash_tree(store.release_dir(first.release_id))
	clock_value += 100
	workspace.save_definition(draft, "packs/extra.json", {"pack_id": "extra", "name": "Extra", "card_ids": ["sample_big_base"]})
	var second_result := _publish()
	assert_true(second_result.is_ok(), "second publish: %s %s" % [second_result.message, str(second_result.problems)])
	var second: FcContentManifest = second_result.value
	assert_eq(second.previous_release_id, first.release_id, "previous release reference")
	assert_eq(second.content_version, 2, "content version increases")
	assert_true(second.release_id != first.release_id, "new release id")
	assert_eq(_active(), second.release_id, "new release active")
	assert_eq(FcSafeFile.hash_tree(store.release_dir(first.release_id)), before, "the old release is byte-for-byte unchanged")
	assert_eq(store.list_release_ids().size(), 2, "both releases kept")


func test_existing_release_id_is_never_overwritten() -> void:
	var m: FcContentManifest = _publish().value
	var again := FcContentFixture.ROOT.path_join("again")
	FcContentFixture.build_release(workspace.content_dir(draft), again, m.release_id)
	var r := store.commit_release(again, m.release_id)
	assert_eq(r.code, FcContentResult.Code.ALREADY_EXISTS, "same id refused")
	assert_eq(FcSafeFile.hash_tree(store.release_dir(m.release_id)),
		FcSafeFile.hash_tree(store.release_dir(m.release_id)), "still readable")
	assert_true(FcContentValidator.validate_release_dir(store.release_dir(m.release_id), FcVersion.GAME_VERSION, defs).is_ok(),
		"the original still verifies")


func test_published_files_are_read_only_on_windows() -> void:
	if OS.get_name() != "Windows":
		return
	var m: FcContentManifest = _publish().value
	var f := FileAccess.open(store.release_dir(m.release_id).path_join("players/sample_big.json"), FileAccess.WRITE)
	assert_true(f == null, "a published file cannot be opened for writing")


func test_card_revision_rule_applies_when_publishing() -> void:
	_publish()
	var changed := {"card_id": "sample_big_base", "player_id": "sample_big", "title": "Renamed",
		"rarity": "rare", "revision": 1}
	workspace.save_definition(draft, "cards/sample_big_base.json", changed)
	var r := _publish()
	assert_eq(r.code, FcContentResult.Code.INVALID, "changed without a new revision")
	assert_true(str(r.problems).contains("higher revision"), "explains why")
	changed["revision"] = 2
	workspace.save_definition(draft, "cards/sample_big_base.json", changed)
	assert_true(_publish().is_ok(), "a higher revision is accepted")


func test_interrupted_commit_leaves_no_release_and_keeps_the_old_one() -> void:
	var first: FcContentManifest = _publish().value
	workspace.save_definition(draft, "packs/extra.json", {"pack_id": "extra", "name": "Extra", "card_ids": ["sample_big_base"]})
	for stage in ["commit_before_rename"]:
		store.fail_at = stage
		var r := _publish()
		assert_true(not r.is_ok(), "interrupted at %s" % stage)
		assert_eq(store.list_release_ids(), [first.release_id], "no partial release after %s" % stage)
		assert_eq(_active(), first.release_id, "old release still active after %s" % stage)
	store.fail_at = ""
	assert_true(_publish().is_ok(), "publishing works again after an interruption")
	assert_eq(store.list_release_ids().size(), 2, "now two releases")


func test_interrupted_pointer_swap_keeps_the_previous_release_usable() -> void:
	var first: FcContentManifest = _publish().value
	workspace.save_definition(draft, "packs/extra.json", {"pack_id": "extra", "name": "Extra", "card_ids": ["sample_big_base"]})
	for stage in ["pointer_after_tmp", "pointer_after_backup"]:
		store.fail_at = stage
		var r := _publish()
		assert_true(not r.is_ok(), "interrupted at %s" % stage)
		assert_eq(_active(), first.release_id, "the previous release is still the active one after %s" % stage)
		store.fail_at = ""
		# Clean the extra stored-but-inactive release so the next stage starts from the same place.
		for id in store.list_release_ids():
			if id != first.release_id:
				FcSafeFile.remove_tree(store.release_dir(id))
		DirAccess.remove_absolute(root.path_join("active.json.tmp"))
		if not FileAccess.file_exists(root.path_join("active.json")) and FileAccess.file_exists(root.path_join("active.json.bak")):
			DirAccess.rename_absolute(root.path_join("active.json.bak"), root.path_join("active.json"))


func test_pointer_survives_damage_via_backup_and_rejects_tampering() -> void:
	var first: FcContentManifest = _publish().value
	clock_value += 5
	workspace.save_definition(draft, "packs/extra.json", {"pack_id": "extra", "name": "Extra", "card_ids": ["sample_big_base"]})
	var second: FcContentManifest = _publish().value
	FcSafeFile.write_text(root.path_join("active.json"), "{ broken")
	assert_eq(_active(), first.release_id, "a damaged pointer falls back to the kept previous pointer")
	FcSafeFile.write_text(root.path_join("active.json"), JSON.stringify({"format": "fc_active_pointer",
		"release_id": second.release_id, "content_version": 2, "pointer_checksum": "forged"}))
	assert_eq(_active(), first.release_id, "a pointer with a wrong checksum is not believed")


func test_set_active_refuses_unknown_or_damaged_releases() -> void:
	var m: FcContentManifest = _publish().value
	assert_eq(store.set_active("fcr_ffffffffffffffff").code, FcContentResult.Code.NOT_FOUND, "unknown release")
	FcSafeFile.set_read_only(store.release_dir(m.release_id).path_join("players/sample_big.json"), false)
	FcSafeFile.write_text(store.release_dir(m.release_id).path_join("players/sample_big.json"), "{}")
	assert_true(not store.set_active(m.release_id).is_ok(), "a release that no longer verifies cannot be activated")


func test_draft_workspace_basics() -> void:
	assert_eq(workspace.create_draft("!!!"), "", "a name with no usable letters")
	var second := workspace.create_draft("Season One")
	assert_eq(second, "season_one_2", "ids stay unique")
	assert_eq(workspace.list_drafts().size(), 2, "listed")
	assert_true(not workspace.save_definition(draft, "../escape.json", {}).is_ok(), "no escaping the draft")
	assert_true(not workspace.save_definition(draft, "art/x.json", {}).is_ok(), "definitions go in definition folders")
	assert_true(not workspace.save_art(draft, "players/x.png", PackedByteArray()).is_ok(), "art goes in art/")
	workspace.delete_draft(second)
	assert_true(not workspace.has_draft(second), "deleted")
