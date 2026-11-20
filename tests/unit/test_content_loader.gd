extends FcTestCase
## The game side: finding, verifying and loading releases; fallback, rollback, ownership, preferences.

var defs: FcDefinitionSet
var root: String
var store: FcLocalContentStore
var workspace: FcDraftWorkspace
var publisher: FcPublisher
var loader: FcContentLoader
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
	loader = FcContentLoader.new(store, defs)
	draft = workspace.create_draft("Main", clock_value)
	FcContentFixture.write_sample_content(workspace.content_dir(draft))


func after_each() -> void:
	FcContentFixture.wipe()


## Publishes the draft as it is now; each call adds a distinguishing pack so releases differ.
func _publish_next(n: int) -> FcContentManifest:
	clock_value += 10
	workspace.save_definition(draft, "packs/extra_%d.json" % n,
		{"pack_id": "extra_%d" % n, "name": "Extra %d" % n, "card_ids": ["sample_big_base"]})
	var content := workspace.content_dir(draft)
	var r := publisher.publish(content, FcApproval.grant("Owner", "ok", FcPublisher.draft_hash(content)))
	assert_true(r.is_ok(), "publish %d: %s %s" % [n, r.message, str(r.problems)])
	return r.value


func _damage(release_id: String) -> void:
	var p := store.release_dir(release_id).path_join("players/sample_big.json")
	FcSafeFile.set_read_only(p, false)
	FcSafeFile.write_text(p, "{}")


func test_loads_the_active_release_and_reports_it() -> void:
	var m := _publish_next(1)
	var report := loader.load_active()
	assert_eq(report.loaded_release_id, m.release_id, "loaded release id is exposed")
	assert_eq(report.requested_release_id, m.release_id, "requested release id")
	assert_true(not report.is_degraded() and not report.used_starter, "normal load")
	assert_true(report.summary().contains(m.release_id), "summary names the release for logs and screens")
	var c := report.catalog
	assert_true(c.has_card("sample_guard_base") and c.packs.has("extra_1"), "definitions available")
	assert_eq(c.player_for_card("sample_guard_base")["display_name"], "Sample Guard", "player resolved from a card")
	assert_true(c.art_path("sample_guard_base").ends_with("art/sample_guard_base.png"), "art path inside the release")
	assert_true(FileAccess.file_exists(c.art_path("sample_guard_base")), "art file exists")
	assert_eq(c.art_path("sample_big_base"), "", "no art for a card without it")


func test_empty_store_uses_the_bundled_starter_without_a_warning() -> void:
	var report := loader.load_active()
	assert_true(report.used_starter and report.has_content(), "starter content loaded")
	assert_true(not report.is_degraded(), "nothing was refused")
	assert_true(report.catalog.packs.has("starter_pack"), "the real bundled starter release verifies and loads")
	assert_true(report.summary().contains("no content release has been published"), report.summary())


func test_damaged_newest_release_falls_back_visibly() -> void:
	var first := _publish_next(1)
	var second := _publish_next(2)
	_damage(second.release_id)
	var report := loader.load_active()
	assert_eq(report.loaded_release_id, first.release_id, "fell back to the previous release")
	assert_eq(report.requested_release_id, second.release_id, "still says what was requested")
	assert_true(report.is_degraded(), "flagged as degraded so the UI warns")
	assert_eq(report.rejected.size(), 1, "one release refused")
	assert_eq(report.rejected[0]["release_id"], second.release_id, "which one")
	assert_true(str(report.rejected[0]["reason"]).length() > 0, "and why")
	assert_true(report.summary().begins_with("WARNING"), report.summary())


func test_chain_walks_back_then_ends_at_the_starter() -> void:
	var first := _publish_next(1)
	var second := _publish_next(2)
	var third := _publish_next(3)
	_damage(third.release_id)
	_damage(second.release_id)
	assert_eq(loader.load_active().loaded_release_id, first.release_id, "skips two damaged releases")
	_damage(first.release_id)
	var report := loader.load_active()
	assert_true(report.used_starter, "all releases damaged: the starter")
	assert_eq(report.rejected.size(), 3, "all three refusals recorded")


func test_missing_previous_release_ends_safely() -> void:
	var first := _publish_next(1)
	var second := _publish_next(2)
	_damage(second.release_id)
	FcSafeFile.remove_tree(store.release_dir(first.release_id))
	var report := loader.load_active()
	assert_true(report.used_starter, "the starter is the last resort")
	var text := str(report.rejected)
	assert_true(text.contains("missing"), "the missing link is reported: %s" % text)


func test_cyclic_previous_references_terminate() -> void:
	var content := workspace.content_dir(draft)
	var a := "fcr_00000000000000a1"
	var b := "fcr_00000000000000b2"
	FcContentFixture.build_release(content, store.release_dir(a), a, b, 1)
	FcContentFixture.build_release(content, store.release_dir(b), b, a, 2)
	assert_true(store.set_active(b).is_ok(), "pointer set while both verify")
	_damage(a)
	_damage(b)
	var report := loader.load_active()
	assert_true(report.used_starter, "ended at the starter instead of looping")
	assert_true(str(report.rejected).contains("loops back"), "cycle reported")


func test_no_content_at_all_never_crashes() -> void:
	var bare := FcContentLoader.new(store, defs, "user://does_not_exist")
	var report := bare.load_active()
	assert_true(not report.has_content(), "nothing could load")
	assert_true(report.summary().contains("No content could be loaded"), "says so plainly")


func test_damaged_pointer_is_reported_and_starter_used() -> void:
	_publish_next(1)
	FcSafeFile.write_text(root.path_join("active.json"), "garbage")
	DirAccess.remove_absolute(root.path_join("active.json.bak"))
	var report := loader.load_active()
	assert_true(report.used_starter, "starter")
	assert_true(str(report.rejected).contains("pointer"), "pointer damage is reported")


func test_rollback_moves_only_the_pointer() -> void:
	var first := _publish_next(1)
	var second := _publish_next(2)
	var before := FcSafeFile.hash_tree(store.release_dir(second.release_id))
	assert_true(loader.rollback_to(first.release_id).is_ok(), "rolled back")
	assert_eq(loader.load_active().loaded_release_id, first.release_id, "the older release is now what loads")
	assert_eq(FcSafeFile.hash_tree(store.release_dir(second.release_id)), before, "no release folder changed")
	assert_eq(store.list_release_ids().size(), 2, "both releases kept")
	assert_true(loader.rollback_to(second.release_id).is_ok(), "and forward again")
	_damage(first.release_id)
	assert_true(not loader.rollback_to(first.release_id).is_ok(), "cannot roll back to a damaged release")
	assert_eq(loader.load_active().loaded_release_id, second.release_id, "pointer unchanged by a refused rollback")


func test_release_list_marks_validity_newest_first() -> void:
	var first := _publish_next(1)
	var second := _publish_next(2)
	_damage(first.release_id)
	var list := loader.list_releases()
	assert_eq(list[0]["release_id"], second.release_id, "newest first")
	assert_true(list[0]["valid"] and not list[1]["valid"], "validity shown")


func test_ownership_ids_survive_release_changes() -> void:
	_publish_next(1)
	var owned := ["sample_guard_base", "sample_big_base"]
	var first_report := loader.load_active()
	assert_eq(first_report.catalog.ownership_view(owned)["unavailable"], [], "everything available")
	# A later release drops the big card (and the packs that listed it).
	workspace.delete_file(draft, "cards/sample_big_base.json")
	for pack in ["packs/starter_pack.json", "packs/extra_1.json"]:
		workspace.delete_file(draft, pack)
	var content := workspace.content_dir(draft)
	clock_value += 10
	assert_true(publisher.publish(content, FcApproval.grant("Owner", "drop a card", FcPublisher.draft_hash(content))).is_ok(),
		"release without the card")
	var view := loader.load_active().catalog.ownership_view(owned)
	assert_eq(view["available"], ["sample_guard_base"], "the guard card is still the same card")
	assert_eq(view["unavailable"], ["sample_big_base"], "the missing card is kept as unavailable, not deleted")
	assert_true(loader.rollback_to(first_report.loaded_release_id).is_ok(), "rollback")
	assert_eq(loader.load_active().catalog.ownership_view(owned)["unavailable"], [], "and it is available again")


func test_card_ids_are_stable_across_releases() -> void:
	var first := _publish_next(1)
	var c1 := loader.load_active().catalog
	var second := _publish_next(2)
	var c2 := loader.load_active().catalog
	assert_true(first.release_id != second.release_id, "different releases")
	assert_eq(c1.cards.keys(), c2.cards.keys(), "the same card ids")
	assert_eq(c1.get_card("sample_guard_base"), c2.get_card("sample_guard_base"), "the same definition")


func test_preferences_content_root_falls_back_safely() -> void:
	var prefs := FcPreferences.new(FcContentFixture.ROOT.path_join("prefs.cfg"))
	assert_eq(prefs.effective_content_root(), FcPreferences.default_content_root(), "default when unset")
	for bad in ["relative/folder", "..\\up", "C:/x/../y", "  ", "/a/../b"]:
		prefs.content_root = bad
		assert_eq(prefs.effective_content_root(), FcPreferences.default_content_root(), "'%s' is refused" % bad)
	prefs.content_root = "user://chosen_content"
	assert_eq(prefs.effective_content_root(), "user://chosen_content", "a valid choice is used")
	assert_true(prefs.save_file(), "saved")
	var again := FcPreferences.new(FcContentFixture.ROOT.path_join("prefs.cfg"))
	assert_eq(again.content_root, "user://chosen_content", "the choice persists")


func test_service_loads_refreshes_and_rolls_back() -> void:
	var prefs := FcPreferences.new(FcContentFixture.ROOT.path_join("prefs.cfg"))
	prefs.content_root = root
	var service := FcContentService.new(prefs, defs)
	assert_true(service.report.used_starter, "starts on the starter: nothing published yet")
	var first := _publish_next(1)
	assert_eq(service.refresh().loaded_release_id, first.release_id, "refresh sees the new release")
	var second := _publish_next(2)
	service.refresh()
	assert_eq(service.catalog().release_id, second.release_id, "newest")
	assert_true(service.rollback_to(first.release_id).is_ok(), "rollback through the service")
	assert_eq(service.catalog().release_id, first.release_id, "service now serves the older release")
