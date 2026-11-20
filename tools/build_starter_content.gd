extends SceneTree
## Rebuilds the small starter content release bundled with the game (data/content_starter).
## It is the last fallback when no published release can be loaded. It goes through the real
## publisher into a scratch store, then the finished release folder is copied into the project.
## Run: ./tools/build_starter_content.ps1   (then commit the result).

const SCRATCH := "user://starter_build"
const OUTPUT := "res://data/content_starter"


func _init() -> void:
	FcSafeFile.remove_tree(SCRATCH)
	var defs := FcDefinitionSet.load_default()
	var store := FcLocalContentStore.new(SCRATCH)
	var workspace := FcDraftWorkspace.new(SCRATCH.path_join("drafts"), defs)
	var draft := workspace.create_draft("Starter content", 1700000000)
	workspace.save_definition(draft, "players/starter_guard.json", {
		"player_id": "starter_guard", "display_name": "Starter Guard", "position": "PG",
		"attributes": {"three_point": 70, "ball_handling": 72, "passing": 68}})
	workspace.save_definition(draft, "players/starter_big.json", {
		"player_id": "starter_big", "display_name": "Starter Big", "position": "C",
		"attributes": {"rebounding": 74, "interior_defense": 70, "close_finishing": 68}})
	workspace.save_definition(draft, "cards/starter_guard_base.json", {
		"card_id": "starter_guard_base", "player_id": "starter_guard", "title": "Starter Guard",
		"rarity": "common", "revision": 1, "requires_features": ["card_rarity_v1"]})
	workspace.save_definition(draft, "cards/starter_big_base.json", {
		"card_id": "starter_big_base", "player_id": "starter_big", "title": "Starter Big",
		"rarity": "common", "revision": 1, "requires_features": ["card_rarity_v1"]})
	workspace.save_definition(draft, "packs/starter_pack.json", {
		"pack_id": "starter_pack", "name": "Starter Pack",
		"card_ids": ["starter_guard_base", "starter_big_base"], "requires_features": ["pack_fixed_v1"]})
	var publisher := FcPublisher.new(store, defs)
	publisher.clock = func() -> int: return 1700000000
	var content := workspace.content_dir(draft)
	var approval := FcApproval.grant("Full Court build tool", "Bundled starter content (fallback when no release loads)",
		FcPublisher.draft_hash(content))
	var result := publisher.publish(content, approval)
	if not result.is_ok():
		printerr("Starter build failed: %s %s" % [result.message, str(result.problems)])
		quit(1)
		return
	var manifest: FcContentManifest = result.value
	var output := ProjectSettings.globalize_path(OUTPUT)
	FcSafeFile.remove_tree(output)
	var source := store.release_dir(manifest.release_id)
	for p in FcSafeFile.list_files(source):
		FcSafeFile.copy_file(source.path_join(p), output.path_join(p))
	FcSafeFile.remove_tree(SCRATCH)
	print("Starter content written to %s (release %s)" % [output, manifest.release_id])
	quit(0)
