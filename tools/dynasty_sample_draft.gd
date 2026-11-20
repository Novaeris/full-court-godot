extends SceneTree
## Creates a Creator Studio DRAFT named "SAMPLE (test data, not official)" in your real content folder, so you can try Dynasty
## Mode end to end: open the draft in Creator Studio, check it, approve and publish it, then start Dynasty.
## It is invented test data (30 players named like "Test Alpha") and is NEVER published by this tool; official players are
## always yours to create. Delete the draft and the release afterwards if you do not want them.
## Run: ./tools/dynasty_sample_draft.ps1


func _init() -> void:
	var prefs := FcPreferences.new()
	var root := prefs.effective_content_root()
	var workspace := FcDraftWorkspace.new(root.path_join("drafts"), FcDefinitionSet.load_default())
	var id := workspace.create_draft("SAMPLE (test data, not official)", int(Time.get_unix_time_from_system()))
	if id == "":
		print("Could not create the draft in ", root)
		quit(1)
		return
	FcDynastyFixture.write_content(workspace.content_dir(id), 0)
	print("Created draft '%s' in %s" % [id, root.path_join("drafts")])
	print("Open Creator Studio, choose that draft, run the check and approve it to publish.")
	quit(0)
