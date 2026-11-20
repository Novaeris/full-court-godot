extends SceneTree
## Shows the content pipeline end to end in a scratch folder (nothing in your real content folder is touched):
## publish two releases, damage the newest, watch the game's loader fall back and say why, then roll back.
## Run: ./tools/publish_demo.ps1

const ROOT := "user://publish_demo"


func _init() -> void:
	FcSafeFile.remove_tree(ROOT)
	var defs := FcDefinitionSet.load_default()
	var store := FcLocalContentStore.new(ROOT)
	var workspace := FcDraftWorkspace.new(ROOT.path_join("drafts"), defs)
	var publisher := FcPublisher.new(store, defs)
	var loader := FcContentLoader.new(store, defs)
	var draft := workspace.create_draft("Demo")
	FcContentFixture.write_sample_content(workspace.content_dir(draft))

	print("1) Before anything is published:")
	print("   ", loader.load_active().summary())

	var first := _publish(publisher, workspace, draft, "first release")
	print("2) Published ", first.release_id, " (version ", first.content_version, ")")
	workspace.save_definition(draft, "packs/extra.json", {"pack_id": "extra", "name": "Extra", "card_ids": ["sample_big_base"]})
	var second := _publish(publisher, workspace, draft, "second release")
	print("3) Published ", second.release_id, " (version ", second.content_version, ", follows ", second.previous_release_id, ")")
	print("   ", loader.load_active().summary())

	var victim := store.release_dir(second.release_id).path_join("players/sample_big.json")
	FcSafeFile.set_read_only(victim, false)
	FcSafeFile.write_text(victim, "{}")
	print("4) Damaged one file of the newest release:")
	var report := loader.load_active()
	print("   ", report.summary())
	for r in report.rejected:
		print("   refused ", r["release_id"], ": ", r["reason"], " ", r["problems"])

	print("5) Releases on disk:")
	for r in loader.list_releases():
		print("   version ", r["content_version"], " ", r["release_id"], " valid=", r["valid"])
	print("6) Rolling back to the first release: ", loader.rollback_to(first.release_id).is_ok())
	print("   ", loader.load_active().summary())
	FcSafeFile.remove_tree(ROOT)
	quit(0)


func _publish(publisher: FcPublisher, workspace: FcDraftWorkspace, draft: String, note: String) -> FcContentManifest:
	var content := workspace.content_dir(draft)
	var approval := FcApproval.grant("Demo owner", note, FcPublisher.draft_hash(content))
	var result := publisher.publish(content, approval)
	if not result.is_ok():
		printerr("publish failed: ", result.message, " ", result.problems)
		quit(1)
	return result.value
