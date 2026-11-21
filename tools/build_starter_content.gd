extends SceneTree
## Rebuilds the bundled Founding Series release (data/content_starter, D-055: 40 players, cards, packs, challenges, a season).
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
	var draft := workspace.create_draft("Founding Series", 1700000000)
	var save := func(rel: String, data: Dictionary) -> void:
		var saved := workspace.save_definition(draft, rel, data)
		if not saved.is_ok():
			printerr("Could not save %s: %s %s" % [rel, saved.message, str(saved.problems)])
	FcDynastyFoundingContent.write_all(save, defs.attributes.keys())
	var publisher := FcPublisher.new(store, defs)
	publisher.clock = func() -> int: return 1700000000
	var content := workspace.content_dir(draft)
	var approval := FcApproval.grant("Full Court build tool", "Bundled Founding Series release (D-055): the first playable Dynasty content",
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
