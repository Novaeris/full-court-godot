extends FcTestCase
## Guards the "one canonical copy" rule: Creator Studio must see src/content through a link,
## never through a second editable copy of the files.


func _files(dir_path: String) -> Array:
	var d := DirAccess.open(dir_path)
	var out := []
	if d != null:
		out.append_array(d.get_files())
		out.sort()
	return out


func test_studio_link_matches_the_shared_source() -> void:
	var link := ProjectSettings.globalize_path("res://creator_studio/shared_content")
	assert_true(DirAccess.dir_exists_absolute(link),
		"creator_studio/shared_content is missing: run ./tools/link_studio.ps1")
	assert_eq(_files(link), _files(ProjectSettings.globalize_path("res://src/content")),
		"the link must show exactly the files in src/content")


func test_studio_link_is_never_tracked_by_git() -> void:
	var ignore := FileAccess.get_file_as_string("res://.gitignore")
	assert_true(ignore.contains("/creator_studio/shared_content"), ".gitignore must exclude the link")


func test_supported_schema_range_is_consistent() -> void:
	assert_true(FcContentFeatures.MIN_SCHEMA_VERSION <= FcContentFeatures.SCHEMA_VERSION, "schema range")
	assert_true(FcContentFeatures.is_supported("pack_fixed_v1"), "known feature")
	assert_true(not FcContentFeatures.is_supported("pack_random_v9"), "unknown feature fails closed")
