extends FcTestCase
## Guards the "one canonical copy" rule: Creator Studio must see the game's src and data through
## links, never through second editable copies of the files.


func _files(dir_path: String) -> Array:
	var d := DirAccess.open(dir_path)
	var out := []
	if d != null:
		out.append_array(d.get_files())
		out.append_array(d.get_directories())
		out.sort()
	return out


func test_studio_links_match_the_shared_sources() -> void:
	for pair in [["creator_studio/game_src", "src"], ["creator_studio/data", "data"]]:
		var link := ProjectSettings.globalize_path("res://" + pair[0])
		assert_true(DirAccess.dir_exists_absolute(link), "%s is missing: run ./tools/link_studio.ps1" % pair[0])
		assert_eq(_files(link), _files(ProjectSettings.globalize_path("res://" + pair[1])),
			"%s must show exactly what %s contains" % [pair[0], pair[1]])


func test_studio_links_are_never_tracked_by_git() -> void:
	var ignore := FileAccess.get_file_as_string("res://.gitignore")
	assert_true(ignore.contains("/creator_studio/game_src"), ".gitignore must exclude the src link")
	assert_true(ignore.contains("/creator_studio/data"), ".gitignore must exclude the data link")


func test_supported_schema_range_is_consistent() -> void:
	assert_true(FcContentFeatures.MIN_SCHEMA_VERSION <= FcContentFeatures.SCHEMA_VERSION, "schema range")
	assert_true(FcContentFeatures.is_supported("pack_fixed_v1"), "known feature")
	assert_true(not FcContentFeatures.is_supported("pack_random_v9"), "unknown feature fails closed")
